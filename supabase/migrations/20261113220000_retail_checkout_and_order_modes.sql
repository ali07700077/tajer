-- Retail checkout: preserve the existing B2B/RFQ order model while adding authenticated B2C orders.
alter table public.orders
  alter column buyer_business_id drop not null,
  add column if not exists buyer_user_id uuid references public.profiles(id) on delete restrict,
  add column if not exists order_type text not null default 'b2b';

do $$
begin
  if not exists (select 1 from pg_constraint where conname='orders_order_type_check') then
    alter table public.orders add constraint orders_order_type_check
      check (order_type in ('b2b','b2c'));
  end if;
  if not exists (select 1 from pg_constraint where conname='orders_buyer_identity_check') then
    alter table public.orders add constraint orders_buyer_identity_check
      check (
        (order_type='b2b' and buyer_business_id is not null and buyer_user_id is null)
        or
        (order_type='b2c' and buyer_business_id is null and buyer_user_id is not null and rfq_id is null)
      );
  end if;
end $$;

create index if not exists orders_b2c_buyer_created_idx
  on public.orders (buyer_user_id, created_at desc) where order_type='b2c';

alter table public.orders enable row level security;
alter table public.order_items enable row level security;

drop policy if exists orders_select_participant on public.orders;
create policy orders_select_participant on public.orders
for select to authenticated
using (
  buyer_user_id = (select auth.uid())
  or public.has_business_role(buyer_business_id, array['owner'::public.member_role,'manager'::public.member_role])
  or public.has_business_role(supplier_business_id, array['owner'::public.member_role,'manager'::public.member_role])
);

drop policy if exists order_items_select_participant on public.order_items;
create policy order_items_select_participant on public.order_items
for select to authenticated
using (exists (
  select 1 from public.orders o
  where o.id=order_items.order_id
    and (
      o.buyer_user_id=(select auth.uid())
      or public.has_business_role(o.buyer_business_id, array['owner'::public.member_role,'manager'::public.member_role])
      or public.has_business_role(o.supplier_business_id, array['owner'::public.member_role,'manager'::public.member_role])
    )
));

grant select on public.orders, public.order_items to authenticated;
revoke insert, update, delete on public.orders, public.order_items from anon, authenticated;

create or replace function public.create_retail_orders(p_items jsonb, p_delivery_address text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_item jsonb;
  v_product public.products%rowtype;
  v_supplier_id uuid;
  v_order_id uuid;
  v_quantity integer;
  v_total numeric(14,2);
  v_result jsonb := '[]'::jsonb;
  v_count integer;
  v_distinct_count integer;
begin
  if v_user_id is null then raise exception 'يجب تسجيل الدخول لإتمام طلب المفرد'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) < 1 or jsonb_array_length(p_items) > 50 then
    raise exception 'سلة المفرد غير صالحة';
  end if;
  if length(trim(coalesce(p_delivery_address,''))) < 8 then
    raise exception 'يرجى إدخال عنوان توصيل واضح';
  end if;

  select count(*), count(distinct (value->>'product_id'))
    into v_count, v_distinct_count
  from jsonb_array_elements(p_items);
  if v_count <> v_distinct_count then raise exception 'لا تكرر المنتج نفسه في السلة'; end if;

  -- Lock every requested product in stable order to prevent overselling and deadlocks.
  for v_product in
    select p.* from public.products p
    join jsonb_array_elements(p_items) i on p.id=(i.value->>'product_id')::uuid
    order by p.id
    for update of p
  loop
    select value into v_item from jsonb_array_elements(p_items)
      where value->>'product_id'=v_product.id::text;
    if coalesce(v_item->>'quantity','') !~ '^[1-9][0-9]*$' then
      raise exception 'كمية المنتج يجب أن تكون عدداً صحيحاً موجباً';
    end if;
    v_quantity := (v_item->>'quantity')::integer;
    if not v_product.is_active or not v_product.is_retail_available or v_product.retail_price is null then
      raise exception 'أحد المنتجات لم يعد متاحاً للبيع بالمفرد';
    end if;
    if not exists (
      select 1 from public.businesses b
      where b.id=v_product.business_id
        and b.business_type='supplier'::public.business_type
        and b.is_active and b.verification_status='approved'::public.verification_status
    ) then
      raise exception 'المورد غير معتمد أو غير نشط';
    end if;
    if v_quantity > v_product.stock_quantity then raise exception 'الكمية المطلوبة تتجاوز المخزون المتاح'; end if;
  end loop;

  if v_count <> (select count(*) from public.products p
      where p.id in (select (value->>'product_id')::uuid from jsonb_array_elements(p_items))) then
    raise exception 'أحد المنتجات غير موجود';
  end if;

  for v_supplier_id in
    select distinct p.business_id
    from public.products p
    join jsonb_array_elements(p_items) i on p.id=(i.value->>'product_id')::uuid
    order by p.business_id
  loop
    v_order_id := gen_random_uuid();
    v_total := 0;
    insert into public.orders(id,buyer_business_id,buyer_user_id,supplier_business_id,order_type,status,total_amount,currency,delivery_address)
    values(v_order_id,null,v_user_id,v_supplier_id,'b2c','pending',0,'IQD',trim(p_delivery_address));

    for v_item in select value from jsonb_array_elements(p_items)
    loop
      select * into v_product from public.products
      where id=(v_item->>'product_id')::uuid and business_id=v_supplier_id;
      if found then
        v_quantity := (v_item->>'quantity')::integer;
        insert into public.order_items(order_id,product_id,product_name,quantity,unit_price)
        values(v_order_id,v_product.id,v_product.name,v_quantity,v_product.retail_price);
        update public.products set stock_quantity=stock_quantity-v_quantity, updated_at=now()
        where id=v_product.id;
        v_total := v_total + (v_product.retail_price * v_quantity);
      end if;
    end loop;

    update public.orders set total_amount=v_total, updated_at=now() where id=v_order_id;
    v_result := v_result || jsonb_build_array(jsonb_build_object('order_id',v_order_id,'supplier_business_id',v_supplier_id,'total_amount',v_total));
  end loop;
  return v_result;
end;
$$;

revoke all on function public.create_retail_orders(jsonb,text) from public, anon;
grant execute on function public.create_retail_orders(jsonb,text) to authenticated;

-- Keep wholesale volume discounts monotonic as quantity thresholds increase.
create or replace function public.validate_product_price_tier()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  product_row public.products%rowtype;
begin
  select * into product_row from public.products where id=new.product_id;
  if not found then raise exception 'المنتج غير موجود'; end if;
  if new.min_quantity < product_row.min_order_quantity then
    raise exception 'كمية شريحة السعر أقل من الحد الأدنى للطلب';
  end if;
  if new.unit_price > product_row.price then
    raise exception 'سعر شريحة الجملة يجب ألا يتجاوز سعر الجملة الأساسي';
  end if;
  if exists (
    select 1 from public.product_price_tiers t
    where t.product_id=new.product_id and t.id<>new.id
      and (
        (t.min_quantity < new.min_quantity and t.unit_price < new.unit_price)
        or
        (t.min_quantity > new.min_quantity and t.unit_price > new.unit_price)
      )
  ) then
    raise exception 'يجب ألا يرتفع سعر الوحدة مع زيادة كمية الجملة';
  end if;
  return new;
end;
$$;

drop trigger if exists product_price_tiers_validate on public.product_price_tiers;
create trigger product_price_tiers_validate
before insert or update of product_id,min_quantity,unit_price
on public.product_price_tiers
for each row execute function public.validate_product_price_tier();

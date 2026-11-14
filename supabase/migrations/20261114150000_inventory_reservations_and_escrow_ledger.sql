-- Atomic inventory reservations and append-only escrow event ledger.
-- Checkout creates supplier orders and holds stock for 15 minutes. Payment-provider
-- webhooks must call confirm_inventory_reservation only after verified capture.
alter table public.products
  add column if not exists reserved_quantity integer not null default 0;
do $$
begin
  if not exists (select 1 from pg_constraint where conname='products_reserved_quantity_nonnegative') then
    alter table public.products add constraint products_reserved_quantity_nonnegative check (reserved_quantity >= 0);
  end if;
  if not exists (select 1 from pg_constraint where conname='products_reserved_not_above_stock') then
    alter table public.products add constraint products_reserved_not_above_stock check (reserved_quantity <= stock_quantity);
  end if;
end $$;
alter table public.products
  add column if not exists available_quantity integer generated always as (stock_quantity - reserved_quantity) stored;

create table if not exists public.inventory_reservations (
  id uuid primary key default extensions.gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete restrict,
  product_id uuid not null references public.products(id) on delete restrict,
  supplier_business_id uuid not null references public.businesses(id) on delete restrict,
  quantity integer not null check (quantity > 0),
  status text not null default 'held' check (status in ('held','committed','released')),
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  unique(order_id, product_id),
  check ((status='held' and resolved_at is null) or (status<>'held' and resolved_at is not null))
);
create index if not exists inventory_reservations_expiry_idx
  on public.inventory_reservations(expires_at) where status='held';
create index if not exists inventory_reservations_order_idx
  on public.inventory_reservations(order_id, status);

alter table public.inventory_reservations enable row level security;
revoke all on public.inventory_reservations from anon, authenticated;
grant select on public.inventory_reservations to authenticated;
create policy inventory_reservations_participant_read on public.inventory_reservations
for select to authenticated using (
  exists (select 1 from public.orders o where o.id=inventory_reservations.order_id
    and (
      o.buyer_user_id=(select auth.uid())
      or public.has_business_role(o.buyer_business_id,array['owner'::public.member_role,'manager'::public.member_role])
      or public.has_business_role(o.supplier_business_id,array['owner'::public.member_role,'manager'::public.member_role])
    ))
);

create table if not exists public.escrow_ledger_entries (
  id uuid primary key default extensions.gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete restrict,
  entry_type text not null check (entry_type in ('authorized','captured','released','refunded','payout','dispute_opened','dispute_closed')),
  amount numeric(14,2) not null check (amount > 0),
  currency text not null default 'IQD' check (currency='IQD'),
  provider_reference text,
  idempotency_key text not null,
  metadata jsonb not null default '{}'::jsonb,
  actor_id uuid, -- immutable actor identifier; deliberately not FK-cascaded
  created_at timestamptz not null default now(),
  unique(order_id,idempotency_key)
);
create index if not exists escrow_ledger_order_created_idx
  on public.escrow_ledger_entries(order_id,created_at);
alter table public.escrow_ledger_entries enable row level security;
revoke all on public.escrow_ledger_entries from anon, authenticated;
grant select on public.escrow_ledger_entries to authenticated;
create policy escrow_ledger_participant_read on public.escrow_ledger_entries
for select to authenticated using (
  exists (select 1 from public.orders o where o.id=escrow_ledger_entries.order_id
    and (
      o.buyer_user_id=(select auth.uid())
      or public.has_business_role(o.buyer_business_id,array['owner'::public.member_role,'manager'::public.member_role])
      or public.has_business_role(o.supplier_business_id,array['owner'::public.member_role,'manager'::public.member_role])
    ))
);

create or replace function public.reject_escrow_ledger_mutation()
returns trigger language plpgsql set search_path='' as $$
begin
  raise exception 'سجل الضمان المالي غير قابل للتعديل أو الحذف' using errcode='55000';
end;
$$;
drop trigger if exists escrow_ledger_entries_immutable on public.escrow_ledger_entries;
create trigger escrow_ledger_entries_immutable before update or delete on public.escrow_ledger_entries
for each row execute function public.reject_escrow_ledger_mutation();

create or replace function public.append_escrow_ledger_entry(
  p_order_id uuid, p_entry_type text, p_amount numeric, p_idempotency_key text,
  p_provider_reference text default null, p_metadata jsonb default '{}'::jsonb
) returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
  if not exists (select 1 from public.orders where id=p_order_id) then
    raise exception 'الطلب غير موجود' using errcode='22023';
  end if;
  if p_amount is null or p_amount<=0 or length(trim(coalesce(p_idempotency_key,'')))<8 then
    raise exception 'بيانات القيد المالي غير صالحة' using errcode='22023';
  end if;
  insert into public.escrow_ledger_entries(order_id,entry_type,amount,idempotency_key,provider_reference,metadata,actor_id)
  values(p_order_id,p_entry_type,p_amount,trim(p_idempotency_key),nullif(trim(coalesce(p_provider_reference,'')),''),coalesce(p_metadata,'{}'::jsonb),auth.uid())
  on conflict(order_id,idempotency_key) do nothing;
  select id into v_id from public.escrow_ledger_entries where order_id=p_order_id and idempotency_key=trim(p_idempotency_key);
  return v_id;
end;
$$;

create or replace function public.confirm_inventory_reservation(p_order_id uuid)
returns integer language plpgsql security definer set search_path='' as $$
declare v_res record; v_count integer:=0;
begin
  if not exists(select 1 from public.inventory_reservations where order_id=p_order_id) then
    raise exception 'لا توجد حجوزات مخزون لهذا الطلب' using errcode='22023';
  end if;
  perform 1 from public.orders where id=p_order_id for update;
  if exists(select 1 from public.inventory_reservations where order_id=p_order_id and (status<>'held' or expires_at<=now())) then
    raise exception 'انتهت صلاحية حجز المخزون أو تمت معالجته مسبقاً' using errcode='55000';
  end if;
  for v_res in
    select * from public.inventory_reservations where order_id=p_order_id order by product_id for update
  loop
    update public.products
      set stock_quantity=stock_quantity-v_res.quantity,
          reserved_quantity=reserved_quantity-v_res.quantity,
          updated_at=now()
    where id=v_res.product_id and reserved_quantity>=v_res.quantity and stock_quantity>=v_res.quantity;
    if not found then raise exception 'تعذر تثبيت حجز المخزون' using errcode='23514'; end if;
    update public.inventory_reservations set status='committed',resolved_at=now() where id=v_res.id;
    v_count:=v_count+1;
  end loop;
  return v_count;
end;
$$;

create or replace function public.release_expired_inventory_reservations(p_limit integer default 250)
returns integer language plpgsql security definer set search_path='' as $$
declare v_res record; v_count integer:=0;
begin
  if p_limit<1 or p_limit>1000 then raise exception 'حد المعالجة غير صالح' using errcode='22023'; end if;
  for v_res in
    select * from public.inventory_reservations
    where status='held' and expires_at<=now()
    order by expires_at,id
    limit p_limit
    for update skip locked
  loop
    update public.products set reserved_quantity=reserved_quantity-v_res.quantity,updated_at=now()
      where id=v_res.product_id and reserved_quantity>=v_res.quantity;
    if not found then raise exception 'تعذر تحرير الكمية المحجوزة' using errcode='23514'; end if;
    update public.inventory_reservations set status='released',resolved_at=now() where id=v_res.id;
    v_count:=v_count+1;
  end loop;
  return v_count;
end;
$$;

revoke all on function public.append_escrow_ledger_entry(uuid,text,numeric,text,text,jsonb) from public,anon,authenticated;
revoke all on function public.confirm_inventory_reservation(uuid) from public,anon,authenticated;
revoke all on function public.release_expired_inventory_reservations(integer) from public,anon,authenticated;
grant execute on function public.append_escrow_ledger_entry(uuid,text,numeric,text,text,jsonb) to service_role;
grant execute on function public.confirm_inventory_reservation(uuid) to service_role;
grant execute on function public.release_expired_inventory_reservations(integer) to service_role;

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

  perform public.release_expired_inventory_reservations(250);

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
    if v_quantity > v_product.available_quantity then raise exception 'الكمية المطلوبة تتجاوز المخزون المتاح'; end if;
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
    v_order_id := extensions.gen_random_uuid();
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
        update public.products set reserved_quantity=reserved_quantity+v_quantity, updated_at=now()
        where id=v_product.id;
        insert into public.inventory_reservations(order_id,product_id,supplier_business_id,quantity,status,expires_at)
        values(v_order_id,v_product.id,v_supplier_id,v_quantity,'held',now()+interval '15 minutes');
        v_total := v_total + (v_product.retail_price * v_quantity);
      end if;
    end loop;

    update public.orders set total_amount=v_total, updated_at=now() where id=v_order_id;
    v_result := v_result || jsonb_build_array(jsonb_build_object('order_id',v_order_id,'supplier_business_id',v_supplier_id,'total_amount',v_total));
  end loop;
  return v_result;
end;
$$;

create or replace function public.create_wholesale_orders(
  p_buyer_business_id uuid,
  p_items jsonb,
  p_delivery_address text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_item jsonb;
  v_product public.products%rowtype;
  v_supplier_id uuid;
  v_order_id uuid;
  v_quantity integer;
  v_unit_price numeric(14,2);
  v_total numeric(14,2);
  v_result jsonb := '[]'::jsonb;
  v_item_count integer;
  v_distinct_count integer;
begin
  if v_user_id is null then
    raise exception 'يجب تسجيل الدخول لإتمام طلب الجملة' using errcode = '28000';
  end if;
  if not public.has_business_role(p_buyer_business_id, array['owner'::public.member_role,'manager'::public.member_role]) then
    raise exception 'ليس لديك صلاحية الشراء باسم هذه الشركة' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.businesses
    where id = p_buyer_business_id and business_type = 'buyer'::public.business_type and is_active
  ) then
    raise exception 'ملف المشتري غير صالح أو غير نشط' using errcode = '22023';
  end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) < 1 or jsonb_array_length(p_items) > 50 then
    raise exception 'سلة الجملة غير صالحة' using errcode = '22023';
  end if;
  if char_length(trim(coalesce(p_delivery_address,''))) < 8 then
    raise exception 'يرجى إدخال عنوان توصيل واضح' using errcode = '22023';
  end if;

  perform public.release_expired_inventory_reservations(250);

  select count(*), count(distinct value->>'product_id')
    into v_item_count, v_distinct_count
  from jsonb_array_elements(p_items);
  if v_item_count <> v_distinct_count then
    raise exception 'لا تكرر المنتج نفسه في السلة' using errcode = '22023';
  end if;

  -- Lock all products in deterministic order. Concurrent checkouts serialize here.
  for v_product in
    select p.*
    from public.products p
    join jsonb_array_elements(p_items) item on p.id = (item.value->>'product_id')::uuid
    order by p.id
    for update of p
  loop
    select value into v_item
    from jsonb_array_elements(p_items)
    where value->>'product_id' = v_product.id::text;

    if coalesce(v_item->>'quantity','') !~ '^[1-9][0-9]*$' then
      raise exception 'كمية المنتج يجب أن تكون عدداً صحيحاً موجباً' using errcode = '22023';
    end if;
    v_quantity := (v_item->>'quantity')::integer;
    if not v_product.is_active then
      raise exception 'أحد المنتجات غير منشور' using errcode = '22023';
    end if;
    if v_quantity < v_product.min_order_quantity then
      raise exception 'الكمية أقل من الحد الأدنى للطلب (MOQ)' using errcode = '23514';
    end if;
    if v_quantity > v_product.available_quantity then
      raise exception 'الكمية المطلوبة تتجاوز المخزون المتاح' using errcode = '23514';
    end if;
    if not exists (
      select 1 from public.businesses supplier
      where supplier.id = v_product.business_id
        and supplier.business_type = 'supplier'::public.business_type
        and supplier.is_active
        and supplier.verification_status = 'approved'::public.verification_status
    ) then
      raise exception 'أحد الموردين غير معتمد أو غير نشط' using errcode = '23514';
    end if;
  end loop;

  if v_item_count <> (
    select count(*) from public.products p
    where p.id in (select (value->>'product_id')::uuid from jsonb_array_elements(p_items))
  ) then
    raise exception 'أحد المنتجات غير موجود' using errcode = '22023';
  end if;

  -- One independent order per supplier, preserving one transaction for the whole basket.
  for v_supplier_id in
    select distinct p.business_id
    from public.products p
    join jsonb_array_elements(p_items) item on p.id = (item.value->>'product_id')::uuid
    order by p.business_id
  loop
    v_order_id := extensions.gen_random_uuid();
    v_total := 0;
    insert into public.orders (
      id, buyer_business_id, buyer_user_id, supplier_business_id,
      order_type, status, total_amount, currency, delivery_address
    ) values (
      v_order_id, p_buyer_business_id, null, v_supplier_id,
      'b2b', 'pending', 0, 'IQD', trim(p_delivery_address)
    );

    for v_item in
      select item.value
      from jsonb_array_elements(p_items) item
      join public.products p on p.id = (item.value->>'product_id')::uuid
      where p.business_id = v_supplier_id
      order by p.id
    loop
      select * into v_product
      from public.products p
      where p.id = (v_item->>'product_id')::uuid
      for update;

      v_quantity := (v_item->>'quantity')::integer;
      select coalesce((
        select tier.unit_price
        from public.product_price_tiers tier
        where tier.product_id = v_product.id and tier.min_quantity <= v_quantity
        order by tier.min_quantity desc
        limit 1
      ), v_product.price)
      into v_unit_price;

      insert into public.order_items(order_id,product_id,product_name,quantity,unit_price)
      values(v_order_id,v_product.id,v_product.name,v_quantity,v_unit_price);

      update public.products
      set reserved_quantity = reserved_quantity + v_quantity, updated_at = now()
      where id = v_product.id;

      insert into public.inventory_reservations(order_id, product_id, supplier_business_id, quantity, status, expires_at)
      values(v_order_id, v_product.id, v_supplier_id, v_quantity, 'held', now() + interval '15 minutes');

      v_total := v_total + (v_unit_price * v_quantity);
    end loop;

    update public.orders
    set total_amount = v_total, updated_at = now()
    where id = v_order_id;

    v_result := v_result || jsonb_build_array(jsonb_build_object(
      'order_id', v_order_id,
      'supplier_business_id', v_supplier_id,
      'total_amount', v_total
    ));
  end loop;
  return v_result;
end;
$function$;

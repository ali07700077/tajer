-- B2B multi-supplier checkout, sample requests, and proforma invoices.
-- All checkout pricing and stock changes are performed atomically inside PostgreSQL.

alter table public.products
  add column if not exists sample_available boolean not null default false,
  add column if not exists sample_price numeric(14,2),
  add column if not exists sample_max_quantity integer not null default 1;

do $$
begin
  if not exists (select 1 from pg_constraint where conname='products_sample_price_positive') then
    alter table public.products add constraint products_sample_price_positive
      check (sample_price is null or sample_price > 0);
  end if;
  if not exists (select 1 from pg_constraint where conname='products_sample_configuration_check') then
    alter table public.products add constraint products_sample_configuration_check
      check (
        (sample_available = false and sample_price is null)
        or
        (sample_available = true and sample_price is not null and sample_max_quantity between 1 and 10)
      );
  end if;
end $$;

create table if not exists public.product_sample_requests (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete restrict,
  buyer_business_id uuid not null references public.businesses(id) on delete restrict,
  supplier_business_id uuid not null references public.businesses(id) on delete restrict,
  requested_by uuid not null references public.profiles(id) on delete restrict,
  quantity integer not null check (quantity between 1 and 10),
  unit_price numeric(14,2) not null check (unit_price > 0),
  total_amount numeric(14,2) generated always as (quantity * unit_price) stored,
  status text not null default 'pending_payment'
    check (status in ('pending_payment','paid','processing','shipped','delivered','cancelled')),
  delivery_address text not null check (char_length(trim(delivery_address)) >= 8),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists product_sample_requests_buyer_idx
  on public.product_sample_requests (buyer_business_id, created_at desc);
create index if not exists product_sample_requests_supplier_idx
  on public.product_sample_requests (supplier_business_id, created_at desc);

alter table public.product_sample_requests enable row level security;
revoke all on public.product_sample_requests from anon, authenticated;
grant select on public.product_sample_requests to authenticated;
create policy product_sample_requests_participant_read
  on public.product_sample_requests for select to authenticated
  using (
    requested_by = (select auth.uid())
    or public.has_business_role(buyer_business_id, array['owner'::public.member_role,'manager'::public.member_role])
    or public.has_business_role(supplier_business_id, array['owner'::public.member_role,'manager'::public.member_role])
  );

create table if not exists public.proforma_invoices (
  id uuid primary key default gen_random_uuid(),
  invoice_number text not null unique,
  order_id uuid not null unique references public.orders(id) on delete restrict,
  supplier_business_id uuid not null references public.businesses(id) on delete restrict,
  buyer_business_id uuid not null references public.businesses(id) on delete restrict,
  currency text not null default 'IQD' check (currency = 'IQD'),
  subtotal numeric(14,2) not null check (subtotal > 0),
  terms text,
  issued_at timestamptz not null default now(),
  valid_until date,
  status text not null default 'issued' check (status in ('draft','issued','accepted','expired','cancelled')),
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  check (valid_until is null or valid_until >= issued_at::date)
);

create table if not exists public.proforma_invoice_items (
  id uuid primary key default gen_random_uuid(),
  proforma_invoice_id uuid not null references public.proforma_invoices(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  product_name text not null,
  quantity numeric(14,2) not null check (quantity > 0),
  unit_price numeric(14,2) not null check (unit_price > 0),
  line_total numeric(14,2) generated always as (quantity * unit_price) stored
);

create index if not exists proforma_invoices_supplier_idx
  on public.proforma_invoices (supplier_business_id, issued_at desc);
create index if not exists proforma_invoices_buyer_idx
  on public.proforma_invoices (buyer_business_id, issued_at desc);

alter table public.proforma_invoices enable row level security;
alter table public.proforma_invoice_items enable row level security;
revoke all on public.proforma_invoices, public.proforma_invoice_items from anon, authenticated;
grant select on public.proforma_invoices, public.proforma_invoice_items to authenticated;

create policy proforma_invoices_participant_read
  on public.proforma_invoices for select to authenticated
  using (
    public.has_business_role(buyer_business_id, array['owner'::public.member_role,'manager'::public.member_role])
    or public.has_business_role(supplier_business_id, array['owner'::public.member_role,'manager'::public.member_role])
  );

create policy proforma_invoice_items_participant_read
  on public.proforma_invoice_items for select to authenticated
  using (exists (
    select 1 from public.proforma_invoices invoice
    where invoice.id = proforma_invoice_items.proforma_invoice_id
      and (
        public.has_business_role(invoice.buyer_business_id, array['owner'::public.member_role,'manager'::public.member_role])
        or public.has_business_role(invoice.supplier_business_id, array['owner'::public.member_role,'manager'::public.member_role])
      )
  ));

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
    if v_quantity > v_product.stock_quantity then
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
      set stock_quantity = stock_quantity - v_quantity, updated_at = now()
      where id = v_product.id;

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

create or replace function public.create_product_sample_request(
  p_buyer_business_id uuid,
  p_product_id uuid,
  p_quantity integer,
  p_delivery_address text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_product public.products%rowtype;
  v_request_id uuid;
begin
  if auth.uid() is null then
    raise exception 'يجب تسجيل الدخول لطلب العينة' using errcode = '28000';
  end if;
  if not public.has_business_role(p_buyer_business_id, array['owner'::public.member_role,'manager'::public.member_role]) then
    raise exception 'ليس لديك صلاحية الطلب باسم هذه الشركة' using errcode = '42501';
  end if;
  select * into v_product from public.products where id = p_product_id;
  if not found or not v_product.is_active or not v_product.sample_available or v_product.sample_price is null then
    raise exception 'العينة غير متاحة لهذا المنتج' using errcode = '22023';
  end if;
  if p_quantity < 1 or p_quantity > v_product.sample_max_quantity then
    raise exception 'كمية العينة تتجاوز الحد المسموح' using errcode = '22023';
  end if;
  if char_length(trim(coalesce(p_delivery_address,''))) < 8 then
    raise exception 'يرجى إدخال عنوان توصيل واضح' using errcode = '22023';
  end if;
  insert into public.product_sample_requests (
    product_id,buyer_business_id,supplier_business_id,requested_by,
    quantity,unit_price,delivery_address
  ) values (
    v_product.id,p_buyer_business_id,v_product.business_id,auth.uid(),
    p_quantity,v_product.sample_price,trim(p_delivery_address)
  ) returning id into v_request_id;
  return v_request_id;
end;
$function$;

create or replace function public.create_proforma_invoice(
  p_order_id uuid,
  p_valid_until date default null,
  p_terms text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_order public.orders%rowtype;
  v_invoice_id uuid;
  v_invoice_number text;
begin
  if auth.uid() is null then
    raise exception 'يجب تسجيل الدخول' using errcode = '28000';
  end if;
  select * into v_order from public.orders where id = p_order_id for update;
  if not found or v_order.order_type <> 'b2b' or v_order.status = 'cancelled' then
    raise exception 'الطلب غير صالح لإصدار فاتورة أولية' using errcode = '22023';
  end if;
  if not public.has_business_role(v_order.supplier_business_id, array['owner'::public.member_role,'manager'::public.member_role]) then
    raise exception 'إصدار الفاتورة متاح للمورد صاحب الطلب فقط' using errcode = '42501';
  end if;
  if p_valid_until is not null and p_valid_until < current_date then
    raise exception 'تاريخ صلاحية الفاتورة يجب ألا يكون في الماضي' using errcode = '22023';
  end if;

  v_invoice_number := 'PI-' || to_char(current_date,'YYYYMMDD') || '-' || upper(substr(replace(extensions.gen_random_uuid()::text,'-',''),1,8));
  insert into public.proforma_invoices (
    invoice_number,order_id,supplier_business_id,buyer_business_id,
    subtotal,terms,valid_until,created_by
  ) values (
    v_invoice_number,v_order.id,v_order.supplier_business_id,v_order.buyer_business_id,
    v_order.total_amount,nullif(trim(coalesce(p_terms,'')),''),p_valid_until,auth.uid()
  ) returning id into v_invoice_id;

  insert into public.proforma_invoice_items (
    proforma_invoice_id,product_id,product_name,quantity,unit_price
  )
  select v_invoice_id,product_id,product_name,quantity,unit_price
  from public.order_items
  where order_id = v_order.id;

  return v_invoice_id;
end;
$function$;

revoke all on function public.create_wholesale_orders(uuid,jsonb,text) from public, anon;
revoke all on function public.create_product_sample_request(uuid,uuid,integer,text) from public, anon;
revoke all on function public.create_proforma_invoice(uuid,date,text) from public, anon;
grant execute on function public.create_wholesale_orders(uuid,jsonb,text) to authenticated;
grant execute on function public.create_product_sample_request(uuid,uuid,integer,text) to authenticated;
grant execute on function public.create_proforma_invoice(uuid,date,text) to authenticated;

grant select on public.product_sample_requests, public.proforma_invoices, public.proforma_invoice_items to authenticated;

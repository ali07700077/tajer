-- Phase 3: product-scoped RFQs, supplier quotations, buyer acceptance and row isolation.
alter table public.rfqs add column if not exists awarded_offer_id uuid;
alter table public.rfq_offers add column if not exists total_price numeric(14,2);
alter table public.rfq_offers add constraint rfq_offers_total_price_positive check (total_price is null or total_price > 0) not valid;

create table if not exists public.rfq_items (
  id uuid primary key default gen_random_uuid(),
  rfq_id uuid not null references public.rfqs(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  supplier_business_id uuid not null references public.businesses(id) on delete restrict,
  quantity integer not null check (quantity > 0),
  created_at timestamptz not null default now(),
  unique (rfq_id, product_id)
);
create index if not exists rfq_items_supplier_idx on public.rfq_items(supplier_business_id, created_at desc);
create index if not exists rfq_items_product_idx on public.rfq_items(product_id);
create index if not exists rfqs_buyer_created_idx on public.rfqs(buyer_business_id, created_at desc);
create index if not exists rfq_offers_rfq_idx on public.rfq_offers(rfq_id, created_at desc);
alter table public.rfq_offers add constraint rfq_offers_one_per_supplier unique (rfq_id, supplier_business_id);

create or replace function public.validate_rfq_item()
returns trigger language plpgsql set search_path = public
as $$
declare product_row public.products%rowtype;
begin
  select * into product_row from public.products where id = new.product_id;
  if not found or not product_row.is_active then raise exception 'المنتج غير متاح لطلب عرض السعر'; end if;
  if not exists (select 1 from public.businesses b where b.id=product_row.business_id and b.business_type='supplier' and b.is_active and b.verification_status='approved') then
    raise exception 'المورد غير معتمد أو غير نشط';
  end if;
  new.supplier_business_id := product_row.business_id;
  if new.quantity < product_row.min_order_quantity then raise exception 'الكمية أقل من الحد الأدنى للطلب'; end if;
  return new;
end;
$$;
drop trigger if exists rfq_items_validate on public.rfq_items;
create trigger rfq_items_validate before insert or update of product_id, quantity on public.rfq_items
for each row execute function public.validate_rfq_item();

alter table public.rfq_items enable row level security;
drop policy if exists rfqs_read_policy on public.rfqs;
drop policy if exists rfqs_insert_policy on public.rfqs;
drop policy if exists rfqs_update_policy on public.rfqs;
drop policy if exists rfqs_buyer_supplier_read on public.rfqs;
drop policy if exists rfqs_buyer_insert on public.rfqs;
drop policy if exists rfqs_buyer_update on public.rfqs;
create policy rfqs_buyer_supplier_read on public.rfqs for select to authenticated
using (
  public.is_business_member(buyer_business_id)
  or exists (select 1 from public.rfq_items ri where ri.rfq_id=rfqs.id and public.has_business_role(ri.supplier_business_id,array['owner'::public.member_role,'manager'::public.member_role,'staff'::public.member_role]))
);
create policy rfqs_buyer_insert on public.rfqs for insert to authenticated
with check (
  status='open' and awarded_offer_id is null
  and public.is_business_member(buyer_business_id)
  and exists (select 1 from public.businesses b where b.id=buyer_business_id and b.business_type='buyer' and b.is_active)
);
create policy rfqs_buyer_update on public.rfqs for update to authenticated
using (public.is_business_member(buyer_business_id))
with check (public.is_business_member(buyer_business_id));

drop policy if exists rfq_items_buyer_supplier_read on public.rfq_items;
drop policy if exists rfq_items_buyer_insert on public.rfq_items;
create policy rfq_items_buyer_supplier_read on public.rfq_items for select to authenticated
using (
  exists (select 1 from public.rfqs r where r.id=rfq_id and public.is_business_member(r.buyer_business_id))
  or public.has_business_role(supplier_business_id,array['owner'::public.member_role,'manager'::public.member_role,'staff'::public.member_role])
);
create policy rfq_items_buyer_insert on public.rfq_items for insert to authenticated
with check (exists (select 1 from public.rfqs r where r.id=rfq_id and public.is_business_member(r.buyer_business_id)));

drop policy if exists rfq_offers_insert on public.rfq_offers;
drop policy if exists rfq_offers_select on public.rfq_offers;
drop policy if exists rfq_offers_update on public.rfq_offers;
drop policy if exists rfq_offers_supplier_buyer_read on public.rfq_offers;
drop policy if exists rfq_offers_supplier_insert on public.rfq_offers;
drop policy if exists rfq_offers_buyer_update on public.rfq_offers;
create policy rfq_offers_supplier_buyer_read on public.rfq_offers for select to authenticated
using (
  public.has_business_role(supplier_business_id,array['owner'::public.member_role,'manager'::public.member_role,'staff'::public.member_role])
  or exists (select 1 from public.rfqs r where r.id=rfq_id and public.is_business_member(r.buyer_business_id))
);
create policy rfq_offers_supplier_insert on public.rfq_offers for insert to authenticated
with check (
  status='submitted' and total_price is not null and total_price>0 and unit_price>0
  and (delivery_days is null or delivery_days>0)
  and public.has_business_role(supplier_business_id,array['owner'::public.member_role,'manager'::public.member_role])
  and exists (
    select 1 from public.rfq_items ri join public.rfqs r on r.id=ri.rfq_id
    where ri.rfq_id=rfq_offers.rfq_id and ri.supplier_business_id=rfq_offers.supplier_business_id
      and ri.quantity=rfq_offers.quantity and r.status in ('open','responded')
  )
);
create policy rfq_offers_buyer_update on public.rfq_offers for update to authenticated
using (exists (select 1 from public.rfqs r where r.id=rfq_id and public.is_business_member(r.buyer_business_id)))
with check (exists (select 1 from public.rfqs r where r.id=rfq_id and public.is_business_member(r.buyer_business_id)));

revoke update on public.rfqs from authenticated;
revoke update on public.rfq_offers from authenticated;
revoke update on public.rfq_items from authenticated;
grant select,insert on public.rfqs to authenticated;
grant select,insert on public.rfq_items to authenticated;
grant select,insert on public.rfq_offers to authenticated;

create or replace function public.create_rfq_for_product(p_buyer_business_id uuid,p_product_id uuid,p_quantity integer,p_notes text default null)
returns uuid language plpgsql security invoker set search_path=public
as $$
declare new_rfq_id uuid; product_name text;
begin
  if not public.is_business_member(p_buyer_business_id) then raise exception 'لا تملك صلاحية استخدام شركة المشتري المحددة'; end if;
  if not exists(select 1 from public.businesses b where b.id=p_buyer_business_id and b.business_type='buyer' and b.is_active) then raise exception 'اختر ملف شركة مشتري نشطاً'; end if;
  select name into product_name from public.products where id=p_product_id and is_active;
  if product_name is null then raise exception 'المنتج غير متاح'; end if;
  insert into public.rfqs(buyer_business_id,title,description,status) values(p_buyer_business_id,'طلب عرض سعر: '||product_name,nullif(trim(p_notes),''),'open') returning id into new_rfq_id;
  insert into public.rfq_items(rfq_id,product_id,supplier_business_id,quantity)
  select new_rfq_id,p.id,p.business_id,p_quantity from public.products p where p.id=p_product_id and p.is_active;
  return new_rfq_id;
end;
$$;
revoke all on function public.create_rfq_for_product(uuid,uuid,integer,text) from public,anon;
grant execute on function public.create_rfq_for_product(uuid,uuid,integer,text) to authenticated;

create or replace function public.submit_rfq_offer(p_rfq_id uuid,p_supplier_business_id uuid,p_total_price numeric,p_delivery_days integer,p_notes text default null)
returns uuid language plpgsql security definer set search_path=''
as $$
declare new_offer_id uuid; requested_quantity integer;
begin
  if auth.uid() is null then raise exception 'يجب تسجيل الدخول'; end if;
  if not public.has_business_role(p_supplier_business_id,array['owner'::public.member_role,'manager'::public.member_role]) then raise exception 'لا تملك صلاحية تقديم عرض لهذه الشركة'; end if;
  if p_total_price is null or p_total_price<=0 then raise exception 'أدخل سعراً إجمالياً صحيحاً'; end if;
  if p_delivery_days is null or p_delivery_days<1 then raise exception 'أدخل مدة توريد صحيحة'; end if;
  select ri.quantity into requested_quantity from public.rfq_items ri join public.rfqs r on r.id=ri.rfq_id
  where ri.rfq_id=p_rfq_id and ri.supplier_business_id=p_supplier_business_id and r.status in ('open','responded') for update of r;
  if requested_quantity is null then raise exception 'طلب العرض غير موجه لشركتك أو لم يعد مفتوحاً'; end if;
  insert into public.rfq_offers(rfq_id,supplier_business_id,unit_price,total_price,quantity,currency,delivery_days,notes,status)
  values(p_rfq_id,p_supplier_business_id,p_total_price/requested_quantity,p_total_price,requested_quantity,'IQD',p_delivery_days,nullif(trim(p_notes),''),'submitted') returning id into new_offer_id;
  update public.rfqs set status='responded',updated_at=now() where id=p_rfq_id and status='open';
  return new_offer_id;
end;
$$;
revoke all on function public.submit_rfq_offer(uuid,uuid,numeric,integer,text) from public,anon;
grant execute on function public.submit_rfq_offer(uuid,uuid,numeric,integer,text) to authenticated;

create or replace function public.accept_rfq_offer(p_offer_id uuid)
returns void language plpgsql security definer set search_path=''
as $$
declare target_rfq_id uuid;
begin
  if auth.uid() is null then raise exception 'يجب تسجيل الدخول'; end if;
  select o.rfq_id into target_rfq_id from public.rfq_offers o join public.rfqs r on r.id=o.rfq_id
  where o.id=p_offer_id and public.is_business_member(r.buyer_business_id) and r.status in ('open','responded') for update of r;
  if target_rfq_id is null then raise exception 'العرض غير موجود أو لا تملك صلاحية قبوله'; end if;
  update public.rfq_offers set status=case when id=p_offer_id then 'accepted' else 'rejected' end,updated_at=now() where rfq_id=target_rfq_id;
  update public.rfqs set status='awarded',awarded_offer_id=p_offer_id,updated_at=now() where id=target_rfq_id;
end;
$$;
revoke all on function public.accept_rfq_offer(uuid) from public,anon;
grant execute on function public.accept_rfq_offer(uuid) to authenticated;

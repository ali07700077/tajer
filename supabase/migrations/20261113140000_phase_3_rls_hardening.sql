-- Phase 3 hardening: safe public supplier names and non-recursive RFQ RLS predicates.
create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to anon, authenticated;
alter table public.rfqs drop constraint if exists rfqs_status_check;
alter table public.rfqs add constraint rfqs_status_check
check (status = any(array['open','responded','closed','awarded','cancelled']));

create or replace function public.get_public_supplier_names(p_business_ids uuid[] default null)
returns table(id uuid,name_ar text) language sql stable security definer set search_path=''
as $$
 select b.id,b.name_ar from public.businesses b
 where b.business_type='supplier' and b.is_active and b.verification_status='approved'
 and (p_business_ids is null or b.id=any(p_business_ids));
$$;
revoke all on function public.get_public_supplier_names(uuid[]) from public;
grant execute on function public.get_public_supplier_names(uuid[]) to anon,authenticated;

create or replace function private.is_approved_supplier(p_business_id uuid)
returns boolean language sql stable security definer set search_path=''
as $$
 select exists(select 1 from public.businesses b where b.id=p_business_id and b.business_type='supplier' and b.is_active and b.verification_status='approved');
$$;
revoke all on function private.is_approved_supplier(uuid) from public;
grant usage on schema private to anon,authenticated;
grant execute on function private.is_approved_supplier(uuid) to anon,authenticated;

drop policy if exists products_select_public_active on public.products;
create policy products_select_public_active on public.products for select to anon,authenticated
using (is_active and private.is_approved_supplier(business_id));

-- Explicit Data API grants: RLS controls rows; grants control whether the API can reach the table.
revoke all on table public.products from public, anon, authenticated;
grant select on table public.products to anon, authenticated;
grant insert (id, business_id, name, description, price, min_order_quantity, image_path, is_active)
  on table public.products to authenticated;
grant update (name, description, price, min_order_quantity, image_path, is_active)
  on table public.products to authenticated;
grant delete on table public.products to authenticated;

create or replace function public.validate_rfq_item()
returns trigger language plpgsql set search_path=''
as $
declare product_row public.products%rowtype;
begin
 select * into product_row from public.products where id=new.product_id;
 if not found or not product_row.is_active then raise exception 'المنتج غير متاح لطلب عرض السعر'; end if;
 if not private.is_approved_supplier(product_row.business_id) then raise exception 'المورد غير معتمد أو غير نشط'; end if;
 new.supplier_business_id:=product_row.business_id;
 if new.quantity<product_row.min_order_quantity then raise exception 'الكمية أقل من الحد الأدنى للطلب'; end if;
 return new;
end;
$$;

create or replace function private.is_rfq_buyer(p_rfq_id uuid)
returns boolean language sql stable security definer set search_path=''
as $$ select auth.uid() is not null and exists(select 1 from public.rfqs r where r.id=p_rfq_id and public.is_business_member(r.buyer_business_id)); $$;
create or replace function private.can_view_rfq(p_rfq_id uuid)
returns boolean language sql stable security definer set search_path=''
as $$
 select auth.uid() is not null and exists(select 1 from public.rfqs r where r.id=p_rfq_id and (
   public.is_business_member(r.buyer_business_id)
   or exists(select 1 from public.rfq_items ri where ri.rfq_id=r.id and public.has_business_role(ri.supplier_business_id,array['owner'::public.member_role,'manager'::public.member_role,'staff'::public.member_role]))
 ));
$$;
create or replace function private.can_view_rfq_item(p_rfq_id uuid,p_supplier_business_id uuid)
returns boolean language sql stable security definer set search_path=''
as $$ select auth.uid() is not null and (private.is_rfq_buyer(p_rfq_id) or public.has_business_role(p_supplier_business_id,array['owner'::public.member_role,'manager'::public.member_role,'staff'::public.member_role])); $$;
create or replace function private.can_submit_rfq_offer(p_rfq_id uuid,p_supplier_business_id uuid,p_quantity numeric)
returns boolean language sql stable security definer set search_path=''
as $$
 select auth.uid() is not null and public.has_business_role(p_supplier_business_id,array['owner'::public.member_role,'manager'::public.member_role])
 and private.is_approved_supplier(p_supplier_business_id)
 and exists(select 1 from public.rfq_items ri join public.rfqs r on r.id=ri.rfq_id where ri.rfq_id=p_rfq_id and ri.supplier_business_id=p_supplier_business_id and ri.quantity=p_quantity and r.status in ('open','responded'));
$$;
revoke all on function private.is_rfq_buyer(uuid) from public,anon;
revoke all on function private.can_view_rfq(uuid) from public,anon;
revoke all on function private.can_view_rfq_item(uuid,uuid) from public,anon;
revoke all on function private.can_submit_rfq_offer(uuid,uuid,numeric) from public,anon;
grant execute on function private.is_rfq_buyer(uuid) to authenticated;
grant execute on function private.can_view_rfq(uuid) to authenticated;
grant execute on function private.can_view_rfq_item(uuid,uuid) to authenticated;
grant execute on function private.can_submit_rfq_offer(uuid,uuid,numeric) to authenticated;

drop policy if exists rfqs_buyer_supplier_read on public.rfqs;
create policy rfqs_buyer_supplier_read on public.rfqs for select to authenticated using (private.can_view_rfq(id));
drop policy if exists rfq_items_buyer_supplier_read on public.rfq_items;
drop policy if exists rfq_items_buyer_insert on public.rfq_items;
create policy rfq_items_buyer_supplier_read on public.rfq_items for select to authenticated using (private.can_view_rfq_item(rfq_id,supplier_business_id));
create policy rfq_items_buyer_insert on public.rfq_items for insert to authenticated with check (
  private.is_rfq_buyer(rfq_id)
  and exists(select 1 from public.rfqs r where r.id=rfq_id and r.status in ('open','responded'))
);
drop policy if exists rfq_offers_supplier_buyer_read on public.rfq_offers;
drop policy if exists rfq_offers_supplier_insert on public.rfq_offers;
drop policy if exists rfq_offers_buyer_update on public.rfq_offers;
create policy rfq_offers_supplier_buyer_read on public.rfq_offers for select to authenticated
using (public.has_business_role(supplier_business_id,array['owner'::public.member_role,'manager'::public.member_role,'staff'::public.member_role]) or private.is_rfq_buyer(rfq_id));
create policy rfq_offers_supplier_insert on public.rfq_offers for insert to authenticated
with check (status='submitted' and total_price is not null and total_price>0 and unit_price>0 and (delivery_days is null or delivery_days>0) and private.can_submit_rfq_offer(rfq_id,supplier_business_id,quantity));

-- RFQ creation and line items are tenant-scoped; offer submission/award use validated RPCs.
revoke all on table public.rfqs, public.rfq_items from public, anon, authenticated;
grant select, insert on table public.rfqs, public.rfq_items to authenticated;
revoke all on table public.rfq_offers from public, anon, authenticated;
grant select on public.rfq_offers to authenticated;

alter table public.rfq_offers drop constraint if exists rfq_offers_one_per_supplier;
revoke all on function public.submit_rfq_offer(uuid,uuid,numeric,integer,text) from public,anon,authenticated;
revoke all on function public.accept_rfq_offer(uuid) from public,anon,authenticated;

-- Explicit access model for the tables used by the current application.
-- Reference data is public-read; company data remains tenant-scoped.
drop policy if exists governorates_active_read on public.governorates;
create policy governorates_active_read on public.governorates
for select to anon, authenticated using (is_active);
drop policy if exists cities_active_read on public.cities;
create policy cities_active_read on public.cities
for select to anon, authenticated using (is_active);
drop policy if exists categories_active_read on public.categories;
create policy categories_active_read on public.categories
for select to anon, authenticated using (is_active);

revoke all on table public.governorates, public.cities, public.categories from public, anon, authenticated;
grant select on table public.governorates, public.cities, public.categories to anon, authenticated;

revoke all on table public.businesses from public, anon, authenticated;
grant select on table public.businesses to authenticated;
grant update (name_ar, name_en, description_ar, phone, email, address_text, logo_path, city_id)
  on table public.businesses to authenticated;
drop policy if exists businesses_member_update on public.businesses;
create policy businesses_member_update on public.businesses
for update to authenticated
using (public.has_business_role(id, array['owner'::public.member_role,'manager'::public.member_role]))
with check (public.has_business_role(id, array['owner'::public.member_role,'manager'::public.member_role]));

revoke all on table public.business_members from public, anon, authenticated;
grant select on table public.business_members to authenticated;

revoke all on table public.profiles from public, anon, authenticated;
grant select on table public.profiles to authenticated;
grant update (full_name, phone) on table public.profiles to authenticated;
drop policy if exists profiles_select_self on public.profiles;
create policy profiles_select_self on public.profiles
for select to authenticated using (id = (select auth.uid()));
drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self on public.profiles
for update to authenticated
using (id = (select auth.uid()))
with check (id = (select auth.uid()));

-- Product quantity tiers inherit the visibility and ownership of their product.
drop policy if exists product_price_tiers_public_read on public.product_price_tiers;
create policy product_price_tiers_public_read on public.product_price_tiers
for select to anon, authenticated
using (exists (
  select 1 from public.products p
  where p.id = product_id and p.is_active and private.is_approved_supplier(p.business_id)
));
drop policy if exists product_price_tiers_supplier_read on public.product_price_tiers;
create policy product_price_tiers_supplier_read on public.product_price_tiers
for select to authenticated
using (exists (
  select 1 from public.products p
  where p.id = product_id
    and public.has_business_role(p.business_id, array['owner'::public.member_role,'manager'::public.member_role])
));
drop policy if exists product_price_tiers_supplier_insert on public.product_price_tiers;
create policy product_price_tiers_supplier_insert on public.product_price_tiers
for insert to authenticated
with check (exists (
  select 1 from public.products p
  where p.id = product_id
    and public.has_business_role(p.business_id, array['owner'::public.member_role,'manager'::public.member_role])
));
drop policy if exists product_price_tiers_supplier_update on public.product_price_tiers;
create policy product_price_tiers_supplier_update on public.product_price_tiers
for update to authenticated
using (exists (
  select 1 from public.products p
  where p.id = product_id
    and public.has_business_role(p.business_id, array['owner'::public.member_role,'manager'::public.member_role])
))
with check (exists (
  select 1 from public.products p
  where p.id = product_id
    and public.has_business_role(p.business_id, array['owner'::public.member_role,'manager'::public.member_role])
));
drop policy if exists product_price_tiers_supplier_delete on public.product_price_tiers;
create policy product_price_tiers_supplier_delete on public.product_price_tiers
for delete to authenticated
using (exists (
  select 1 from public.products p
  where p.id = product_id
    and public.has_business_role(p.business_id, array['owner'::public.member_role,'manager'::public.member_role])
));

revoke all on table public.product_price_tiers from public, anon, authenticated;
grant select on table public.product_price_tiers to anon, authenticated;
grant insert, update, delete on table public.product_price_tiers to authenticated;

-- Business creation is guarded inside the SECURITY DEFINER function; expose it only to signed-in users.
revoke all on function public.create_business(public.business_type, text, uuid, uuid, text) from public, anon, authenticated;
grant execute on function public.create_business(public.business_type, text, uuid, uuid, text) to authenticated;

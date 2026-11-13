-- Phase 3 hardening: safe public supplier names and non-recursive RFQ RLS predicates.
create or replace view public.public_supplier_directory
with (security_invoker=false, security_barrier=true)
as
select id,name_ar from public.businesses
where business_type='supplier' and is_active and verification_status='approved';
revoke all on public.public_supplier_directory from public;
grant select on public.public_supplier_directory to anon,authenticated;

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

create or replace function public.validate_rfq_item()
returns trigger language plpgsql set search_path=public
as $$
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
create policy rfq_items_buyer_insert on public.rfq_items for insert to authenticated with check (private.is_rfq_buyer(rfq_id));
drop policy if exists rfq_offers_supplier_buyer_read on public.rfq_offers;
drop policy if exists rfq_offers_supplier_insert on public.rfq_offers;
drop policy if exists rfq_offers_buyer_update on public.rfq_offers;
create policy rfq_offers_supplier_buyer_read on public.rfq_offers for select to authenticated
using (public.has_business_role(supplier_business_id,array['owner'::public.member_role,'manager'::public.member_role,'staff'::public.member_role]) or private.is_rfq_buyer(rfq_id));
create policy rfq_offers_supplier_insert on public.rfq_offers for insert to authenticated
with check (status='submitted' and total_price is not null and total_price>0 and unit_price>0 and (delivery_days is null or delivery_days>0) and private.can_submit_rfq_offer(rfq_id,supplier_business_id,quantity));

alter table public.rfq_offers drop constraint if exists rfq_offers_one_per_supplier;
revoke all on function private.submit_rfq_offer(uuid,uuid,numeric,integer,text) from public,anon,authenticated;
revoke all on function private.accept_rfq_offer(uuid) from public,anon,authenticated;

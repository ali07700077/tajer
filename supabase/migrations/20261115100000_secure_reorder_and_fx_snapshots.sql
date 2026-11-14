-- Secure reorder reservations and immutable FX quote snapshots.
-- IQD remains the accounting currency; USD is a rate-stamped presentation/settlement amount.
create table if not exists public.fx_rate_snapshots (
  id uuid primary key default extensions.gen_random_uuid(),
  base_currency text not null default 'USD' check (base_currency='USD'),
  quote_currency text not null default 'IQD' check (quote_currency='IQD'),
  rate_iqd_per_usd numeric(19,6) not null check (rate_iqd_per_usd>0),
  source text not null check (char_length(trim(source)) between 2 and 120),
  effective_at timestamptz not null,
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  created_by uuid,
  check (expires_at>effective_at),
  unique(base_currency,quote_currency,effective_at)
);
create index if not exists fx_rate_snapshots_current_idx
  on public.fx_rate_snapshots(base_currency,quote_currency,effective_at desc);
alter table public.fx_rate_snapshots enable row level security;
revoke all on public.fx_rate_snapshots from anon,authenticated;
grant select on public.fx_rate_snapshots to authenticated;
create policy fx_rate_snapshots_read_current on public.fx_rate_snapshots
for select to authenticated using (effective_at<=now() and expires_at>now());

create or replace function public.reject_fx_rate_mutation()
returns trigger language plpgsql set search_path='' as $$
begin
 raise exception 'سجل أسعار الصرف غير قابل للتعديل أو الحذف' using errcode='55000';
end; $$;
drop trigger if exists fx_rate_snapshots_immutable on public.fx_rate_snapshots;
create trigger fx_rate_snapshots_immutable before update or delete on public.fx_rate_snapshots
for each row execute function public.reject_fx_rate_mutation();
revoke all on function public.reject_fx_rate_mutation() from public,anon,authenticated;

alter table public.orders
 add column if not exists fx_rate_snapshot_id uuid references public.fx_rate_snapshots(id) on delete restrict,
 add column if not exists fx_rate_iqd_per_usd numeric(19,6),
 add column if not exists total_amount_usd numeric(19,4);
alter table public.orders
 add constraint orders_fx_snapshot_consistency check (
   (fx_rate_snapshot_id is null and fx_rate_iqd_per_usd is null and total_amount_usd is null)
   or (fx_rate_snapshot_id is not null and fx_rate_iqd_per_usd>0 and total_amount_usd>=0)
 ) not valid;

create or replace function public.apply_order_fx_snapshot(p_order_id uuid)
returns public.orders
language plpgsql security definer set search_path='' as $$
declare v_order public.orders%rowtype; v_rate public.fx_rate_snapshots%rowtype;
begin
 if auth.uid() is null then raise exception 'يجب تسجيل الدخول' using errcode='28000'; end if;
 select * into v_order from public.orders where id=p_order_id for update;
 if not found then raise exception 'الطلب غير موجود' using errcode='P0002'; end if;
 if not (
   v_order.buyer_user_id=auth.uid()
   or public.has_business_role(v_order.buyer_business_id,array['owner'::public.member_role,'manager'::public.member_role])
   or public.has_business_role(v_order.supplier_business_id,array['owner'::public.member_role,'manager'::public.member_role])
 ) then raise exception 'غير مخول لعرض تحويل قيمة الطلب' using errcode='42501'; end if;
 if v_order.fx_rate_snapshot_id is not null then return v_order; end if;
 select * into v_rate from public.fx_rate_snapshots
 where base_currency='USD' and quote_currency='IQD'
   and effective_at<=now() and expires_at>now()
 order by effective_at desc limit 1;
 if not found then raise exception 'لا يوجد سعر صرف USD/IQD ساري حالياً' using errcode='55000'; end if;
 update public.orders set fx_rate_snapshot_id=v_rate.id,
   fx_rate_iqd_per_usd=v_rate.rate_iqd_per_usd,
   total_amount_usd=round(total_amount / v_rate.rate_iqd_per_usd,4),
   updated_at=now()
 where id=p_order_id returning * into v_order;
 return v_order;
end; $$;
revoke all on function public.apply_order_fx_snapshot(uuid) from public,anon;
grant execute on function public.apply_order_fx_snapshot(uuid) to authenticated;

create or replace function public.reorder_order(p_source_order_id uuid)
returns jsonb
language plpgsql security definer set search_path='' as $$
declare
 v_source public.orders%rowtype;
 v_new_order_id uuid:=extensions.gen_random_uuid();
 v_item record;
 v_product public.products%rowtype;
 v_qty integer;
 v_price numeric(19,4);
 v_total numeric(19,4):=0;
 v_currency text;
begin
 if auth.uid() is null then raise exception 'يجب تسجيل الدخول' using errcode='28000'; end if;
 select * into v_source from public.orders where id=p_source_order_id for update;
 if not found then raise exception 'الطلب الأصلي غير موجود' using errcode='P0002'; end if;
 if v_source.order_type='b2b' then
   if not public.has_business_role(v_source.buyer_business_id,array['owner'::public.member_role,'manager'::public.member_role]) then
     raise exception 'إعادة طلب الجملة تتطلب صلاحية مدير أو مالك الشركة' using errcode='42501';
   end if;
 else
   if v_source.buyer_user_id is distinct from auth.uid() then
     raise exception 'لا يمكنك إعادة طلب يخص مستخدماً آخر' using errcode='42501';
   end if;
 end if;
 if v_source.status='cancelled' and v_source.created_at<now()-interval '365 days' then
   raise exception 'الطلب أقدم من المدة المسموحة لإعادة الطلب' using errcode='22023';
 end if;
 v_currency:=coalesce(v_source.currency,'IQD');
 insert into public.orders(id,buyer_business_id,buyer_user_id,supplier_business_id,order_type,status,total_amount,currency,delivery_address,notes)
 values(v_new_order_id,v_source.buyer_business_id,case when v_source.order_type='b2c' then auth.uid() else null end,
   v_source.supplier_business_id,v_source.order_type,'pending',0,'IQD',v_source.delivery_address,
   'إعادة طلب من '||v_source.id::text);
 for v_item in select product_id,product_name,quantity from public.order_items where order_id=p_source_order_id order by product_id
 loop
   if v_item.quantity<>trunc(v_item.quantity) or v_item.quantity<=0 or v_item.quantity>2147483647 then
     raise exception 'كمية بند الطلب الأصلي غير صالحة' using errcode='22023';
   end if;
   v_qty:=v_item.quantity::integer;
   select * into v_product from public.products where id=v_item.product_id for update;
   if not found or not v_product.is_active then raise exception 'أحد المنتجات لم يعد متاحاً' using errcode='23514'; end if;
   if v_source.order_type='b2c' then
     if not v_product.is_retail_available or v_product.retail_price is null then raise exception 'المنتج لم يعد متاحاً للمفرد' using errcode='23514'; end if;
     v_price:=v_product.retail_price;
   else
     if v_qty<v_product.min_order_quantity then raise exception 'الكمية أقل من الحد الأدنى الحالي للطلب' using errcode='23514'; end if;
     v_price:=coalesce((select t.unit_price from public.product_price_tiers t where t.product_id=v_product.id and t.min_quantity<=v_qty order by t.min_quantity desc limit 1),v_product.price);
   end if;
   if v_qty>v_product.available_quantity then raise exception 'المخزون المتاح لا يكفي لإعادة الطلب' using errcode='23514'; end if;
   insert into public.order_items(order_id,product_id,product_name,quantity,unit_price)
   values(v_new_order_id,v_product.id,v_product.name,v_qty,v_price);
   update public.products set reserved_quantity=reserved_quantity+v_qty,updated_at=now() where id=v_product.id;
   insert into public.inventory_reservations(order_id,product_id,supplier_business_id,quantity,status,expires_at)
   values(v_new_order_id,v_product.id,v_product.business_id,v_qty,'held',now()+interval '15 minutes');
   v_total:=v_total+(v_price*v_qty);
 end loop;
 if not exists(select 1 from public.order_items where order_id=v_new_order_id) then
   raise exception 'الطلب الأصلي لا يحتوي بنوداً قابلة لإعادة الطلب' using errcode='22023';
 end if;
 update public.orders set total_amount=v_total,updated_at=now() where id=v_new_order_id;
 insert into public.order_workflow_events(order_id,actor_id,action,reason,metadata)
 values(v_new_order_id,auth.uid(),'approved','reorder_created',jsonb_build_object('source_order_id',p_source_order_id,'reservation_minutes',15));
 return jsonb_build_object('order_id',v_new_order_id,'status','pending','total_amount_iqd',v_total,'reservation_expires_at',now()+interval '15 minutes');
end; $$;
revoke all on function public.reorder_order(uuid) from public,anon;
grant execute on function public.reorder_order(uuid) to authenticated;

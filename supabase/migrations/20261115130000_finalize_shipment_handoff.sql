-- Finalize the shipment only after its linked order(s) have been confirmed delivered.
create or replace function public.verify_shipment_handoff_code(p_shipment_id uuid,p_order_id uuid,p_code text)
returns boolean language plpgsql security definer set search_path='' as $$
declare v_shipment public.consolidated_shipments%rowtype; v_ok boolean;
begin
 if auth.uid() is null then raise exception 'يجب تسجيل الدخول' using errcode='28000'; end if;
 select * into v_shipment from public.consolidated_shipments where id=p_shipment_id for update;
 if not found then raise exception 'الشحنة غير موجودة' using errcode='P0002'; end if;
 if not exists(select 1 from public.consolidated_shipment_orders where shipment_id=p_shipment_id and order_id=p_order_id) then
  raise exception 'الطلب غير مرتبط بهذه الشحنة' using errcode='22023';
 end if;
 v_ok:=public.verify_order_handoff_code(p_order_id,p_code);
 if not v_ok then return false; end if;
 if not exists(select 1 from public.consolidated_shipment_orders so join public.orders o on o.id=so.order_id
   where so.shipment_id=p_shipment_id and o.status<>'delivered') then
  update public.consolidated_shipments set status='delivered',delivered_at=now(),updated_at=now() where id=p_shipment_id;
  if v_shipment.last_latitude is not null and v_shipment.last_longitude is not null then
   insert into public.shipment_tracking_events(shipment_id,actor_id,latitude,longitude,event_type,metadata)
   values(p_shipment_id,auth.uid(),v_shipment.last_latitude,v_shipment.last_longitude,
    'handoff_verified',jsonb_build_object('verified_order_id',p_order_id));
  end if;
 end if;
 return true;
end; $$;
revoke all on function public.verify_shipment_handoff_code(uuid,uuid,text) from public,anon;
grant execute on function public.verify_shipment_handoff_code(uuid,uuid,text) to authenticated;

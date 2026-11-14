-- Live shipment tracking: privacy-scoped location events and realtime publication.
alter table public.consolidated_shipments
 add column if not exists assigned_driver_id uuid references auth.users(id) on delete restrict,
 add column if not exists last_latitude numeric(9,6),
 add column if not exists last_longitude numeric(9,6),
 add column if not exists last_location_at timestamptz,
 add column if not exists eta_source text,
 add constraint consolidated_shipments_latitude_check check(last_latitude is null or last_latitude between -90 and 90),
 add constraint consolidated_shipments_longitude_check check(last_longitude is null or last_longitude between -180 and 180);

create table if not exists public.shipment_tracking_events(
 id uuid primary key default extensions.gen_random_uuid(),
 shipment_id uuid not null references public.consolidated_shipments(id) on delete restrict,
 actor_id uuid not null references auth.users(id) on delete restrict,
 latitude numeric(9,6) not null check(latitude between -90 and 90),
 longitude numeric(9,6) not null check(longitude between -180 and 180),
 accuracy_m numeric(8,2) check(accuracy_m is null or accuracy_m between 0 and 10000),
 speed_mps numeric(8,2) check(speed_mps is null or speed_mps between 0 and 150),
 heading_deg numeric(6,2) check(heading_deg is null or heading_deg between 0 and 360),
 eta_minutes integer check(eta_minutes is null or eta_minutes between 0 and 10080),
 eta_at timestamptz,
 event_type text not null default 'location' check(event_type in ('location','status','handoff_verified')),
 metadata jsonb not null default '{}'::jsonb,
 recorded_at timestamptz not null default now()
);
create index if not exists shipment_tracking_events_shipment_time_idx
 on public.shipment_tracking_events(shipment_id,recorded_at desc);
alter table public.shipment_tracking_events enable row level security;
revoke all on public.shipment_tracking_events from anon,authenticated;
grant select on public.shipment_tracking_events to authenticated;

create or replace function public.can_view_shipment(p_shipment_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(
  select 1 from public.consolidated_shipments s
  where s.id=p_shipment_id and (
   s.created_by=auth.uid() or s.assigned_driver_id=auth.uid()
   or public.has_business_role(s.buyer_business_id,array['owner'::public.member_role,'manager'::public.member_role])
   or exists(select 1 from public.consolidated_shipment_orders so
     where so.shipment_id=s.id and public.has_business_role(so.supplier_business_id,array['owner'::public.member_role,'manager'::public.member_role]))
  )
 );
$$;
revoke all on function public.can_view_shipment(uuid) from public,anon;
grant execute on function public.can_view_shipment(uuid) to authenticated;
create policy shipment_tracking_participant_read on public.shipment_tracking_events
for select to authenticated using(public.can_view_shipment(shipment_id));

create or replace function public.record_shipment_location(
 p_shipment_id uuid,p_latitude numeric,p_longitude numeric,
 p_accuracy_m numeric default null,p_speed_mps numeric default null,
 p_heading_deg numeric default null,p_eta_minutes integer default null
) returns public.shipment_tracking_events
language plpgsql security definer set search_path='' as $$
declare v_shipment public.consolidated_shipments%rowtype; v_event public.shipment_tracking_events%rowtype;
begin
 if auth.uid() is null then raise exception 'يجب تسجيل الدخول' using errcode='28000'; end if;
 if p_latitude is null or p_latitude not between -90 and 90 or p_longitude is null or p_longitude not between -180 and 180 then
  raise exception 'إحداثيات GPS غير صالحة' using errcode='22023';
 end if;
 if p_eta_minutes is not null and p_eta_minutes not between 0 and 10080 then raise exception 'قيمة ETA غير صالحة' using errcode='22023'; end if;
 select * into v_shipment from public.consolidated_shipments where id=p_shipment_id for update;
 if not found then raise exception 'الشحنة غير موجودة' using errcode='P0002'; end if;
 if not (
  v_shipment.assigned_driver_id=auth.uid() or v_shipment.created_by=auth.uid()
  or public.has_business_role(v_shipment.buyer_business_id,array['owner'::public.member_role,'manager'::public.member_role])
  or exists(select 1 from public.consolidated_shipment_orders so
   where so.shipment_id=v_shipment.id and public.has_business_role(so.supplier_business_id,array['owner'::public.member_role,'manager'::public.member_role]))
 ) then raise exception 'غير مخول لتحديث موقع الشحنة' using errcode='42501'; end if;
 if v_shipment.status not in ('dispatched','in_transit') then raise exception 'تتبع GPS متاح للشحنات المنطلقة فقط' using errcode='55000'; end if;
 insert into public.shipment_tracking_events(shipment_id,actor_id,latitude,longitude,accuracy_m,speed_mps,heading_deg,eta_minutes,eta_at)
 values(p_shipment_id,auth.uid(),p_latitude,p_longitude,p_accuracy_m,p_speed_mps,p_heading_deg,p_eta_minutes,
  case when p_eta_minutes is null then null else now()+make_interval(mins=>p_eta_minutes) end)
 returning * into v_event;
 update public.consolidated_shipments set last_latitude=p_latitude,last_longitude=p_longitude,
  last_location_at=now(),estimated_delivery_at=coalesce(v_event.eta_at,estimated_delivery_at),
  eta_source=case when p_eta_minutes is null then eta_source else 'driver_reported_minutes' end,
  status='in_transit',updated_at=now()
 where id=p_shipment_id;
 return v_event;
end; $$;
revoke all on function public.record_shipment_location(uuid,numeric,numeric,numeric,numeric,numeric,integer) from public,anon;
grant execute on function public.record_shipment_location(uuid,numeric,numeric,numeric,numeric,numeric,integer) to authenticated;

do $$
begin
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='shipment_tracking_events') then
  alter publication supabase_realtime add table public.shipment_tracking_events;
 end if;
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='consolidated_shipments') then
  alter publication supabase_realtime add table public.consolidated_shipments;
 end if;
end $$;

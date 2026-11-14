-- TAJER order workflow controls: audited transitions, safe line adjustments and one-time handoff codes.
create table if not exists public.order_workflow_events (
  id uuid primary key default extensions.gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete restrict,
  actor_id uuid not null references auth.users(id) on delete restrict,
  action text not null check(action in ('approved','rejected','processing','shipped','delivered','quantity_changed','handoff_code_issued')),
  reason text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists order_workflow_events_order_created_idx
  on public.order_workflow_events(order_id,created_at desc);
alter table public.order_workflow_events enable row level security;
revoke all on public.order_workflow_events from anon,authenticated;
grant select on public.order_workflow_events to authenticated;
create policy order_workflow_events_participant_read on public.order_workflow_events
for select to authenticated using (
 exists(select 1 from public.orders o where o.id=order_id and (
  o.buyer_user_id=auth.uid()
  or public.has_business_role(o.buyer_business_id,array['owner'::public.member_role,'manager'::public.member_role])
  or public.has_business_role(o.supplier_business_id,array['owner'::public.member_role,'manager'::public.member_role])
 ))
);

create or replace function public.transition_order_status(
 p_order_id uuid,p_next_status text,p_reason text default null
) returns public.orders
language plpgsql security definer set search_path='' as $$
declare v_order public.orders%rowtype; v_action text; v_previous_status text;
begin
 if auth.uid() is null then raise exception 'يجب تسجيل الدخول' using errcode='28000'; end if;
 select * into v_order from public.orders where id=p_order_id for update;
 if not found then raise exception 'الطلب غير موجود' using errcode='P0002'; end if;
 if not public.has_business_role(v_order.supplier_business_id,array['owner'::public.member_role,'manager'::public.member_role]) then
   raise exception 'لا تملك صلاحية إدارة طلب المورد' using errcode='42501';
 end if;
 v_previous_status:=v_order.status;
 if p_next_status not in ('confirmed','cancelled','processing','shipped','delivered') then
   raise exception 'حالة الطلب المطلوبة غير مسموحة' using errcode='22023';
 end if;
 if p_next_status='confirmed' and v_order.status<>'pending' then raise exception 'لا يمكن اعتماد هذا الطلب من حالته الحالية' using errcode='55000'; end if;
 if p_next_status='cancelled' and v_order.status not in ('pending','confirmed') then raise exception 'لا يمكن رفض الطلب بعد بدء التجهيز' using errcode='55000'; end if;
 if p_next_status='processing' and v_order.status<>'confirmed' then raise exception 'يجب اعتماد الطلب قبل التجهيز' using errcode='55000'; end if;
 if p_next_status='shipped' and v_order.status<>'processing' then raise exception 'يجب تجهيز الطلب قبل الشحن' using errcode='55000'; end if;
 if p_next_status='delivered' and v_order.status<>'shipped' then raise exception 'يجب شحن الطلب قبل التسليم' using errcode='55000'; end if;
 if p_next_status='cancelled' and char_length(trim(coalesce(p_reason,'')))<4 then raise exception 'سبب الرفض مطلوب (4 أحرف على الأقل)' using errcode='22023'; end if;
 update public.orders set status=p_next_status,notes=case when p_next_status='cancelled' then concat_ws(E'\n',notes,'سبب الرفض: '||trim(p_reason)) else notes end,updated_at=now()
 where id=p_order_id returning * into v_order;
 v_action:=case p_next_status when 'confirmed' then 'approved' when 'cancelled' then 'rejected' else p_next_status end;
 insert into public.order_workflow_events(order_id,actor_id,action,reason,metadata)
 values(p_order_id,auth.uid(),v_action,nullif(trim(coalesce(p_reason,'')),''),jsonb_build_object('from',v_previous_status,'to',p_next_status));
 return v_order;
end;
$$;
revoke all on function public.transition_order_status(uuid,text,text) from public,anon;
grant execute on function public.transition_order_status(uuid,text,text) to authenticated;

create or replace function public.update_order_item_quantity(
 p_order_item_id uuid,p_quantity numeric,p_reason text
) returns public.order_items
language plpgsql security definer set search_path='' as $$
declare v_item public.order_items%rowtype; v_order public.orders%rowtype;
begin
 if auth.uid() is null then raise exception 'يجب تسجيل الدخول' using errcode='28000'; end if;
 if p_quantity is null or p_quantity<=0 or p_quantity>1000000000 then raise exception 'الكمية غير صالحة' using errcode='22023'; end if;
 if char_length(trim(coalesce(p_reason,'')))<4 then raise exception 'سبب تعديل الكمية مطلوب' using errcode='22023'; end if;
 select * into v_item from public.order_items where id=p_order_item_id for update;
 if not found then raise exception 'بند الطلب غير موجود' using errcode='P0002'; end if;
 select * into v_order from public.orders where id=v_item.order_id for update;
 if v_order.status<>'pending' then raise exception 'تعديل الكمية متاح قبل اعتماد الطلب فقط' using errcode='55000'; end if;
 if not (
  public.has_business_role(v_order.buyer_business_id,array['owner'::public.member_role,'manager'::public.member_role])
  or public.has_business_role(v_order.supplier_business_id,array['owner'::public.member_role,'manager'::public.member_role])
 ) then raise exception 'لا تملك صلاحية تعديل هذا الطلب' using errcode='42501'; end if;
 if exists(select 1 from public.inventory_reservations r where r.order_id=v_order.id and r.status='held') then
  raise exception 'لا يمكن تعديل الكمية أثناء وجود حجز مخزون؛ حرر الحجز أولاً' using errcode='55000';
 end if;
 update public.order_items set quantity=p_quantity where id=p_order_item_id returning * into v_item;
 update public.orders set total_amount=(select coalesce(sum(line_total),0) from public.order_items where order_id=v_order.id),updated_at=now() where id=v_order.id;
 insert into public.order_workflow_events(order_id,actor_id,action,reason,metadata)
 values(v_order.id,auth.uid(),'quantity_changed',trim(p_reason),jsonb_build_object('order_item_id',v_item.id,'quantity',p_quantity));
 return v_item;
end;
$$;
revoke all on function public.update_order_item_quantity(uuid,numeric,text) from public,anon;
grant execute on function public.update_order_item_quantity(uuid,numeric,text) to authenticated;

create table if not exists public.order_handoff_codes (
 order_id uuid primary key references public.orders(id) on delete restrict,
 code_hash bytea not null,
 expires_at timestamptz not null,
 consumed_at timestamptz,
 issued_by uuid not null references auth.users(id) on delete restrict,
 created_at timestamptz not null default now()
);
alter table public.order_handoff_codes enable row level security;
revoke all on public.order_handoff_codes from anon,authenticated;

create or replace function public.issue_order_handoff_code(p_order_id uuid)
returns text language plpgsql security definer set search_path='' as $$
declare v_order public.orders%rowtype; v_code text;
begin
 if auth.uid() is null then raise exception 'يجب تسجيل الدخول' using errcode='28000'; end if;
 select * into v_order from public.orders where id=p_order_id for update;
 if not found then raise exception 'الطلب غير موجود' using errcode='P0002'; end if;
 if not public.has_business_role(v_order.supplier_business_id,array['owner'::public.member_role,'manager'::public.member_role]) then
  raise exception 'إصدار رمز التسليم يتطلب صلاحية المورد' using errcode='42501';
 end if;
 if v_order.status not in ('shipped','processing') then raise exception 'رمز التسليم متاح للطلبات قيد التجهيز أو الشحن' using errcode='55000'; end if;
 v_code:=upper(substr(encode(extensions.gen_random_bytes(8),'hex'),1,10));
 insert into public.order_handoff_codes(order_id,code_hash,expires_at,issued_by)
 values(p_order_id,extensions.digest(convert_to(v_code,'UTF8'),'sha256'),now()+interval '30 minutes',auth.uid())
 on conflict(order_id) do update set code_hash=excluded.code_hash,expires_at=excluded.expires_at,consumed_at=null,issued_by=excluded.issued_by,created_at=now();
 insert into public.order_workflow_events(order_id,actor_id,action,metadata)
 values(p_order_id,auth.uid(),'handoff_code_issued',jsonb_build_object('expires_at',now()+interval '30 minutes'));
 return v_code;
end;
$$;
revoke all on function public.issue_order_handoff_code(uuid) from public,anon;
grant execute on function public.issue_order_handoff_code(uuid) to authenticated;

create or replace function public.verify_order_handoff_code(p_order_id uuid,p_code text)
returns boolean language plpgsql security definer set search_path='' as $$
declare v_code public.order_handoff_codes%rowtype; v_order public.orders%rowtype;
begin
 if auth.uid() is null then raise exception 'يجب تسجيل الدخول' using errcode='28000'; end if;
 select * into v_order from public.orders where id=p_order_id for update;
 if not found then return false; end if;
 if not (
  public.has_business_role(v_order.buyer_business_id,array['owner'::public.member_role,'manager'::public.member_role])
  or public.has_business_role(v_order.supplier_business_id,array['owner'::public.member_role,'manager'::public.member_role])
 ) then raise exception 'غير مخول للتحقق من رمز التسليم' using errcode='42501'; end if;
 select * into v_code from public.order_handoff_codes where order_id=p_order_id for update;
 if not found or v_code.consumed_at is not null or v_code.expires_at<=now() then return false; end if;
 if v_code.code_hash<>extensions.digest(convert_to(upper(trim(coalesce(p_code,''))),'UTF8'),'sha256') then return false; end if;
 update public.order_handoff_codes set consumed_at=now() where order_id=p_order_id;
 update public.orders set status='delivered',updated_at=now() where id=p_order_id and status in ('shipped','processing');
 insert into public.order_workflow_events(order_id,actor_id,action,metadata)
 values(p_order_id,auth.uid(),'delivered',jsonb_build_object('verification','one_time_code'));
 return true;
end;
$$;
revoke all on function public.verify_order_handoff_code(uuid,text) from public,anon;
grant execute on function public.verify_order_handoff_code(uuid,text) to authenticated;

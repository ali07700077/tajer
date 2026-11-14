-- One checkout session groups the supplier-specific orders produced by the existing
-- B2C and B2B checkout RPCs. The wrapper is atomic: either every child order and
-- inventory reservation is created, or the entire mixed checkout rolls back.

create table public.checkout_sessions (
  id uuid primary key default extensions.gen_random_uuid(),
  buyer_user_id uuid not null references public.profiles(id) on delete restrict,
  buyer_business_id uuid references public.businesses(id) on delete restrict,
  delivery_address text not null check (char_length(trim(delivery_address)) >= 8),
  status text not null default 'pending_payment'
    check (status in ('pending_payment','partially_paid','paid','expired','cancelled')),
  total_amount numeric(14,2) not null default 0 check (total_amount >= 0),
  currency text not null default 'IQD' check (currency = 'IQD'),
  expires_at timestamptz not null default (now() + interval '15 minutes'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.orders
  add column checkout_session_id uuid references public.checkout_sessions(id) on delete restrict;

create index checkout_sessions_buyer_created_idx
  on public.checkout_sessions (buyer_user_id, created_at desc);
create index checkout_sessions_expiry_idx
  on public.checkout_sessions (expires_at) where status = 'pending_payment';
create index orders_checkout_session_idx
  on public.orders (checkout_session_id) where checkout_session_id is not null;

alter table public.checkout_sessions enable row level security;
revoke all on public.checkout_sessions from anon, authenticated;
grant select on public.checkout_sessions to authenticated;

create policy checkout_sessions_participant_read
on public.checkout_sessions for select to authenticated
using (
  buyer_user_id = (select auth.uid())
  or (
    buyer_business_id is not null
    and public.has_business_role(
      buyer_business_id,
      array['owner'::public.member_role,'manager'::public.member_role]
    )
  )
  or exists (
    select 1 from public.orders child
    where child.checkout_session_id = checkout_sessions.id
      and public.has_business_role(
        child.supplier_business_id,
        array['owner'::public.member_role,'manager'::public.member_role]
      )
  )
);

create or replace function public.sync_checkout_session_status()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_session_id uuid;
  v_held integer;
  v_committed integer;
  v_released integer;
  v_next_status text;
begin
  select o.checkout_session_id into v_session_id
  from public.orders o where o.id = new.order_id;

  if v_session_id is null then
    return new;
  end if;

  select
    count(*) filter (where r.status = 'held'),
    count(*) filter (where r.status = 'committed'),
    count(*) filter (where r.status = 'released')
  into v_held, v_committed, v_released
  from public.inventory_reservations r
  join public.orders o on o.id = r.order_id
  where o.checkout_session_id = v_session_id;

  v_next_status := case
    when v_held > 0 then 'pending_payment'
    when v_committed > 0 and v_released > 0 then 'partially_paid'
    when v_committed > 0 then 'paid'
    else 'expired'
  end;

  update public.checkout_sessions
  set status = v_next_status, updated_at = now()
  where id = v_session_id and status <> 'cancelled';

  return new;
end;
$function$;

drop trigger if exists inventory_reservations_sync_checkout_session
  on public.inventory_reservations;
create trigger inventory_reservations_sync_checkout_session
after update of status on public.inventory_reservations
for each row
when (old.status is distinct from new.status)
execute function public.sync_checkout_session_status();

create or replace function public.create_hybrid_checkout(
  p_buyer_business_id uuid,
  p_retail_items jsonb,
  p_wholesale_items jsonb,
  p_delivery_address text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_session_id uuid;
  v_retail_result jsonb := '[]'::jsonb;
  v_wholesale_result jsonb := '[]'::jsonb;
  v_child jsonb;
  v_total numeric(14,2) := 0;
  v_expiry timestamptz := now() + interval '15 minutes';
begin
  if v_user_id is null then
    raise exception 'يجب تسجيل الدخول لإتمام عملية الشراء' using errcode = '28000';
  end if;
  if char_length(trim(coalesce(p_delivery_address,''))) < 8 then
    raise exception 'يرجى إدخال عنوان توصيل واضح' using errcode = '22023';
  end if;
  if jsonb_typeof(p_retail_items) <> 'array'
     or jsonb_typeof(p_wholesale_items) <> 'array'
     or (jsonb_array_length(p_retail_items) = 0 and jsonb_array_length(p_wholesale_items) = 0)
     or jsonb_array_length(p_retail_items) > 50
     or jsonb_array_length(p_wholesale_items) > 50 then
    raise exception 'سلة الشراء الهجينة غير صالحة' using errcode = '22023';
  end if;
  if jsonb_array_length(p_wholesale_items) > 0 and p_buyer_business_id is null then
    raise exception 'اختر ملف شركة مشتري لطلب الجملة' using errcode = '22023';
  end if;
  if p_buyer_business_id is not null and not public.has_business_role(
    p_buyer_business_id,
    array['owner'::public.member_role,'manager'::public.member_role]
  ) then
    raise exception 'ليس لديك صلاحية استخدام ملف شركة المشتري' using errcode = '42501';
  end if;
  if exists (
    select 1
    from jsonb_array_elements(p_retail_items) retail_item
    join jsonb_array_elements(p_wholesale_items) wholesale_item
      on retail_item.value->>'product_id' = wholesale_item.value->>'product_id'
  ) then
    raise exception 'لا يمكن إضافة المنتج نفسه إلى مساري المفرد والجملة في عملية شراء واحدة' using errcode = '22023';
  end if;

  insert into public.checkout_sessions (
    buyer_user_id, buyer_business_id, delivery_address, expires_at
  ) values (
    v_user_id, p_buyer_business_id, trim(p_delivery_address), v_expiry
  ) returning id into v_session_id;

  if jsonb_array_length(p_retail_items) > 0 then
    v_retail_result := public.create_retail_orders(p_retail_items, p_delivery_address);
    for v_child in select value from jsonb_array_elements(v_retail_result)
    loop
      update public.orders
      set checkout_session_id = v_session_id
      where id = (v_child->>'order_id')::uuid
        and buyer_user_id = v_user_id
        and order_type = 'b2c';
      if not found then
        raise exception 'تعذر ربط طلب المفرد بعملية الشراء الرئيسية' using errcode = '23514';
      end if;
      v_total := v_total + (v_child->>'total_amount')::numeric;
    end loop;
  end if;

  if jsonb_array_length(p_wholesale_items) > 0 then
    v_wholesale_result := public.create_wholesale_orders(
      p_buyer_business_id, p_wholesale_items, p_delivery_address
    );
    for v_child in select value from jsonb_array_elements(v_wholesale_result)
    loop
      update public.orders
      set checkout_session_id = v_session_id
      where id = (v_child->>'order_id')::uuid
        and buyer_business_id = p_buyer_business_id
        and order_type = 'b2b';
      if not found then
        raise exception 'تعذر ربط طلب الجملة بعملية الشراء الرئيسية' using errcode = '23514';
      end if;
      v_total := v_total + (v_child->>'total_amount')::numeric;
    end loop;
  end if;

  update public.checkout_sessions
  set total_amount = v_total, updated_at = now()
  where id = v_session_id;

  return jsonb_build_object(
    'checkout_session_id', v_session_id,
    'status', 'pending_payment',
    'total_amount', v_total,
    'currency', 'IQD',
    'expires_at', v_expiry,
    'retail_orders', v_retail_result,
    'wholesale_orders', v_wholesale_result
  );
end;
$function$;

revoke all on function public.create_hybrid_checkout(uuid,jsonb,jsonb,text) from public, anon;
grant execute on function public.create_hybrid_checkout(uuid,jsonb,jsonb,text) to authenticated;
revoke all on function public.sync_checkout_session_status() from public, anon, authenticated;

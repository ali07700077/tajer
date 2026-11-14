-- TAJER Phase 1: account bootstrap, company ownership and RLS hardening.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_business_type public.business_type;
  v_business_name text;
  v_governorate_id uuid;
  v_business_id uuid;
begin
  insert into public.profiles (id, full_name, phone)
  values (
    new.id,
    nullif(left(new.raw_user_meta_data ->> 'full_name', 120), ''),
    nullif(left(new.raw_user_meta_data ->> 'phone', 30), '')
  );

  v_business_name := nullif(left(trim(coalesce(new.raw_user_meta_data ->> 'business_name', '')), 160), '');
  if v_business_name is not null then
    begin
      v_business_type := (new.raw_user_meta_data ->> 'business_type')::public.business_type;
      v_governorate_id := (new.raw_user_meta_data ->> 'governorate_id')::uuid;
    exception when others then
      raise exception 'Invalid business registration details' using errcode = '22023';
    end;

    if v_business_type not in ('buyer'::public.business_type, 'supplier'::public.business_type)
       or v_governorate_id is null
       or not exists (select 1 from public.governorates where id = v_governorate_id and is_active) then
      raise exception 'Business type or governorate is invalid' using errcode = '22023';
    end if;

    insert into public.businesses (business_type, name_ar, governorate_id, phone, created_by)
    values (
      v_business_type, v_business_name, v_governorate_id,
      nullif(left(new.raw_user_meta_data ->> 'phone', 30), ''), new.id
    ) returning id into v_business_id;

    insert into public.business_members (business_id, user_id, member_role)
    values (v_business_id, new.id, 'owner'::public.member_role);
  end if;
  return new;
end;
$function$;

revoke update on table public.profiles from authenticated;
grant update (full_name, phone) on table public.profiles to authenticated;

revoke update on table public.businesses from authenticated;
grant update (name_ar, name_en, description_ar, phone, email, address_text, logo_path, city_id)
on table public.businesses to authenticated;

drop policy if exists businesses_select_member on public.businesses;
create policy businesses_select_member on public.businesses
for select to authenticated using (public.is_business_member(id));

drop policy if exists business_members_select on public.business_members;
create policy business_members_select on public.business_members
for select to authenticated
using (
  user_id = (select auth.uid())
  or public.is_business_member(business_id)
  or public.has_permission('businesses.read')
);

drop policy if exists products_select_authenticated on public.products;
drop policy if exists products_public_active on public.products;
drop policy if exists products_select_public_active on public.products;
create policy products_select_public_active on public.products
for select to anon, authenticated
using (
  is_active and exists (
    select 1 from public.businesses b
    where b.id = products.business_id and b.is_active
      and b.verification_status = 'approved'::public.verification_status
  )
);

revoke execute on function public.create_business(public.business_type, text, uuid, uuid, text) from authenticated;

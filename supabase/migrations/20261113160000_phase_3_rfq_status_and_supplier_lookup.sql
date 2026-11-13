alter table public.rfqs drop constraint if exists rfqs_status_check;
alter table public.rfqs add constraint rfqs_status_check
check (status = any(array['open','responded','closed','awarded','cancelled']));

drop view if exists public.public_supplier_directory;
create or replace function public.get_public_supplier_names(p_business_ids uuid[] default null)
returns table(id uuid,name_ar text)
language sql stable security definer set search_path=''
as $$
 select b.id,b.name_ar from public.businesses b
 where b.business_type='supplier' and b.is_active and b.verification_status='approved'
 and (p_business_ids is null or b.id=any(p_business_ids));
$$;
revoke all on function public.get_public_supplier_names(uuid[]) from public;
grant execute on function public.get_public_supplier_names(uuid[]) to anon,authenticated;

-- Harden exposed SECURITY DEFINER routines with least-privilege EXECUTE grants.
-- Every SECURITY DEFINER routine uses an empty search_path; all object references
-- in these functions are schema-qualified.

alter function public.rls_auto_enable() set search_path = '';

revoke execute on function public.audit_row_change() from public, anon, authenticated;
revoke execute on function public.handle_new_user() from public, anon, authenticated;
revoke execute on function public.write_audit_log(text, text, uuid, text, jsonb) from public, anon, authenticated;
revoke execute on function public.get_public_supplier_names(uuid[]) from public, anon;
grant execute on function public.get_public_supplier_names(uuid[]) to authenticated;

-- These RPCs are intentionally callable by signed-in users; their bodies perform
-- explicit auth.uid(), membership, role, supplier-verification and state checks.
revoke execute on function public.accept_rfq_offer(uuid) from public, anon;
grant execute on function public.accept_rfq_offer(uuid) to authenticated;
revoke execute on function public.submit_rfq_offer(uuid, uuid, numeric, integer, text) from public, anon;
grant execute on function public.submit_rfq_offer(uuid, uuid, numeric, integer, text) to authenticated;

-- Policy helper functions are used by authenticated RLS policies. Keep them
-- unavailable to anonymous callers and retain authenticated execution.
revoke execute on function public.has_business_role(uuid, public.member_role[]) from public, anon;
grant execute on function public.has_business_role(uuid, public.member_role[]) to authenticated;
revoke execute on function public.has_permission(text) from public, anon;
grant execute on function public.has_permission(text) to authenticated;
revoke execute on function public.is_business_member(uuid) from public, anon;
grant execute on function public.is_business_member(uuid) to authenticated;
revoke execute on function public.my_permissions() from public, anon;
grant execute on function public.my_permissions() to authenticated;

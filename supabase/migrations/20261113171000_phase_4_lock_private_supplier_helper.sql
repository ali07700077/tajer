-- Private supplier eligibility helper is used internally by RLS and RPC routines.
-- It must not be directly callable by anonymous API clients.
revoke execute on function private.is_approved_supplier(uuid) from public, anon;
grant execute on function private.is_approved_supplier(uuid) to authenticated;

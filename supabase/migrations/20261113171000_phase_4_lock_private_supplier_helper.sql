-- The helper backs the public approved-supplier product visibility policy.
-- It returns only a boolean and is safe for anonymous catalog reads; all other
-- private RFQ helpers remain restricted to authenticated callers.
revoke execute on function private.is_approved_supplier(uuid) from public;
grant execute on function private.is_approved_supplier(uuid) to anon, authenticated;

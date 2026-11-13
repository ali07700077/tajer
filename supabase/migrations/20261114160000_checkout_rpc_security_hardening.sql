-- Tighten checkout RPC execution boundaries and pin a safe search_path.
-- These SECURITY DEFINER functions must never resolve objects from a caller-controlled schema.
alter function public.create_retail_orders(jsonb, text) set search_path = '';
alter function public.create_wholesale_orders(uuid, jsonb, text) set search_path = '';

revoke all on function public.create_retail_orders(jsonb, text) from public, anon;
revoke all on function public.create_wholesale_orders(uuid, jsonb, text) from public, anon;
grant execute on function public.create_retail_orders(jsonb, text) to authenticated;
grant execute on function public.create_wholesale_orders(uuid, jsonb, text) to authenticated;

-- Inventory and escrow state transitions remain server-only.
alter function public.append_escrow_ledger_entry(uuid, text, numeric, text, text, jsonb) set search_path = '';
alter function public.confirm_inventory_reservation(uuid) set search_path = '';
alter function public.release_expired_inventory_reservations(integer) set search_path = '';

revoke all on function public.append_escrow_ledger_entry(uuid, text, numeric, text, text, jsonb) from public, anon, authenticated;
revoke all on function public.confirm_inventory_reservation(uuid) from public, anon, authenticated;
revoke all on function public.release_expired_inventory_reservations(integer) from public, anon, authenticated;
grant execute on function public.append_escrow_ledger_entry(uuid, text, numeric, text, text, jsonb) to service_role;
grant execute on function public.confirm_inventory_reservation(uuid) to service_role;
grant execute on function public.release_expired_inventory_reservations(integer) to service_role;

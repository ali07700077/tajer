-- Restore column-level Data API privileges for the retail fields introduced in Phase 5.
-- RLS remains the authorization boundary: suppliers can only change their own products.
grant insert (retail_price, is_retail_available) on table public.products to authenticated;
grant update (retail_price, is_retail_available) on table public.products to authenticated;

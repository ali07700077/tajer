-- Hybrid B2B wholesale + B2C retail product availability.
-- Keep products.price as the existing wholesale unit price to avoid breaking RFQ flows.
alter table public.products
  add column if not exists retail_price numeric(14,2),
  add column if not exists is_retail_available boolean not null default false;

do $$
begin
  if not exists (select 1 from pg_constraint where conname='products_retail_price_positive') then
    alter table public.products add constraint products_retail_price_positive
      check (retail_price is null or retail_price > 0);
  end if;
  if not exists (select 1 from pg_constraint where conname='products_retail_requires_price') then
    alter table public.products add constraint products_retail_requires_price
      check (not is_retail_available or retail_price is not null);
  end if;
end $$;

create index if not exists products_retail_catalog_idx
  on public.products (created_at desc)
  where is_active and is_retail_available and retail_price is not null;

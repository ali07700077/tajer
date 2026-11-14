-- Read-only, explicitly flagged demo catalogue records.
-- No demo/business rows are inserted by this migration.
create table if not exists public.catalog_demo_products (
  id uuid primary key default extensions.gen_random_uuid(),
  sku text,
  name text not null,
  description text,
  price_iqd numeric(14,2) not null check (price_iqd >= 0),
  retail_price_iqd numeric(14,2) check (retail_price_iqd is null or retail_price_iqd >= 0),
  price_usd numeric(14,2) check (price_usd is null or price_usd >= 0),
  retail_price_usd numeric(14,2) check (retail_price_usd is null or retail_price_usd >= 0),
  fx_rate_iqd_per_usd numeric(14,4) check (fx_rate_iqd_per_usd is null or fx_rate_iqd_per_usd > 0),
  min_order_quantity integer not null default 1 check (min_order_quantity > 0),
  stock_quantity integer not null default 0 check (stock_quantity >= 0),
  category_name text,
  supplier_name text,
  governorate_name text,
  is_retail_available boolean not null default false,
  demo_only boolean not null default true,
  created_at timestamptz not null default now()
);

-- CREATE TABLE IF NOT EXISTS does not validate an existing relation's shape.
do $$
declare v_missing text;
begin
  select string_agg(required.column_name, ', ' order by required.column_name)
    into v_missing
  from (values
    ('id'), ('sku'), ('name'), ('description'), ('price_iqd'),
    ('retail_price_iqd'), ('price_usd'), ('retail_price_usd'),
    ('fx_rate_iqd_per_usd'), ('min_order_quantity'), ('stock_quantity'),
    ('category_name'), ('supplier_name'), ('governorate_name'),
    ('is_retail_available'), ('demo_only')
  ) as required(column_name)
  where not exists (
    select 1 from information_schema.columns c
    where c.table_schema = 'public' and c.table_name = 'catalog_demo_products'
      and c.column_name = required.column_name
  );
  if v_missing is not null then
    raise exception 'catalog_demo_products schema mismatch; missing required columns: %', v_missing
      using errcode = '42703';
  end if;
end;
$$;

alter table public.catalog_demo_products enable row level security;
revoke all on public.catalog_demo_products from public, anon, authenticated;
grant select on public.catalog_demo_products to anon, authenticated;
drop policy if exists catalog_demo_products_public_demo_read on public.catalog_demo_products;
create policy catalog_demo_products_public_demo_read
  on public.catalog_demo_products for select to anon, authenticated
  using (demo_only is true);

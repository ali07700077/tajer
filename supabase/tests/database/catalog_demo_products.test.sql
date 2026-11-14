begin;
select plan(8);
select has_table('public', 'catalog_demo_products', 'demo catalogue table exists');
select has_column('public', 'catalog_demo_products', 'demo_only', 'demo flag exists');
select ok(has_table_privilege('anon', 'public.catalog_demo_products', 'SELECT'), 'anon has SELECT privilege');
select ok(not has_table_privilege('anon', 'public.catalog_demo_products', 'INSERT'), 'anon cannot INSERT');
select ok(not has_table_privilege('anon', 'public.catalog_demo_products', 'UPDATE'), 'anon cannot UPDATE');
select ok(not has_table_privilege('anon', 'public.catalog_demo_products', 'DELETE'), 'anon cannot DELETE');

-- Transaction-local fixtures only; migration does not create demo/business data.
insert into public.catalog_demo_products
  (id, name, price_iqd, min_order_quantity, stock_quantity, demo_only)
values
  ('90000000-0000-4000-8000-000000000001', 'pgTAP demo fixture', 1000, 1, 5, true),
  ('90000000-0000-4000-8000-000000000002', 'pgTAP private fixture', 1000, 1, 5, false);

set local role anon;
select is((select count(*)::integer from public.catalog_demo_products
  where id = '90000000-0000-4000-8000-000000000001'), 1,
  'anon can read an explicitly flagged demo row');
select is((select count(*)::integer from public.catalog_demo_products
  where id = '90000000-0000-4000-8000-000000000002'), 0,
  'anon cannot read a row that is not flagged as demo');
reset role;
select * from finish();
rollback;

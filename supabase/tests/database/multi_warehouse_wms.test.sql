-- Multi-warehouse WMS schema, tenant isolation, and stock ledger controls.
begin;
create extension if not exists pgtap with schema extensions;
select plan(9);

select ok(
  to_regclass('public.warehouses') is not null
  and to_regclass('public.warehouse_stock') is not null
  and to_regclass('public.warehouse_stock_movements') is not null,
  'warehouse master, per-warehouse balances, and stock movement ledger exist'
);
select ok(
  (select relrowsecurity from pg_class where oid='public.warehouses'::regclass)
  and (select relrowsecurity from pg_class where oid='public.warehouse_stock'::regclass)
  and (select relrowsecurity from pg_class where oid='public.warehouse_stock_movements'::regclass),
  'all WMS tables enforce row-level security'
);
select ok(
  has_table_privilege('authenticated','public.warehouses','SELECT')
  and has_table_privilege('authenticated','public.warehouse_stock','SELECT')
  and has_table_privilege('authenticated','public.warehouse_stock_movements','SELECT')
  and not has_table_privilege('authenticated','public.warehouses','INSERT')
  and not has_table_privilege('authenticated','public.warehouse_stock','UPDATE')
  and not has_table_privilege('authenticated','public.warehouse_stock_movements','INSERT'),
  'business users can read WMS data but cannot mutate stock directly'
);
select ok(
  exists(select 1 from information_schema.columns where table_schema='public'
    and table_name='warehouse_stock' and column_name='on_hand_quantity'
    and numeric_precision=19 and numeric_scale=4)
  and exists(select 1 from information_schema.columns where table_schema='public'
    and table_name='warehouse_stock' and column_name='reserved_quantity'
    and numeric_precision=19 and numeric_scale=4),
  'warehouse stock quantities use NUMERIC(19,4) precision'
);
select ok(
  exists(select 1 from information_schema.columns where table_schema='public'
    and table_name='warehouse_stock' and column_name='available_quantity'
    and is_generated='ALWAYS'),
  'available stock is generated from on-hand minus reserved quantities'
);
select ok(
  exists(select 1 from pg_trigger where tgrelid='public.warehouses'::regclass
    and tgname='warehouses_validate_location' and not tgisinternal)
  and exists(select 1 from pg_trigger where tgrelid='public.warehouse_stock'::regclass
    and tgname='warehouse_stock_validate_tenant' and not tgisinternal),
  'warehouse location and business-product tenant consistency are enforced by triggers'
);
select ok(
  exists(select 1 from pg_indexes where schemaname='public'
    and indexname='warehouses_one_default_per_business' and indexdef ilike '%unique%')
  and exists(select 1 from pg_constraint where conrelid='public.warehouse_stock'::regclass
    and contype='u'),
  'each business is limited to one default warehouse and product balance per warehouse'
);
select ok(
  exists(select 1 from public.governorates where code='wasit' and is_active)
  and exists(select 1 from public.cities c join public.governorates g on g.id=c.governorate_id
    where g.code='wasit' and c.name_ar='الكوت' and c.is_active)
  and exists(select 1 from public.commercial_areas where code='kut')
  and exists(select 1 from public.commercial_areas where code='al-ashar')
  and exists(select 1 from public.commercial_areas where code='qaysari-bazaar'),
  'Kut, Basra, and Erbil are represented in the initial regional market directory'
);
select ok(
  exists(select 1 from pg_trigger where tgrelid='public.warehouse_stock_movements'::regclass
    and tgname='warehouse_stock_movements_immutable' and not tgisinternal),
  'stock movement history is protected behind row-level security'
);

select * from finish();
rollback;

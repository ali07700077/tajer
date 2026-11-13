-- Inventory reservation lifecycle and escrow ledger security boundary.
begin;
create extension if not exists pgtap with schema extensions;
select plan(12);
select ok(
  exists(select 1 from information_schema.columns where table_schema='public' and table_name='products' and column_name='reserved_quantity'),
  'products persist the quantity held by pending checkouts'
);
select ok(
  exists(select 1 from information_schema.columns where table_schema='public' and table_name='products' and column_name='available_quantity' and is_generated='ALWAYS'),
  'available stock is a database-generated value'
);
select ok(
  (select relrowsecurity from pg_class where oid='public.inventory_reservations'::regclass),
  'inventory reservations enforce row-level security'
);
select ok(
  not has_table_privilege('anon','public.inventory_reservations','SELECT')
  and not has_table_privilege('authenticated','public.inventory_reservations','INSERT'),
  'reservation rows are participant-readable and never client-writable'
);
select ok(
  (select relrowsecurity from pg_class where oid='public.escrow_ledger_entries'::regclass),
  'escrow ledger entries enforce row-level security'
);
select ok(
  not has_table_privilege('anon','public.escrow_ledger_entries','SELECT')
  and not has_table_privilege('authenticated','public.escrow_ledger_entries','INSERT'),
  'escrow ledger is private and append access is server-only'
);
select ok(
  has_function_privilege('service_role','public.confirm_inventory_reservation(uuid)','EXECUTE')
  and has_function_privilege('service_role','public.release_expired_inventory_reservations(integer)','EXECUTE'),
  'only trusted server workflows can commit or release reservations'
);
select ok(
  not has_function_privilege('authenticated','public.confirm_inventory_reservation(uuid)','EXECUTE')
  and not has_function_privilege('anon','public.append_escrow_ledger_entry(uuid,text,numeric,text,text,jsonb)','EXECUTE'),
  'browser clients cannot confirm stock or append financial ledger entries'
);
select ok(
  exists(select 1 from pg_trigger where tgrelid='public.escrow_ledger_entries'::regclass and tgname='escrow_ledger_entries_immutable' and not tgisinternal),
  'escrow ledger rejects update and delete mutations'
);

select ok(
  to_regprocedure('public.create_retail_orders(jsonb,text)') is not null
  and has_function_privilege('authenticated','public.create_retail_orders(jsonb,text)','EXECUTE')
  and not has_function_privilege('anon','public.create_retail_orders(jsonb,text)','EXECUTE'),
  'retail checkout is exposed only to authenticated customers'
);
select ok(
  has_function_privilege('authenticated','public.create_wholesale_orders(uuid,jsonb,text)','EXECUTE')
  and not has_function_privilege('anon','public.create_wholesale_orders(uuid,jsonb,text)','EXECUTE'),
  'wholesale checkout is exposed only to authenticated business buyers'
);
select ok(
  not has_function_privilege('authenticated','public.release_expired_inventory_reservations(integer)','EXECUTE')
  and has_function_privilege('service_role','public.release_expired_inventory_reservations(integer)','EXECUTE'),
  'reservation expiry processing is restricted to trusted server workflows'
);

select * from finish();
rollback;

-- Regression coverage for the hybrid B2B checkout and trade-document security boundary.
begin;
create extension if not exists pgtap with schema extensions;
select plan(8);

select ok(
  to_regprocedure('public.create_wholesale_orders(uuid,jsonb,text)') is not null,
  'wholesale checkout RPC is installed'
);
select ok(
  has_function_privilege('authenticated','public.create_wholesale_orders(uuid,jsonb,text)','EXECUTE'),
  'authenticated buyers can invoke wholesale checkout'
);
select ok(
  not has_function_privilege('anon','public.create_wholesale_orders(uuid,jsonb,text)','EXECUTE'),
  'anonymous users cannot invoke wholesale checkout'
);
select ok(
  to_regprocedure('public.create_product_sample_request(uuid,uuid,integer,text)') is not null
  and has_function_privilege('authenticated','public.create_product_sample_request(uuid,uuid,integer,text)','EXECUTE')
  and not has_function_privilege('anon','public.create_product_sample_request(uuid,uuid,integer,text)','EXECUTE'),
  'paid sample requests are available only through the authenticated RPC'
);
select ok(
  to_regprocedure('public.create_proforma_invoice(uuid,date,text)') is not null
  and has_function_privilege('authenticated','public.create_proforma_invoice(uuid,date,text)','EXECUTE')
  and not has_function_privilege('anon','public.create_proforma_invoice(uuid,date,text)','EXECUTE'),
  'proforma invoices are issued through the authenticated supplier RPC'
);
select ok(
  (select relrowsecurity from pg_class where oid='public.product_sample_requests'::regclass)
  and (select relrowsecurity from pg_class where oid='public.proforma_invoices'::regclass)
  and (select relrowsecurity from pg_class where oid='public.proforma_invoice_items'::regclass),
  'sample requests and proforma documents enforce row level security'
);
select ok(
  not has_table_privilege('anon','public.product_sample_requests','SELECT')
  and not has_table_privilege('anon','public.proforma_invoices','SELECT')
  and not has_table_privilege('anon','public.proforma_invoice_items','SELECT'),
  'anonymous users cannot read private trade documents'
);
select ok(
  exists (select 1 from information_schema.columns where table_schema='public' and table_name='products' and column_name='sample_available')
  and exists (select 1 from information_schema.columns where table_schema='public' and table_name='products' and column_name='sample_price')
  and exists (select 1 from information_schema.columns where table_schema='public' and table_name='products' and column_name='sample_max_quantity'),
  'supplier sample configuration is persisted on products'
);

select * from finish();
rollback;

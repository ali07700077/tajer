-- Tenant isolation and RFQ authorization regression tests.
-- Run with: supabase test db
begin;

create extension if not exists pgtap with schema extensions;
select plan(31);

insert into auth.users
  (id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data)
values
  ('90000000-0000-4000-8000-000000000001','authenticated','authenticated','rls-buyer@tajer.test','',now(),'{}'::jsonb,'{}'::jsonb),
  ('90000000-0000-4000-8000-000000000002','authenticated','authenticated','rls-supplier-a@tajer.test','',now(),'{}'::jsonb,'{}'::jsonb),
  ('90000000-0000-4000-8000-000000000003','authenticated','authenticated','rls-supplier-b@tajer.test','',now(),'{}'::jsonb,'{}'::jsonb)
on conflict (id) do nothing;

insert into public.business_members (business_id,user_id,member_role)
values
  ('10000000-0000-4000-8000-000000000003','90000000-0000-4000-8000-000000000001','owner'),
  ('10000000-0000-4000-8000-000000000001','90000000-0000-4000-8000-000000000002','owner'),
  ('10000000-0000-4000-8000-000000000002','90000000-0000-4000-8000-000000000003','owner')
on conflict (business_id,user_id) do nothing;

-- Signed-out visitors may browse approved products, but never RFQ data or private helpers.
set local role anon;
select ok(
  not has_table_privilege('anon','public.rfqs','SELECT'),
  'anonymous visitors have no table-level access to RFQs'
);
select ok(
  not has_function_privilege('anon','private.can_view_rfq(uuid)','EXECUTE'),
  'anonymous visitors cannot call internal RFQ visibility helpers'
);
select ok(
  has_function_privilege('anon','private.is_approved_supplier(uuid)','EXECUTE'),
  'anonymous catalog reads can evaluate approved supplier visibility'
);
select is(
  (select count(*)::bigint from public.governorates where is_active),
  19::bigint,
  'all 19 Iraqi governorates are available as active reference data'
);
select is(
  (select count(*)::bigint from public.products where id in (
    '20000000-0000-4000-8000-000000000001',
    '20000000-0000-4000-8000-000000000002'
  )),
  2::bigint,
  'anonymous visitors can read active products from approved suppliers'
);
reset role;

select ok(
  has_column_privilege('authenticated','public.products','retail_price','INSERT')
  and has_column_privilege('authenticated','public.products','is_retail_available','INSERT'),
  'authenticated suppliers can insert retail pricing fields subject to product RLS'
);
select ok(
  has_column_privilege('authenticated','public.products','retail_price','UPDATE')
  and has_column_privilege('authenticated','public.products','is_retail_available','UPDATE'),
  'authenticated suppliers can update retail pricing fields subject to product RLS'
);

-- Supplier A sees the RFQ and only the item assigned to Supplier A.
set local role authenticated;
set local request.jwt.claim.sub = '90000000-0000-4000-8000-000000000002';
select is(
  (select count(*)::bigint from public.rfq_items where rfq_id='30000000-0000-4000-8000-000000000001'),
  1::bigint,
  'supplier A sees only its own RFQ item'
);
select is(
  (select count(*)::bigint from public.rfq_items
   where rfq_id='30000000-0000-4000-8000-000000000001'
     and supplier_business_id='10000000-0000-4000-8000-000000000002'),
  0::bigint,
  'supplier A cannot read supplier B item'
);
reset role;

-- Supplier B sees its own item, while the buyer sees the complete RFQ.
set local role authenticated;
set local request.jwt.claim.sub = '90000000-0000-4000-8000-000000000003';
select is(
  (select count(*)::bigint from public.rfq_items where rfq_id='30000000-0000-4000-8000-000000000001'),
  1::bigint,
  'supplier B sees only its own RFQ item'
);
reset role;

set local role authenticated;
set local request.jwt.claim.sub = '90000000-0000-4000-8000-000000000001';
select is(
  (select count(*)::bigint from public.rfq_items where rfq_id='30000000-0000-4000-8000-000000000001'),
  2::bigint,
  'buyer sees all items in its RFQ'
);
select is(
  (select count(*)::bigint from public.rfqs where id='30000000-0000-4000-8000-000000000001'),
  1::bigint,
  'buyer can read its own RFQ'
);
reset role;

select ok(
  not has_table_privilege('authenticated','public.rfq_offers','INSERT'),
  'clients cannot bypass the validated offer submission RPC'
);
select ok(
  has_function_privilege('authenticated','public.submit_rfq_offer(uuid,uuid,numeric,integer,text)','EXECUTE'),
  'authenticated suppliers can submit offers through the validated RPC'
);
select ok(
  not has_function_privilege('anon','public.submit_rfq_offer(uuid,uuid,numeric,integer,text)','EXECUTE'),
  'anonymous visitors cannot submit RFQ offers'
);


select ok(
  (select is_nullable='YES' from information_schema.columns
   where table_schema='public' and table_name='orders' and column_name='buyer_business_id'),
  'retail orders may omit a buyer business'
);
select ok(
  exists (select 1 from information_schema.columns where table_schema='public' and table_name='orders' and column_name='buyer_user_id')
  and exists (select 1 from information_schema.columns where table_schema='public' and table_name='orders' and column_name='order_type'),
  'orders distinguish personal buyers from business buyers'
);
select ok(
  has_function_privilege('authenticated','public.create_retail_orders(jsonb,text)','EXECUTE'),
  'authenticated users can create retail orders through the validated RPC'
);
select ok(
  not has_function_privilege('anon','public.create_retail_orders(jsonb,text)','EXECUTE'),
  'anonymous users cannot create retail orders'
);
select ok(
  (select relrowsecurity from pg_class where oid='public.orders'::regclass)
  and (select relrowsecurity from pg_class where oid='public.order_items'::regclass),
  'orders and order items enforce row level security'
);


-- A personal retail buyer may buy below the wholesale MOQ; the server prices from retail_price.
update public.products
set retail_price=1250, is_retail_available=true, stock_quantity=10
where id='20000000-0000-4000-8000-000000000001';

set local role authenticated;
set local request.jwt.claim.sub = '90000000-0000-4000-8000-000000000001';
select is(
  jsonb_array_length(public.create_retail_orders(
    '[{"product_id":"20000000-0000-4000-8000-000000000001","quantity":2}]'::jsonb,
    'بغداد، الكرادة، شارع ١'
  )),
  1,
  'retail checkout creates one supplier order without applying wholesale MOQ'
);
select is(
  (select count(*)::bigint from public.orders
   where buyer_user_id='90000000-0000-4000-8000-000000000001' and order_type='b2c'),
  1::bigint,
  'retail order is owned by the authenticated personal buyer'
);
select is(
  (select unit_price from public.order_items oi join public.orders o on o.id=oi.order_id
   where o.buyer_user_id='90000000-0000-4000-8000-000000000001' and o.order_type='b2c'
   limit 1),
  1250::numeric,
  'retail order snapshots the retail unit price, not the wholesale price'
);
select is(
  (select total_amount from public.orders
   where buyer_user_id='90000000-0000-4000-8000-000000000001' and order_type='b2c'
   limit 1),
  2500::numeric,
  'retail order total is calculated on the server'
);
reset role;
select is(
  (select stock_quantity from public.products where id='20000000-0000-4000-8000-000000000001'),
  8,
  'retail checkout atomically reserves stock'
);


-- Tiered wholesale pricing and MOQ integrity.
insert into public.products (id,business_id,name,price,min_order_quantity,stock_quantity,is_active)
values ('20000000-0000-4000-8000-000000000003','10000000-0000-4000-8000-000000000001','Tier validation fixture',10000,10,100,true)
on conflict (id) do update set price=10000,min_order_quantity=10,stock_quantity=100,is_active=true;
insert into public.product_price_tiers (product_id,min_quantity,unit_price)
values ('20000000-0000-4000-8000-000000000003',10,9000),('20000000-0000-4000-8000-000000000003',20,8000)
on conflict (product_id,min_quantity) do update set unit_price=excluded.unit_price;

select is((select count(*)::bigint from public.product_price_tiers where product_id='20000000-0000-4000-8000-000000000003'),2::bigint,'a supplier can maintain multiple increasing-quantity wholesale price tiers');
select throws_ok($$insert into public.product_price_tiers(product_id,min_quantity,unit_price) values('20000000-0000-4000-8000-000000000003',5,7000)$$,'P0001','كمية شريحة السعر أقل من الحد الأدنى للطلب','a wholesale tier cannot start below the product MOQ');
select throws_ok($$insert into public.product_price_tiers(product_id,min_quantity,unit_price) values('20000000-0000-4000-8000-000000000003',30,8500)$$,'P0001','يجب ألا يرتفع سعر الوحدة مع زيادة كمية الجملة','unit price cannot increase when the wholesale quantity threshold increases');
select throws_ok($$update public.products set min_order_quantity=25 where id='20000000-0000-4000-8000-000000000003'$$,'P0001','تغيير الحد الأدنى سيجعل شرائح الأسعار الحالية غير صالحة','raising MOQ cannot invalidate existing wholesale tiers');
select throws_ok($$update public.products set price=7500 where id='20000000-0000-4000-8000-000000000003'$$,'P0001','تغيير سعر الجملة الأساسي سيجعل شرائح الأسعار الحالية غير صالحة','lowering the base wholesale price cannot invalidate existing tiers');
select ok((select relrowsecurity from pg_class where oid='public.product_price_tiers'::regclass) and has_table_privilege('authenticated','public.product_price_tiers','SELECT') and has_table_privilege('authenticated','public.product_price_tiers','INSERT'),'wholesale tiers remain protected by RLS while authenticated clients use supplier policies');

select * from finish();
rollback;

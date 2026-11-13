-- Tenant isolation and RFQ authorization regression tests.
-- Run with: supabase test db
begin;

create extension if not exists pgtap with schema extensions;
select plan(13);

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
select is(
  (select count(*)::bigint from public.rfqs where id='30000000-0000-4000-8000-000000000001'),
  0::bigint,
  'anonymous visitors cannot read RFQs'
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

select * from finish();
rollback;

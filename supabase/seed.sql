-- TAJER deterministic demo fixtures. Safe for local Supabase and disposable branches only.
-- These records contain no real users or credentials. Auth users are created per test run.
begin;

insert into public.businesses
  (id,business_type,name_ar,name_en,governorate_id,verification_status,is_active,created_by)
values
  ('10000000-0000-4000-8000-000000000001','supplier','مورد بغداد الأول','Baghdad Supplier One',(select id from public.governorates where code='baghdad' limit 1),'approved',true,null),
  ('10000000-0000-4000-8000-000000000002','supplier','مورد بغداد الثاني','Baghdad Supplier Two',(select id from public.governorates where code='baghdad' limit 1),'approved',true,null),
  ('10000000-0000-4000-8000-000000000003','buyer','مشتري تجريبي','Demo Buyer',(select id from public.governorates where code='baghdad' limit 1),'approved',true,null)
on conflict (id) do update set
  name_ar=excluded.name_ar, name_en=excluded.name_en,
  verification_status=excluded.verification_status, is_active=excluded.is_active;

insert into public.products
  (id,business_id,name,description,sku,price,min_order_quantity,stock_quantity,is_active)
values
  ('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','رز بسمتي تجريبي 5 كغم','منتج تجريبي لاختبار العزل وطلبات الأسعار','SEED-RICE-01',25000,10,500,true),
  ('20000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000002','زيت طبخ تجريبي 1 لتر','منتج تجريبي للمورد الثاني','SEED-OIL-02',3000,24,800,true)
on conflict (id) do update set
  name=excluded.name, description=excluded.description, price=excluded.price,
  min_order_quantity=excluded.min_order_quantity, stock_quantity=excluded.stock_quantity,
  is_active=excluded.is_active;

insert into public.rfqs
  (id,buyer_business_id,title,description,status,delivery_governorate_id)
values
  ('30000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000003',
   'طلب تجريبي متعدد الموردين','طلب تجريبي للتحقق من صلاحيات رؤية الموردين','open',
   (select id from public.governorates where code='baghdad' limit 1))
on conflict (id) do update set status='open', awarded_offer_id=null;

insert into public.rfq_items (id,rfq_id,product_id,supplier_business_id,quantity)
values
 ('40000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001',20),
 ('40000000-0000-4000-8000-000000000002','30000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000002',30)
on conflict (id) do update set quantity=excluded.quantity;

commit;

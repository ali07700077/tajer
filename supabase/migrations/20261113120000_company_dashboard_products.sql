alter table public.products add column if not exists image_path text;

insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('product-images','product-images',false,5242880,array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public=false,file_size_limit=5242880,allowed_mime_types=array['image/jpeg','image/png','image/webp'];

drop policy if exists products_supplier_manage on public.products;
drop policy if exists products_insert_business_manager on public.products;
drop policy if exists products_update_business_manager on public.products;
drop policy if exists products_delete_business_manager on public.products;
drop policy if exists products_company_select on public.products;
drop policy if exists products_company_insert on public.products;
drop policy if exists products_company_update on public.products;
drop policy if exists products_company_delete on public.products;

create policy products_company_select on public.products
for select to authenticated
using (public.has_business_role(business_id, array['owner'::public.member_role,'manager'::public.member_role]));

create policy products_company_insert on public.products
for insert to authenticated
with check (
  public.has_business_role(business_id, array['owner'::public.member_role,'manager'::public.member_role])
  and exists (select 1 from public.businesses b where b.id=products.business_id and b.business_type='supplier'::public.business_type)
);

create policy products_company_update on public.products
for update to authenticated
using (public.has_business_role(business_id, array['owner'::public.member_role,'manager'::public.member_role]))
with check (
  public.has_business_role(business_id, array['owner'::public.member_role,'manager'::public.member_role])
  and exists (select 1 from public.businesses b where b.id=products.business_id and b.business_type='supplier'::public.business_type)
);

create policy products_company_delete on public.products
for delete to authenticated
using (public.has_business_role(business_id, array['owner'::public.member_role,'manager'::public.member_role]));

drop policy if exists product_images_company_select on storage.objects;
drop policy if exists product_images_company_insert on storage.objects;
drop policy if exists product_images_company_update on storage.objects;
drop policy if exists product_images_company_delete on storage.objects;

create policy product_images_company_select on storage.objects
for select to authenticated
using (bucket_id='product-images' and public.has_business_role(((storage.foldername(name))[1])::uuid,array['owner'::public.member_role,'manager'::public.member_role]));

create policy product_images_company_insert on storage.objects
for insert to authenticated
with check (bucket_id='product-images' and public.has_business_role(((storage.foldername(name))[1])::uuid,array['owner'::public.member_role,'manager'::public.member_role]));

create policy product_images_company_update on storage.objects
for update to authenticated
using (bucket_id='product-images' and public.has_business_role(((storage.foldername(name))[1])::uuid,array['owner'::public.member_role,'manager'::public.member_role]))
with check (bucket_id='product-images' and public.has_business_role(((storage.foldername(name))[1])::uuid,array['owner'::public.member_role,'manager'::public.member_role]));

create policy product_images_company_delete on storage.objects
for delete to authenticated
using (bucket_id='product-images' and public.has_business_role(((storage.foldername(name))[1])::uuid,array['owner'::public.member_role,'manager'::public.member_role]));

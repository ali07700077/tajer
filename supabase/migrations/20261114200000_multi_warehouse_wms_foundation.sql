-- TAJER multi-warehouse WMS foundation.
-- Additive migration: existing product-level stock remains the compatibility aggregate.
-- Warehouse balances are initialized from existing products into each business default warehouse.

create table if not exists public.warehouses (
  id uuid primary key default extensions.gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete restrict,
  governorate_id uuid not null references public.governorates(id) on delete restrict,
  city_id uuid references public.cities(id) on delete restrict,
  code text not null check (code ~ '^[a-zA-Z0-9_-]{2,40}$'),
  name_ar text not null check (char_length(trim(name_ar)) between 2 and 140),
  name_en text check (name_en is null or char_length(name_en)<=140),
  warehouse_type text not null default 'standard'
    check (warehouse_type in ('standard','distribution_center','storefront','fulfillment','returns')),
  address_text text,
  latitude numeric(9,6) check (latitude is null or latitude between -90 and 90),
  longitude numeric(9,6) check (longitude is null or longitude between -180 and 180),
  is_default boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(business_id,code),
  check (city_id is null or governorate_id is not null)
);
create unique index if not exists warehouses_one_default_per_business
  on public.warehouses(business_id) where is_default;
create index if not exists warehouses_business_location_idx
  on public.warehouses(business_id,governorate_id,city_id) where is_active;

create table if not exists public.warehouse_stock (
  id uuid primary key default extensions.gen_random_uuid(),
  warehouse_id uuid not null references public.warehouses(id) on delete restrict,
  business_id uuid not null references public.businesses(id) on delete restrict,
  product_id uuid not null references public.products(id) on delete restrict,
  on_hand_quantity numeric(19,4) not null default 0 check (on_hand_quantity>=0),
  reserved_quantity numeric(19,4) not null default 0 check (reserved_quantity>=0),
  available_quantity numeric(19,4) generated always as (on_hand_quantity-reserved_quantity) stored,
  updated_at timestamptz not null default now(),
  unique(warehouse_id,product_id),
  check (reserved_quantity<=on_hand_quantity)
);
create index if not exists warehouse_stock_business_product_idx
  on public.warehouse_stock(business_id,product_id);
create index if not exists warehouse_stock_available_idx
  on public.warehouse_stock(product_id,available_quantity);

create table if not exists public.warehouse_stock_movements (
  id uuid primary key default extensions.gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete restrict,
  product_id uuid not null references public.products(id) on delete restrict,
  movement_type text not null check (movement_type in ('receipt','issue','adjustment','transfer_in','transfer_out')),
  source_warehouse_id uuid references public.warehouses(id) on delete restrict,
  destination_warehouse_id uuid references public.warehouses(id) on delete restrict,
  quantity numeric(19,4) not null check (quantity>0),
  reference_type text,
  reference_id uuid,
  idempotency_key text not null check (char_length(trim(idempotency_key))>=8),
  actor_id uuid references auth.users(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique(business_id,idempotency_key),
  check (
    (movement_type in ('receipt','adjustment') and destination_warehouse_id is not null and source_warehouse_id is null)
    or (movement_type='issue' and source_warehouse_id is not null and destination_warehouse_id is null)
    or (movement_type='transfer_in' and source_warehouse_id is not null and destination_warehouse_id is not null and source_warehouse_id<>destination_warehouse_id)
    or (movement_type='transfer_out' and source_warehouse_id is not null and destination_warehouse_id is not null and source_warehouse_id<>destination_warehouse_id)
  )
);
create index if not exists warehouse_movements_product_created_idx
  on public.warehouse_stock_movements(product_id,created_at desc);
create index if not exists warehouse_movements_business_created_idx
  on public.warehouse_stock_movements(business_id,created_at desc);

-- Validate that a warehouse location belongs to the selected governorate and that
-- stock rows cannot mix a warehouse, business, and product from different tenants.
create or replace function public.validate_warehouse_location()
returns trigger language plpgsql set search_path='' as $$
begin
  if new.city_id is not null and not exists (
    select 1 from public.cities c where c.id=new.city_id
      and c.governorate_id=new.governorate_id and c.is_active
  ) then
    raise exception 'city does not belong to selected governorate' using errcode='23514';
  end if;
  return new;
end;
$$;
drop trigger if exists warehouses_validate_location on public.warehouses;
create trigger warehouses_validate_location
before insert or update of governorate_id,city_id on public.warehouses
for each row execute function public.validate_warehouse_location();

create or replace function public.validate_warehouse_stock_tenant()
returns trigger language plpgsql set search_path='' as $$
begin
  if not exists(select 1 from public.warehouses w
    where w.id=new.warehouse_id and w.business_id=new.business_id) then
    raise exception 'warehouse does not belong to selected business' using errcode='23514';
  end if;
  if not exists(select 1 from public.products p
    where p.id=new.product_id and p.business_id=new.business_id) then
    raise exception 'product does not belong to selected business' using errcode='23514';
  end if;
  return new;
end;
$$;
drop trigger if exists warehouse_stock_validate_tenant on public.warehouse_stock;
create trigger warehouse_stock_validate_tenant
before insert or update of warehouse_id,business_id,product_id on public.warehouse_stock
for each row execute function public.validate_warehouse_stock_tenant();

alter table public.warehouses enable row level security;
alter table public.warehouse_stock enable row level security;
alter table public.warehouse_stock_movements enable row level security;
revoke all on public.warehouses,public.warehouse_stock,public.warehouse_stock_movements from anon,authenticated;
grant select on public.warehouses,public.warehouse_stock,public.warehouse_stock_movements to authenticated;

drop policy if exists warehouses_member_read on public.warehouses;
create policy warehouses_member_read on public.warehouses for select to authenticated
using (public.is_business_member(business_id));
drop policy if exists warehouse_stock_member_read on public.warehouse_stock;
create policy warehouse_stock_member_read on public.warehouse_stock for select to authenticated
using (public.is_business_member(business_id));
drop policy if exists warehouse_movements_member_read on public.warehouse_stock_movements;
create policy warehouse_movements_member_read on public.warehouse_stock_movements for select to authenticated
using (public.is_business_member(business_id));

revoke all on function public.validate_warehouse_location() from public,anon,authenticated;
revoke all on function public.validate_warehouse_stock_tenant() from public,anon,authenticated;

-- One default warehouse per existing business, located at its registered city/governorate.
insert into public.warehouses(business_id,governorate_id,city_id,code,name_ar,name_en,is_default)
select b.id,b.governorate_id,b.city_id,'MAIN','المخزن الرئيسي','Main Warehouse',true
from public.businesses b
where not exists(select 1 from public.warehouses w where w.business_id=b.id and w.is_default)
on conflict(business_id,code) do nothing;

-- Preserve current product stock by seeding it into the corresponding default warehouse.
insert into public.warehouse_stock(warehouse_id,business_id,product_id,on_hand_quantity,reserved_quantity)
select w.id,p.business_id,p.id,p.stock_quantity,p.reserved_quantity
from public.products p
join public.warehouses w on w.business_id=p.business_id and w.is_default
on conflict(warehouse_id,product_id) do nothing;

-- First regional commercial-market directory slice: Kut, Basra, and Erbil.
insert into public.commercial_areas(city_id,code,name_ar,name_en,area_type,description_ar,sort_order)
select c.id,v.code,v.name_ar,v.name_en,v.area_type,v.description_ar,v.sort_order
from (values
 ('wasit','الكوت','الكوت','Kut','commercial_district','مركز تجاري وخدمي في مدينة الكوت',1,'wasit'),
 ('basra','البصرة','العشار','Al-Ashar','commercial_district','منطقة تجارية مركزية في البصرة',2,'basra'),
 ('basra','البصرة','سوق المغايز','Al-Maghayiz Market','wholesale_market','منطقة أسواق وتجارة في البصرة',3,'basra'),
 ('erbil','أربيل','سوق القيصرية','Qaysari Bazaar','retail_market','سوق تجاري تقليدي في أربيل',4,'erbil'),
 ('erbil','أربيل','المنطقة الصناعية','Industrial Area','industrial_zone','منطقة الأنشطة الصناعية والتجارية في أربيل',5,'erbil')
) as v(governorate_code,city_name,name_ar,name_en,area_type,description_ar,sort_order,city_code)
join public.governorates g on g.code=v.governorate_code
join public.cities c on c.governorate_id=g.id and c.name_ar=v.city_name
on conflict(code) do update set
 name_ar=excluded.name_ar,name_en=excluded.name_en,area_type=excluded.area_type,
 description_ar=excluded.description_ar,is_active=true,sort_order=excluded.sort_order;

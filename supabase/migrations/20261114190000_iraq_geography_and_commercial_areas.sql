-- TAJER Iraqi geographic hierarchy and commercial-area reference layer.
-- This is additive: existing governorates/cities/business addresses and seed fixtures remain valid.
-- The migration deliberately seeds governorate seats and a Baghdad pilot market directory;
-- exhaustive district/neighborhood coverage must be imported from a reviewed official dataset.

create table if not exists public.districts (
  id uuid primary key default extensions.gen_random_uuid(),
  city_id uuid not null references public.cities(id) on delete restrict,
  code text not null check (code ~ '^[a-z][a-z0-9-]*$'),
  name_ar text not null check (char_length(trim(name_ar)) between 2 and 120),
  name_en text check (name_en is null or char_length(name_en)<=120),
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(city_id,code),
  unique(city_id,name_ar)
);
create index if not exists districts_city_active_idx on public.districts(city_id,is_active,sort_order);

create table if not exists public.neighborhoods (
  id uuid primary key default extensions.gen_random_uuid(),
  district_id uuid not null references public.districts(id) on delete restrict,
  code text not null check (code ~ '^[a-z][a-z0-9-]*$'),
  name_ar text not null check (char_length(trim(name_ar)) between 2 and 120),
  name_en text check (name_en is null or char_length(name_en)<=120),
  postal_code text,
  latitude numeric(9,6) check (latitude is null or latitude between -90 and 90),
  longitude numeric(9,6) check (longitude is null or longitude between -180 and 180),
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(district_id,code),
  unique(district_id,name_ar)
);
create index if not exists neighborhoods_district_active_idx on public.neighborhoods(district_id,is_active,sort_order);

create table if not exists public.commercial_areas (
  id uuid primary key default extensions.gen_random_uuid(),
  city_id uuid not null references public.cities(id) on delete restrict,
  district_id uuid references public.districts(id) on delete restrict,
  neighborhood_id uuid references public.neighborhoods(id) on delete restrict,
  code text not null unique check (code ~ '^[a-z][a-z0-9-]*$'),
  name_ar text not null check (char_length(trim(name_ar)) between 2 and 160),
  name_en text check (name_en is null or char_length(name_en)<=160),
  area_type text not null check (area_type in ('wholesale_market','retail_market','commercial_district','industrial_zone','logistics_hub')),
  description_ar text,
  latitude numeric(9,6) check (latitude is null or latitude between -90 and 90),
  longitude numeric(9,6) check (longitude is null or longitude between -180 and 180),
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (neighborhood_id is null or district_id is not null)
);
create index if not exists commercial_areas_city_type_idx on public.commercial_areas(city_id,area_type,is_active,sort_order);
create index if not exists commercial_areas_district_idx on public.commercial_areas(district_id) where district_id is not null;

-- Keep hierarchy internally consistent even when records are inserted outside the UI.
create or replace function public.validate_commercial_geography()
returns trigger language plpgsql set search_path='' as $$
begin
  if new.district_id is not null and not exists (
    select 1 from public.districts d where d.id=new.district_id and d.city_id=new.city_id
  ) then
    raise exception 'district does not belong to selected city' using errcode='23514';
  end if;
  if new.neighborhood_id is not null and not exists (
    select 1 from public.neighborhoods n
    join public.districts d on d.id=n.district_id
    where n.id=new.neighborhood_id and n.district_id=new.district_id and d.city_id=new.city_id
  ) then
    raise exception 'neighborhood does not belong to selected district and city' using errcode='23514';
  end if;
  return new;
end;
$$;
drop trigger if exists commercial_areas_validate_geography on public.commercial_areas;
create trigger commercial_areas_validate_geography
before insert or update of city_id,district_id,neighborhood_id on public.commercial_areas
for each row execute function public.validate_commercial_geography();

create or replace function public.validate_neighborhood_geography()
returns trigger language plpgsql set search_path='' as $$
begin
  if not exists(select 1 from public.districts d where d.id=new.district_id) then
    raise exception 'district does not exist' using errcode='23503';
  end if;
  return new;
end;
$$;
drop trigger if exists neighborhoods_validate_geography on public.neighborhoods;
create trigger neighborhoods_validate_geography
before insert or update of district_id on public.neighborhoods
for each row execute function public.validate_neighborhood_geography();

-- Add optional structured commercial address without invalidating existing business records.
alter table public.businesses
  add column if not exists commercial_area_id uuid references public.commercial_areas(id) on delete set null;
create index if not exists businesses_commercial_area_idx on public.businesses(commercial_area_id)
where commercial_area_id is not null;

-- Public directory data is read-only to browser clients. All reference-data writes are privileged.
alter table public.districts enable row level security;
alter table public.neighborhoods enable row level security;
alter table public.commercial_areas enable row level security;

revoke all on public.districts,public.neighborhoods,public.commercial_areas from anon,authenticated;
grant select on public.districts,public.neighborhoods,public.commercial_areas to anon,authenticated;

drop policy if exists districts_public_active_read on public.districts;
create policy districts_public_active_read on public.districts
for select to anon,authenticated using (is_active);
drop policy if exists neighborhoods_public_active_read on public.neighborhoods;
create policy neighborhoods_public_active_read on public.neighborhoods
for select to anon,authenticated using (
  is_active and exists(select 1 from public.districts d where d.id=district_id and d.is_active)
);
drop policy if exists commercial_areas_public_active_read on public.commercial_areas;
create policy commercial_areas_public_active_read on public.commercial_areas
for select to anon,authenticated using (
  is_active
  and exists(select 1 from public.cities c where c.id=city_id and c.is_active)
  and (district_id is null or exists(select 1 from public.districts d where d.id=district_id and d.is_active))
);

revoke all on function public.validate_commercial_geography() from public,anon,authenticated;
revoke all on function public.validate_neighborhood_geography() from public,anon,authenticated;

-- One canonical city/administrative seat per Iraqi governorate, preserving pre-existing city IDs.
insert into public.cities(governorate_id,name_ar,name_en,is_active,sort_order)
select g.id,v.name_ar,v.name_en,true,v.sort_order
from (values
 ('baghdad','بغداد','Baghdad',1),
 ('basra','البصرة','Basra',2),
 ('nineveh','الموصل','Mosul',3),
 ('erbil','أربيل','Erbil',4),
 ('sulaymaniyah','السليمانية','Sulaymaniyah',5),
 ('duhok','دهوك','Duhok',6),
 ('halabja','حلبجة','Halabja',7),
 ('kirkuk','كركوك','Kirkuk',8),
 ('diyala','بعقوبة','Baqubah',9),
 ('saladin','تكريت','Tikrit',10),
 ('anbar','الرمادي','Ramadi',11),
 ('babylon','الحلة','Hillah',12),
 ('karbala','كربلاء','Karbala',13),
 ('najaf','النجف','Najaf',14),
 ('wasit','الكوت','Kut',15),
 ('maysan','العمارة','Amarah',16),
 ('dhi-qar','الناصرية','Nasiriyah',17),
 ('muthanna','السماوة','Samawah',18),
 ('qadisiyyah','الديوانية','Diwaniyah',19)
) as v(governorate_code,name_ar,name_en,sort_order)
join public.governorates g on g.code=v.governorate_code
on conflict(governorate_id,name_ar) do update
set name_en=excluded.name_en,is_active=true,sort_order=excluded.sort_order;

-- First verified-ready commercial directory slice: Baghdad. These are named market/
-- commercial districts, not a claim of complete street-level mapping for Iraq.
insert into public.commercial_areas(city_id,code,name_ar,name_en,area_type,description_ar,sort_order)
select c.id,v.code,v.name_ar,v.name_en,v.area_type,v.description_ar,v.sort_order
from public.cities c
join public.governorates g on g.id=c.governorate_id and g.code='baghdad'
cross join (values
 ('al-shorja','الشورجة','Al-Shorja','wholesale_market','منطقة أسواق الجملة والتجارة المركزية',1),
 ('jameela-market','سوق جميلة','Jameela Market','wholesale_market','منطقة تجارة الجملة والمواد الغذائية',2),
 ('bab-al-sharqi','باب الشرقي','Bab Al-Sharqi','commercial_district','منطقة تجارية مركزية',3),
 ('alawi-market','سوق العلاوي','Alawi Market','wholesale_market','أسواق ومخازن وتجارة متنوعة',4),
 ('saffafeer-market','سوق الصفافير','Copper Market','retail_market','سوق حرفي وتراثي متخصص',5),
 ('karrada-commercial','الكرادة التجارية','Karrada Commercial','commercial_district','منطقة تجارية وخدمية',6),
 ('mansour-commercial','المنصور التجارية','Mansour Commercial','commercial_district','منطقة تجارية وخدمية',7),
 ('arasat-commercial','عرصات الهندية','Arasat Al-Hindiya','commercial_district','منطقة تجارية وخدمية',8),
 ('zayouna-commercial','زيونة التجارية','Zayouna Commercial','commercial_district','منطقة تجارية وخدمية',9)
) as v(code,name_ar,name_en,area_type,description_ar,sort_order)
on conflict(code) do update set
 name_ar=excluded.name_ar,name_en=excluded.name_en,area_type=excluded.area_type,
 description_ar=excluded.description_ar,is_active=true,sort_order=excluded.sort_order;

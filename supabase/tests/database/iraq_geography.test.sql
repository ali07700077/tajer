-- Iraqi geography hierarchy and commercial-area directory authorization.
begin;
create extension if not exists pgtap with schema extensions;
select plan(10);

select is(
  (select count(*)::bigint from public.governorates where is_active),
  19::bigint,
  'the platform keeps all 19 currently recognized Iraqi governorates active'
);
select is(
  (select count(distinct governorate_id)::bigint from public.cities where is_active),
  19::bigint,
  'every active governorate has at least one active city/administrative seat'
);
select ok(
  to_regclass('public.districts') is not null
  and to_regclass('public.neighborhoods') is not null
  and to_regclass('public.commercial_areas') is not null,
  'district, neighborhood and commercial-area hierarchy exists'
);
select is(
  (select count(*)::bigint from public.commercial_areas where is_active and city_id=(
    select c.id from public.cities c join public.governorates g on g.id=c.governorate_id
    where g.code='baghdad' and c.name_ar='بغداد'
  )),
  9::bigint,
  'the initial Baghdad commercial directory contains nine named market and business areas'
);
select ok(
  (select relrowsecurity from pg_class where oid='public.districts'::regclass)
  and (select relrowsecurity from pg_class where oid='public.neighborhoods'::regclass)
  and (select relrowsecurity from pg_class where oid='public.commercial_areas'::regclass),
  'all new geographic reference tables enforce row-level security'
);
select ok(
  has_table_privilege('anon','public.commercial_areas','SELECT')
  and has_table_privilege('authenticated','public.commercial_areas','SELECT')
  and not has_table_privilege('anon','public.commercial_areas','INSERT')
  and not has_table_privilege('authenticated','public.commercial_areas','INSERT'),
  'reference directories are publicly readable but browser writes are denied'
);
select ok(
  exists(select 1 from information_schema.columns
    where table_schema='public' and table_name='businesses' and column_name='commercial_area_id'),
  'business profiles can optionally reference a structured commercial area'
);
select ok(
  exists(select 1 from information_schema.columns
    where table_schema='public' and table_name='neighborhoods' and column_name='latitude'
      and data_type='numeric')
  and exists(select 1 from information_schema.columns
    where table_schema='public' and table_name='neighborhoods' and column_name='longitude'
      and data_type='numeric'),
  'neighborhoods support validated coordinates for future map and delivery workflows'
);

insert into public.districts(city_id,code,name_ar)
select c.id,'rls-geo-test','منطقة اختبار جغرافية'
from public.cities c join public.governorates g on g.id=c.governorate_id
where g.code='baghdad' and c.name_ar='بغداد'
on conflict(city_id,code) do nothing;
select throws_ok(
  $$insert into public.commercial_areas(city_id,district_id,code,name_ar,area_type)
    values(
      (select c.id from public.cities c join public.governorates g on g.id=c.governorate_id where g.code='basra' limit 1),
      (select d.id from public.districts d join public.cities c on c.id=d.city_id join public.governorates g on g.id=c.governorate_id where g.code='baghdad' and d.code='rls-geo-test'),
      'invalid-cross-city-test','اختبار ربط غير صحيح','commercial_district'
    )$$,
  '23514',
  'district does not belong to selected city',
  'a commercial area cannot reference a district from another city'
);
select ok(
  exists(select 1 from pg_trigger where tgrelid='public.commercial_areas'::regclass
    and tgname='commercial_areas_validate_geography' and not tgisinternal),
  'commercial area hierarchy is validated on every insert and update'
);

select * from finish();
rollback;

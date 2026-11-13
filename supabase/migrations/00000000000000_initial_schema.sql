-- TAJER foundational schema. Safe for clean local rebuilds; never run against production.
-- audit_logs is deliberately non-destructive and append-only.
create extension if not exists pgcrypto with schema extensions;

do $$ begin create type public.account_status as enum ('active','suspended'); exception when duplicate_object then null; end $$;
do $$ begin create type public.business_type as enum ('buyer','supplier'); exception when duplicate_object then null; end $$;
do $$ begin create type public.member_role as enum ('owner','manager','staff'); exception when duplicate_object then null; end $$;
do $$ begin create type public.verification_status as enum ('draft','submitted','under_review','approved','rejected','suspended'); exception when duplicate_object then null; end $$;

create table if not exists public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 full_name text check (full_name is null or char_length(full_name)<=120),
 phone text check (phone is null or phone ~ '^[0-9+ ()-]{6,20}$'),
 status public.account_status not null default 'active',
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create table if not exists public.governorates (
 id uuid primary key default gen_random_uuid(), code text not null unique check(code ~ '^[a-z][a-z0-9-]*$'),
 name_ar text not null, name_en text, is_active boolean not null default false,
 sort_order integer not null default 0, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.cities (
 id uuid primary key default gen_random_uuid(), governorate_id uuid not null references public.governorates(id) on delete restrict,
 name_ar text not null, name_en text, is_active boolean not null default true, sort_order integer not null default 0,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(governorate_id,name_ar)
);
create table if not exists public.businesses (
 id uuid primary key default gen_random_uuid(), business_type public.business_type not null, name_ar text not null check(char_length(trim(name_ar)) between 2 and 160),
 name_en text check(name_en is null or char_length(name_en)<=160), legal_name text, commercial_registration_no text, tax_id text,
 governorate_id uuid not null references public.governorates(id) on delete restrict,
 city_id uuid references public.cities(id) on delete restrict, address_text text,
 phone text check(phone is null or phone ~ '^[0-9+ ()-]{6,20}$'), email text, description_ar text, logo_path text,
 verification_status public.verification_status not null default 'draft', verification_reason text,
 reviewed_by uuid references public.profiles(id) on delete set null, reviewed_at timestamptz,
 is_active boolean not null default true, created_by uuid references public.profiles(id) on delete set null,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.business_members (
 business_id uuid not null references public.businesses(id) on delete cascade,
 user_id uuid not null references public.profiles(id) on delete cascade,
 member_role public.member_role not null default 'staff', created_at timestamptz not null default now(),
 primary key(business_id,user_id)
);
create table if not exists public.categories (
 id uuid primary key default gen_random_uuid(), parent_id uuid references public.categories(id) on delete restrict,
 slug text not null unique check(slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
 name_ar text not null, name_en text, description_ar text, icon text, image_path text,
 sort_order integer not null default 0, is_active boolean not null default true,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 check(parent_id is null or parent_id<>id)
);
create table if not exists public.products (
 id uuid primary key default gen_random_uuid(), business_id uuid not null references public.businesses(id) on delete cascade,
 category_id uuid references public.categories(id), name text not null, description text, sku text,
 price numeric(14,2) not null default 0 check(price>=0), min_order_quantity integer not null default 1 check(min_order_quantity>0),
 stock_quantity integer not null default 0 check(stock_quantity>=0), is_active boolean not null default true,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(), image_path text
);
create table if not exists public.product_price_tiers (
 id uuid primary key default gen_random_uuid(), product_id uuid not null references public.products(id) on delete cascade,
 min_quantity integer not null check(min_quantity>0), unit_price numeric(14,2) not null check(unit_price>=0),
 created_at timestamptz not null default now(), unique(product_id,min_quantity)
);
create table if not exists public.rfqs (
 id uuid primary key default gen_random_uuid(), buyer_business_id uuid not null references public.businesses(id),
 title text not null, description text, status text not null default 'open' check(status in ('open','responded','closed','awarded','cancelled')),
 delivery_governorate_id uuid references public.governorates(id), delivery_city_id uuid references public.cities(id),
 deadline timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now(), awarded_offer_id uuid
);
create table if not exists public.rfq_items (
 id uuid primary key default gen_random_uuid(), rfq_id uuid not null references public.rfqs(id) on delete cascade,
 product_id uuid not null references public.products(id) on delete restrict,
 supplier_business_id uuid not null references public.businesses(id) on delete restrict,
 quantity integer not null check(quantity>0), created_at timestamptz not null default now(), unique(rfq_id,product_id)
);
create table if not exists public.rfq_offers (
 id uuid primary key default gen_random_uuid(), rfq_id uuid not null references public.rfqs(id) on delete cascade,
 supplier_business_id uuid not null references public.businesses(id), unit_price numeric(14,2) not null check(unit_price>0),
 quantity numeric(14,2) not null check(quantity>0), currency text not null default 'IQD', delivery_days integer check(delivery_days>=0),
 notes text, status text not null default 'submitted' check(status in ('submitted','accepted','rejected','withdrawn')),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(), total_price numeric(14,2),
 constraint rfq_offers_total_price_positive check(total_price is null or total_price>0) not valid,
 unique(rfq_id,supplier_business_id)
);
create table if not exists public.orders (
 id uuid primary key default gen_random_uuid(), buyer_business_id uuid not null references public.businesses(id),
 supplier_business_id uuid not null references public.businesses(id), rfq_id uuid references public.rfqs(id),
 status text not null default 'pending' check(status in ('pending','confirmed','processing','shipped','delivered','cancelled')),
 total_amount numeric(14,2) not null default 0 check(total_amount>=0), currency text not null default 'IQD',
 delivery_address text, notes text, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.order_items (
 id uuid primary key default gen_random_uuid(), order_id uuid not null references public.orders(id) on delete cascade,
 product_id uuid not null references public.products(id), product_name text not null,
 quantity numeric(14,2) not null check(quantity>0), unit_price numeric(14,2) not null check(unit_price>=0),
 line_total numeric(14,2) generated always as(quantity*unit_price) stored, created_at timestamptz not null default now()
);
create table if not exists public.roles (
 id uuid primary key default gen_random_uuid(), key text not null unique check(key ~ '^[a-z][a-z0-9_]*$'),
 name_ar text not null, description_ar text, is_system boolean not null default false, created_at timestamptz not null default now()
);
create table if not exists public.permissions (
 key text primary key check(key ~ '^[a-z][a-z0-9_]*\\.[a-z][a-z0-9_]*$'), name_ar text not null, group_key text not null
);
create table if not exists public.role_permissions (
 role_id uuid not null references public.roles(id) on delete cascade,
 permission_key text not null references public.permissions(key) on delete cascade, primary key(role_id,permission_key)
);
create table if not exists public.staff_roles (
 user_id uuid not null references public.profiles(id) on delete cascade,
 role_id uuid not null references public.roles(id) on delete cascade,
 granted_by uuid references public.profiles(id) on delete set null, created_at timestamptz not null default now(),
 primary key(user_id,role_id)
);
create table if not exists public.audit_logs (
 id uuid primary key default gen_random_uuid(), actor_id uuid, action text not null, entity_type text, entity_id uuid,
 reason text, metadata jsonb not null default '{}'::jsonb, created_at timestamptz not null default now()
);

create index if not exists business_members_user_idx on public.business_members(user_id);
create index if not exists businesses_governorate_idx on public.businesses(governorate_id);
create index if not exists businesses_type_status_idx on public.businesses(business_type,verification_status);
create index if not exists categories_parent_idx on public.categories(parent_id);
create index if not exists cities_governorate_idx on public.cities(governorate_id);
create index if not exists products_business_id_idx on public.products(business_id);
create index if not exists products_category_id_idx on public.products(category_id);
create index if not exists product_price_tiers_product_idx on public.product_price_tiers(product_id);
create index if not exists rfqs_buyer_business_idx on public.rfqs(buyer_business_id);
create index if not exists rfqs_buyer_created_idx on public.rfqs(buyer_business_id,created_at desc);
create index if not exists rfqs_status_idx on public.rfqs(status);
create index if not exists rfq_items_supplier_idx on public.rfq_items(supplier_business_id,created_at desc);
create index if not exists rfq_items_product_idx on public.rfq_items(product_id);
create index if not exists rfq_offers_rfq_id_idx on public.rfq_offers(rfq_id);
create index if not exists rfq_offers_supplier_id_idx on public.rfq_offers(supplier_business_id);
create index if not exists rfq_offers_rfq_idx on public.rfq_offers(rfq_id,created_at desc);
create index if not exists orders_buyer_idx on public.orders(buyer_business_id);
create index if not exists orders_supplier_idx on public.orders(supplier_business_id);
create index if not exists order_items_order_idx on public.order_items(order_id);
create index if not exists staff_roles_role_idx on public.staff_roles(role_id);
create index if not exists audit_logs_actor_idx on public.audit_logs(actor_id);
create index if not exists audit_logs_created_idx on public.audit_logs(created_at desc);
create index if not exists audit_logs_entity_idx on public.audit_logs(entity_type,entity_id);

create or replace function public.has_business_role(p_business_id uuid,p_roles public.member_role[])
returns boolean language sql stable security definer set search_path=''
as $$ select exists(select 1 from public.business_members m where m.business_id=p_business_id and m.user_id=auth.uid() and m.member_role=any(p_roles)); $$;
create or replace function public.is_business_member(p_business_id uuid)
returns boolean language sql stable security definer set search_path=''
as $$ select exists(select 1 from public.business_members m where m.business_id=p_business_id and m.user_id=auth.uid()); $$;
create or replace function public.has_permission(p_key text)
returns boolean language sql stable security definer set search_path=''
as $$ select exists(select 1 from public.staff_roles sr join public.roles r on r.id=sr.role_id where sr.user_id=auth.uid() and r.key='super_admin')
or exists(select 1 from public.staff_roles sr join public.role_permissions rp on rp.role_id=sr.role_id where sr.user_id=auth.uid() and rp.permission_key=p_key); $$;
create or replace function public.set_updated_at()
returns trigger language plpgsql set search_path='' as $$ begin new.updated_at=now(); return new; end $$;
create or replace function public.businesses_validate_city()
returns trigger language plpgsql set search_path='' as $$ begin
 if new.city_id is not null and not exists(select 1 from public.cities c where c.id=new.city_id and c.governorate_id=new.governorate_id) then
 raise exception 'city does not belong to the selected governorate' using errcode='23514'; end if; return new; end $$;
create or replace function public.categories_prevent_cycle()
returns trigger language plpgsql set search_path='' as $$ begin
 if new.parent_id is null then return new; end if;
 if exists(with recursive ancestors as (select c.id,c.parent_id from public.categories c where c.id=new.parent_id union all select c.id,c.parent_id from public.categories c join ancestors a on c.id=a.parent_id) select 1 from ancestors where id=new.id) then
 raise exception 'category hierarchy cannot contain a cycle' using errcode='23514'; end if; return new; end $$;
create or replace function public.audit_logs_block_changes()
returns trigger language plpgsql set search_path='' as $$ begin raise exception 'audit_logs is append-only'; end $$;

do $$ declare t text; begin
 foreach t in array array['profiles','governorates','cities','businesses','business_members','categories','products','product_price_tiers','rfqs','rfq_items','rfq_offers','orders','order_items','roles','permissions','role_permissions','staff_roles','audit_logs'] loop
 execute format('alter table public.%I enable row level security',t);
 end loop;
end $$;

create trigger audit_logs_no_update_delete before update or delete on public.audit_logs for each row execute function public.audit_logs_block_changes();
create trigger audit_logs_no_truncate before truncate on public.audit_logs for each statement execute function public.audit_logs_block_changes();
create trigger businesses_set_updated_at before update on public.businesses for each row execute function public.set_updated_at();
create trigger businesses_validate_city before insert or update of city_id,governorate_id on public.businesses for each row execute function public.businesses_validate_city();
create trigger categories_set_updated_at before update on public.categories for each row execute function public.set_updated_at();
create trigger categories_prevent_cycle before insert or update of parent_id on public.categories for each row execute function public.categories_prevent_cycle();
create trigger profiles_set_updated_at before update on public.profiles for each row execute function public.set_updated_at();
create trigger cities_set_updated_at before update on public.cities for each row execute function public.set_updated_at();
create trigger governorates_set_updated_at before update on public.governorates for each row execute function public.set_updated_at();

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path=''
as $$ begin
 insert into public.profiles(id,full_name,phone) values(new.id,nullif(left(new.raw_user_meta_data->>'full_name',120),''),nullif(left(new.raw_user_meta_data->>'phone',30),''));
 return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

revoke all on function public.has_business_role(uuid,public.member_role[]) from public,anon;
revoke all on function public.is_business_member(uuid) from public,anon;
revoke all on function public.has_permission(text) from public,anon;
grant execute on function public.has_business_role(uuid,public.member_role[]) to authenticated;
grant execute on function public.is_business_member(uuid) to authenticated;
grant execute on function public.has_permission(text) to authenticated;

-- Enforce wholesale tier pricing and MOQ invariants under concurrent writes.
-- A product row lock serializes all tier changes for that product.
create index if not exists product_price_tiers_product_quantity_idx
  on public.product_price_tiers (product_id, min_quantity);

alter table public.product_price_tiers
  add constraint product_price_tiers_unit_price_positive
  check (unit_price > 0) not valid;

create or replace function public.validate_product_price_tier()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  product_row public.products%rowtype;
begin
  select * into product_row
  from public.products
  where id = new.product_id
  for update;

  if not found then
    raise exception 'المنتج غير موجود';
  end if;
  if new.min_quantity < product_row.min_order_quantity then
    raise exception 'كمية شريحة السعر أقل من الحد الأدنى للطلب';
  end if;
  if new.unit_price <= 0 or new.unit_price > product_row.price then
    raise exception 'سعر شريحة الجملة يجب أن يكون أكبر من صفر ولا يتجاوز سعر الجملة الأساسي';
  end if;
  if exists (
    select 1
    from public.product_price_tiers tier
    where tier.product_id = new.product_id
      and tier.id is distinct from new.id
      and (
        (tier.min_quantity < new.min_quantity and tier.unit_price < new.unit_price)
        or
        (tier.min_quantity > new.min_quantity and tier.unit_price > new.unit_price)
      )
  ) then
    raise exception 'يجب ألا يرتفع سعر الوحدة مع زيادة كمية الجملة';
  end if;
  return new;
end;
$$;

drop trigger if exists product_price_tiers_validate on public.product_price_tiers;
create trigger product_price_tiers_validate
before insert or update of product_id, min_quantity, unit_price
on public.product_price_tiers
for each row execute function public.validate_product_price_tier();

create or replace function public.validate_product_wholesale_pricing_update()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.min_order_quantity is distinct from old.min_order_quantity
     or new.price is distinct from old.price then
    if exists (
      select 1 from public.product_price_tiers tier
      where tier.product_id = old.id
        and tier.min_quantity < new.min_order_quantity
    ) then
      raise exception 'تغيير الحد الأدنى سيجعل شرائح الأسعار الحالية غير صالحة'
        using errcode = 'P0001';
    end if;
    if exists (
      select 1 from public.product_price_tiers tier
      where tier.product_id = old.id and tier.unit_price > new.price
    ) then
      raise exception 'تغيير سعر الجملة الأساسي سيجعل شرائح الأسعار الحالية غير صالحة'
        using errcode = 'P0001';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists products_validate_wholesale_pricing on public.products;
create trigger products_validate_wholesale_pricing
before update of min_order_quantity, price
on public.products
for each row execute function public.validate_product_wholesale_pricing_update();

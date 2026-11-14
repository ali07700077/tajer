-- Enforce wholesale tier boundaries at the database layer, not only in the UI.
create index if not exists product_price_tiers_product_quantity_idx
  on public.product_price_tiers (product_id, min_quantity);

create or replace function public.validate_product_price_tier()
returns trigger
language plpgsql
set search_path = public
as $$
declare product_row public.products%rowtype;
begin
  select * into product_row from public.products where id = new.product_id;
  if not found then raise exception 'المنتج غير موجود'; end if;
  if new.min_quantity < product_row.min_order_quantity then
    raise exception 'كمية شريحة السعر أقل من الحد الأدنى للطلب';
  end if;
  if new.unit_price > product_row.price then
    raise exception 'سعر شريحة الجملة يجب ألا يتجاوز سعر الجملة الأساسي';
  end if;
  return new;
end;
$$;

drop trigger if exists product_price_tiers_validate on public.product_price_tiers;
create trigger product_price_tiers_validate
before insert or update of product_id, min_quantity, unit_price
on public.product_price_tiers
for each row execute function public.validate_product_price_tier();

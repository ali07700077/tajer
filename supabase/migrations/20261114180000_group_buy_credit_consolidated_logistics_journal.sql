-- Commercial finance and fulfillment foundation for TAJER.
-- Inspired by public workflows documented by Alibaba Trade Assurance, Amazon Business
-- quantity pricing, and Faire approved net terms. This migration does not connect
-- external payment, lending, or carrier providers.

alter table public.escrow_ledger_entries
  alter column amount type numeric(19,4) using amount::numeric(19,4);

create table public.group_buy_campaigns (
  id uuid primary key default extensions.gen_random_uuid(),
  supplier_business_id uuid not null references public.businesses(id) on delete restrict,
  product_id uuid not null references public.products(id) on delete restrict,
  title_ar text not null check (char_length(trim(title_ar)) between 3 and 180),
  target_quantity integer not null check (target_quantity > 1),
  max_quantity integer not null check (max_quantity >= target_quantity),
  committed_quantity integer not null default 0 check (committed_quantity >= 0 and committed_quantity <= max_quantity),
  unit_price numeric(19,4) not null check (unit_price > 0),
  currency text not null default 'IQD' check (currency = 'IQD'),
  status text not null default 'open' check (status in ('open','target_met','expired','cancelled','converted')),
  starts_at timestamptz not null default now(),
  ends_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at > starts_at),
  check (committed_quantity <= max_quantity)
);
create index group_buy_campaigns_status_ends_idx on public.group_buy_campaigns(status,ends_at) where status='open';
create index group_buy_campaigns_supplier_created_idx on public.group_buy_campaigns(supplier_business_id,created_at desc);
create index group_buy_campaigns_product_status_idx on public.group_buy_campaigns(product_id,status);

create table public.group_buy_participants (
  id uuid primary key default extensions.gen_random_uuid(),
  campaign_id uuid not null references public.group_buy_campaigns(id) on delete restrict,
  buyer_business_id uuid not null references public.businesses(id) on delete restrict,
  joined_by uuid not null references public.profiles(id) on delete restrict,
  quantity integer not null check (quantity > 0),
  status text not null default 'committed' check (status in ('committed','withdrawn','converted')),
  idempotency_key text not null check (char_length(trim(idempotency_key)) >= 8),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(campaign_id,buyer_business_id),
  unique(campaign_id,idempotency_key)
);
create index group_buy_participants_buyer_idx on public.group_buy_participants(buyer_business_id,created_at desc);

create or replace function public.join_group_buy(
  p_campaign_id uuid, p_buyer_business_id uuid, p_quantity integer, p_idempotency_key text
) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_campaign public.group_buy_campaigns%rowtype; v_id uuid;
begin
  if auth.uid() is null then raise exception 'يجب تسجيل الدخول' using errcode='28000'; end if;
  if p_quantity is null or p_quantity<1 or char_length(trim(coalesce(p_idempotency_key,'')))<8 then
    raise exception 'بيانات المشاركة غير صالحة' using errcode='22023';
  end if;
  if not public.has_business_role(p_buyer_business_id,array['owner'::public.member_role,'manager'::public.member_role]) then
    raise exception 'لا تملك صلاحية الشراء باسم الشركة' using errcode='42501';
  end if;
  select * into v_campaign from public.group_buy_campaigns where id=p_campaign_id for update;
  if not found or v_campaign.status<>'open' or v_campaign.starts_at>now() or v_campaign.ends_at<=now() then
    raise exception 'حملة الشراء الجماعي غير متاحة' using errcode='55000';
  end if;
  if not exists(select 1 from public.businesses where id=p_buyer_business_id and business_type='buyer'::public.business_type and is_active) then
    raise exception 'ملف شركة المشتري غير صالح' using errcode='22023';
  end if;
  if v_campaign.committed_quantity+p_quantity>v_campaign.max_quantity then
    raise exception 'الكمية تتجاوز المتبقي في حملة الشراء الجماعي' using errcode='23514';
  end if;
  insert into public.group_buy_participants(campaign_id,buyer_business_id,joined_by,quantity,idempotency_key)
  values(p_campaign_id,p_buyer_business_id,auth.uid(),p_quantity,trim(p_idempotency_key))
  on conflict(campaign_id,idempotency_key) do nothing
  returning id into v_id;
  if v_id is null then
    select id into v_id from public.group_buy_participants
    where campaign_id=p_campaign_id and idempotency_key=trim(p_idempotency_key);
    return v_id;
  end if;
  update public.group_buy_campaigns
  set committed_quantity=committed_quantity+p_quantity,
      status=case when committed_quantity+p_quantity>=target_quantity then 'target_met' else 'open' end,
      updated_at=now()
  where id=p_campaign_id;
  return v_id;
end;
$$;

create table public.b2b_credit_accounts (
  id uuid primary key default extensions.gen_random_uuid(),
  buyer_business_id uuid not null unique references public.businesses(id) on delete restrict,
  credit_limit numeric(19,4) not null default 0 check (credit_limit>=0),
  outstanding_balance numeric(19,4) not null default 0 check (outstanding_balance>=0 and outstanding_balance<=credit_limit),
  currency text not null default 'IQD' check (currency='IQD'),
  status text not null default 'pending' check (status in ('pending','approved','suspended','closed')),
  payment_term_days integer not null default 0 check (payment_term_days between 0 and 120),
  approved_by uuid references public.profiles(id) on delete restrict,
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((status='approved' and approved_by is not null and approved_at is not null) or status<>'approved')
);
create index b2b_credit_accounts_status_idx on public.b2b_credit_accounts(status,updated_at desc);

create table public.b2b_credit_transactions (
  id uuid primary key default extensions.gen_random_uuid(),
  credit_account_id uuid not null references public.b2b_credit_accounts(id) on delete restrict,
  order_id uuid references public.orders(id) on delete restrict,
  transaction_type text not null check (transaction_type in ('drawdown','repayment','adjustment','reversal')),
  amount numeric(19,4) not null check (amount>0),
  currency text not null default 'IQD' check (currency='IQD'),
  idempotency_key text not null check (char_length(trim(idempotency_key))>=8),
  due_at timestamptz,
  reference text,
  metadata jsonb not null default '{}'::jsonb,
  actor_id uuid references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique(credit_account_id,idempotency_key)
);
create index b2b_credit_transactions_account_created_idx on public.b2b_credit_transactions(credit_account_id,created_at desc);
create index b2b_credit_transactions_due_idx on public.b2b_credit_transactions(due_at) where transaction_type='drawdown';

create table public.financial_journal_transactions (
  id uuid primary key default extensions.gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete restrict,
  event_type text not null check (event_type in ('payment_capture','supplier_release','buyer_refund','supplier_payout','manual_reversal')),
  amount numeric(19,4) not null check (amount>0),
  currency text not null default 'IQD' check (currency='IQD'),
  idempotency_key text not null check (char_length(trim(idempotency_key))>=8),
  provider_reference text,
  metadata jsonb not null default '{}'::jsonb,
  actor_id uuid references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique(order_id,idempotency_key)
);
create index financial_journal_order_created_idx on public.financial_journal_transactions(order_id,created_at desc);

create table public.financial_journal_lines (
  id uuid primary key default extensions.gen_random_uuid(),
  journal_transaction_id uuid not null references public.financial_journal_transactions(id) on delete restrict,
  account_code text not null check (account_code in ('processor_clearing','escrow_liability','supplier_payable','buyer_refund_payable','bank_clearing')),
  debit numeric(19,4) not null default 0 check (debit>=0),
  credit numeric(19,4) not null default 0 check (credit>=0),
  currency text not null default 'IQD' check (currency='IQD'),
  created_at timestamptz not null default now(),
  check ((debit>0 and credit=0) or (credit>0 and debit=0))
);
create index financial_journal_lines_transaction_idx on public.financial_journal_lines(journal_transaction_id);
create index financial_journal_lines_account_created_idx on public.financial_journal_lines(account_code,created_at desc);

create or replace function public.enforce_balanced_financial_journal()
returns trigger language plpgsql set search_path='' as $$
declare v_id uuid; v_debit numeric(19,4); v_credit numeric(19,4); v_count integer;
begin
  v_id:=coalesce(new.journal_transaction_id,old.journal_transaction_id);
  select coalesce(sum(debit),0),coalesce(sum(credit),0),count(*)
  into v_debit,v_credit,v_count
  from public.financial_journal_lines where journal_transaction_id=v_id;
  if v_count<2 or v_debit<>v_credit then
    raise exception 'القيد المحاسبي غير متوازن' using errcode='23514';
  end if;
  return null;
end;
$$;
create constraint trigger financial_journal_balanced
after insert or update or delete on public.financial_journal_lines
deferrable initially deferred for each row execute function public.enforce_balanced_financial_journal();

create or replace function public.reject_financial_journal_mutation()
returns trigger language plpgsql set search_path='' as $$
begin raise exception 'السجل المحاسبي غير قابل للتعديل أو الحذف؛ استخدم قيداً عكسياً' using errcode='55000'; end;
$$;
create trigger financial_journal_transactions_immutable before update or delete on public.financial_journal_transactions
for each row execute function public.reject_financial_journal_mutation();
create trigger financial_journal_lines_immutable before update or delete on public.financial_journal_lines
for each row execute function public.reject_financial_journal_mutation();

create or replace function public.post_order_escrow_journal(
  p_order_id uuid, p_event_type text, p_amount numeric, p_idempotency_key text,
  p_provider_reference text default null, p_metadata jsonb default '{}'::jsonb
) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_journal_id uuid; v_debit_account text; v_credit_account text;
begin
  if auth.role()<>'service_role' then raise exception 'service role required' using errcode='42501'; end if;
  if p_amount is null or p_amount<=0 or char_length(trim(coalesce(p_idempotency_key,'')))<8 then
    raise exception 'بيانات القيد المالي غير صالحة' using errcode='22023';
  end if;
  perform 1 from public.orders where id=p_order_id for update;
  if not found then raise exception 'الطلب غير موجود' using errcode='22023'; end if;
  case p_event_type
    when 'payment_capture' then v_debit_account:='processor_clearing'; v_credit_account:='escrow_liability';
    when 'supplier_release' then v_debit_account:='escrow_liability'; v_credit_account:='supplier_payable';
    when 'buyer_refund' then v_debit_account:='escrow_liability'; v_credit_account:='buyer_refund_payable';
    when 'supplier_payout' then v_debit_account:='supplier_payable'; v_credit_account:='bank_clearing';
    when 'manual_reversal' then v_debit_account:='escrow_liability'; v_credit_account:='processor_clearing';
    else raise exception 'نوع الحركة المالية غير صالح' using errcode='22023';
  end case;
  insert into public.financial_journal_transactions(order_id,event_type,amount,idempotency_key,provider_reference,metadata,actor_id)
  values(p_order_id,p_event_type,p_amount,trim(p_idempotency_key),nullif(trim(coalesce(p_provider_reference,'')),''),coalesce(p_metadata,'{}'::jsonb),auth.uid())
  on conflict(order_id,idempotency_key) do nothing
  returning id into v_journal_id;
  if v_journal_id is null then
    select id into v_journal_id from public.financial_journal_transactions
    where order_id=p_order_id and idempotency_key=trim(p_idempotency_key);
    return v_journal_id;
  end if;
  insert into public.financial_journal_lines(journal_transaction_id,account_code,debit,credit)
  values
    (v_journal_id,v_debit_account,p_amount,0),
    (v_journal_id,v_credit_account,0,p_amount);
  return v_journal_id;
end;
$$;

create table public.consolidated_shipments (
  id uuid primary key default extensions.gen_random_uuid(),
  buyer_business_id uuid not null references public.businesses(id) on delete restrict,
  shipment_reference text not null unique,
  carrier_name text,
  tracking_reference text,
  status text not null default 'planning' check (status in ('planning','collecting','dispatched','in_transit','delivered','exception','cancelled')),
  origin_governorate_id uuid references public.governorates(id) on delete restrict,
  destination_governorate_id uuid not null references public.governorates(id) on delete restrict,
  delivery_address text not null check (char_length(trim(delivery_address))>=8),
  shipping_cost numeric(19,4) not null default 0 check (shipping_cost>=0),
  currency text not null default 'IQD' check (currency='IQD'),
  estimated_delivery_at timestamptz,
  dispatched_at timestamptz,
  delivered_at timestamptz,
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index consolidated_shipments_buyer_status_idx on public.consolidated_shipments(buyer_business_id,status,created_at desc);
create index consolidated_shipments_tracking_idx on public.consolidated_shipments(tracking_reference) where tracking_reference is not null;

create table public.consolidated_shipment_orders (
  shipment_id uuid not null references public.consolidated_shipments(id) on delete restrict,
  order_id uuid not null unique references public.orders(id) on delete restrict,
  supplier_business_id uuid not null references public.businesses(id) on delete restrict,
  package_count integer not null default 1 check (package_count>0),
  declared_value numeric(19,4) not null default 0 check (declared_value>=0),
  created_at timestamptz not null default now(),
  primary key(shipment_id,order_id)
);
create index consolidated_shipment_orders_supplier_idx on public.consolidated_shipment_orders(supplier_business_id,created_at desc);

create or replace function public.set_commercial_updated_at()
returns trigger language plpgsql set search_path='' as $$ begin new.updated_at=now(); return new; end $$;
create trigger group_buy_campaigns_updated_at before update on public.group_buy_campaigns for each row execute function public.set_commercial_updated_at();
create trigger group_buy_participants_updated_at before update on public.group_buy_participants for each row execute function public.set_commercial_updated_at();
create trigger b2b_credit_accounts_updated_at before update on public.b2b_credit_accounts for each row execute function public.set_commercial_updated_at();
create trigger consolidated_shipments_updated_at before update on public.consolidated_shipments for each row execute function public.set_commercial_updated_at();

alter table public.group_buy_campaigns enable row level security;
alter table public.group_buy_participants enable row level security;
alter table public.b2b_credit_accounts enable row level security;
alter table public.b2b_credit_transactions enable row level security;
alter table public.financial_journal_transactions enable row level security;
alter table public.financial_journal_lines enable row level security;
alter table public.consolidated_shipments enable row level security;
alter table public.consolidated_shipment_orders enable row level security;

revoke all on public.group_buy_campaigns,public.group_buy_participants,public.b2b_credit_accounts,
 public.b2b_credit_transactions,public.financial_journal_transactions,public.financial_journal_lines,
 public.consolidated_shipments,public.consolidated_shipment_orders from anon,authenticated;
grant select on public.group_buy_campaigns,public.group_buy_participants,public.b2b_credit_accounts,
 public.b2b_credit_transactions,public.financial_journal_transactions,public.financial_journal_lines,
 public.consolidated_shipments,public.consolidated_shipment_orders to authenticated;

create policy group_buy_campaigns_public_read on public.group_buy_campaigns for select to authenticated
using (status in ('open','target_met') or public.has_business_role(supplier_business_id,array['owner'::public.member_role,'manager'::public.member_role]));
create policy group_buy_participants_party_read on public.group_buy_participants for select to authenticated
using (
 public.has_business_role(buyer_business_id,array['owner'::public.member_role,'manager'::public.member_role])
 or exists(select 1 from public.group_buy_campaigns c where c.id=campaign_id and public.has_business_role(c.supplier_business_id,array['owner'::public.member_role,'manager'::public.member_role]))
);
create policy b2b_credit_accounts_business_read on public.b2b_credit_accounts for select to authenticated
using (public.has_business_role(buyer_business_id,array['owner'::public.member_role,'manager'::public.member_role]));
create policy b2b_credit_transactions_business_read on public.b2b_credit_transactions for select to authenticated
using (exists(select 1 from public.b2b_credit_accounts a where a.id=credit_account_id and public.has_business_role(a.buyer_business_id,array['owner'::public.member_role,'manager'::public.member_role])));
create policy financial_journal_transactions_party_read on public.financial_journal_transactions for select to authenticated
using (exists(select 1 from public.orders o where o.id=order_id and (
 o.buyer_user_id=(select auth.uid())
 or public.has_business_role(o.buyer_business_id,array['owner'::public.member_role,'manager'::public.member_role])
 or public.has_business_role(o.supplier_business_id,array['owner'::public.member_role,'manager'::public.member_role])
)));
create policy financial_journal_lines_party_read on public.financial_journal_lines for select to authenticated
using (exists(select 1 from public.financial_journal_transactions j join public.orders o on o.id=j.order_id
 where j.id=journal_transaction_id and (
 o.buyer_user_id=(select auth.uid())
 or public.has_business_role(o.buyer_business_id,array['owner'::public.member_role,'manager'::public.member_role])
 or public.has_business_role(o.supplier_business_id,array['owner'::public.member_role,'manager'::public.member_role])
)));
create policy consolidated_shipments_buyer_read on public.consolidated_shipments for select to authenticated
using (public.has_business_role(buyer_business_id,array['owner'::public.member_role,'manager'::public.member_role]));
create policy consolidated_shipment_orders_party_read on public.consolidated_shipment_orders for select to authenticated
using (
 public.has_business_role(supplier_business_id,array['owner'::public.member_role,'manager'::public.member_role])
 or exists(select 1 from public.consolidated_shipments s where s.id=shipment_id and public.has_business_role(s.buyer_business_id,array['owner'::public.member_role,'manager'::public.member_role]))
);

revoke all on function public.join_group_buy(uuid,uuid,integer,text) from public,anon;
grant execute on function public.join_group_buy(uuid,uuid,integer,text) to authenticated;
revoke all on function public.post_order_escrow_journal(uuid,text,numeric,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.post_order_escrow_journal(uuid,text,numeric,text,text,jsonb) to service_role;


-- Append-only audit trail for every stateful commercial, credit, journal and shipment event.
create or replace function public.audit_commercial_change()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_row jsonb; v_entity_id uuid; v_action text;
begin
  v_action:=tg_op;
  v_row:=case when tg_op='DELETE' then to_jsonb(old) else to_jsonb(new) end;
  v_entity_id:=coalesce(
    nullif(v_row->>'id','')::uuid,
    nullif(v_row->>'shipment_id','')::uuid,
    nullif(v_row->>'order_id','')::uuid
  );
  insert into public.audit_logs(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),lower(v_action),tg_table_name,v_entity_id,jsonb_build_object('record',v_row));
  return case when tg_op='DELETE' then old else new end;
end;
$$;

create trigger group_buy_campaigns_audit after insert or update or delete on public.group_buy_campaigns
for each row execute function public.audit_commercial_change();
create trigger group_buy_participants_audit after insert or update or delete on public.group_buy_participants
for each row execute function public.audit_commercial_change();
create trigger b2b_credit_accounts_audit after insert or update or delete on public.b2b_credit_accounts
for each row execute function public.audit_commercial_change();
create trigger b2b_credit_transactions_audit after insert or update or delete on public.b2b_credit_transactions
for each row execute function public.audit_commercial_change();
create trigger financial_journal_transactions_audit after insert on public.financial_journal_transactions
for each row execute function public.audit_commercial_change();
create trigger consolidated_shipments_audit after insert or update or delete on public.consolidated_shipments
for each row execute function public.audit_commercial_change();
create trigger consolidated_shipment_orders_audit after insert or update or delete on public.consolidated_shipment_orders
for each row execute function public.audit_commercial_change();

revoke all on function public.audit_commercial_change() from public,anon,authenticated;

-- Normalize persisted monetary values and fractional quantities to the platform precision.
-- PostgreSQL cannot change a referenced column's type while an UPDATE OF trigger
-- names that column. Temporarily remove the guard and restore it immediately after
-- the type conversion; its function and validation logic remain unchanged.
drop trigger if exists products_validate_wholesale_pricing on public.products;
alter table public.products
  alter column price type numeric(19,4) using price::numeric(19,4),
  alter column retail_price type numeric(19,4) using retail_price::numeric(19,4),
  alter column sample_price type numeric(19,4) using sample_price::numeric(19,4);
create trigger products_validate_wholesale_pricing
before update of min_order_quantity, price
on public.products
for each row execute function public.validate_product_wholesale_pricing_update();
-- The tier-validation trigger references unit_price; remove it only during the type change.
drop trigger if exists product_price_tiers_validate on public.product_price_tiers;
alter table public.product_price_tiers
  alter column unit_price type numeric(19,4) using unit_price::numeric(19,4);
create trigger product_price_tiers_validate
before insert or update of product_id, min_quantity, unit_price
on public.product_price_tiers
for each row execute function public.validate_product_price_tier();
alter table public.rfq_offers
  alter column unit_price type numeric(19,4) using unit_price::numeric(19,4),
  alter column total_price type numeric(19,4) using total_price::numeric(19,4),
  alter column quantity type numeric(19,4) using quantity::numeric(19,4);
alter table public.orders
  alter column total_amount type numeric(19,4) using total_amount::numeric(19,4);
alter table public.order_items
  alter column quantity type numeric(19,4) using quantity::numeric(19,4),
  alter column unit_price type numeric(19,4) using unit_price::numeric(19,4);
alter table public.product_sample_requests
  alter column unit_price type numeric(19,4) using unit_price::numeric(19,4);
alter table public.proforma_invoices
  alter column subtotal type numeric(19,4) using subtotal::numeric(19,4);
alter table public.proforma_invoice_items
  alter column quantity type numeric(19,4) using quantity::numeric(19,4),
  alter column unit_price type numeric(19,4) using unit_price::numeric(19,4);


alter table public.order_items
  alter column line_total type numeric(19,4) using line_total::numeric(19,4);
alter table public.product_sample_requests
  alter column total_amount type numeric(19,4) using total_amount::numeric(19,4);
alter table public.proforma_invoice_items
  alter column line_total type numeric(19,4) using line_total::numeric(19,4);
alter table public.checkout_sessions
  alter column total_amount type numeric(19,4) using total_amount::numeric(19,4);

create trigger b2b_credit_transactions_immutable before update or delete on public.b2b_credit_transactions
for each row execute function public.reject_financial_journal_mutation();

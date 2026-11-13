-- TAJER buyer AI assistant persistence and supply agreements.
create table if not exists public.ai_conversations (
 id uuid primary key default gen_random_uuid(),
 buyer_business_id uuid not null references public.businesses(id) on delete cascade,
 created_by uuid not null references auth.users(id) on delete cascade,
 title text,
 status text not null default 'active' check(status in ('active','archived')),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create table if not exists public.ai_messages (
 id uuid primary key default gen_random_uuid(),
 conversation_id uuid not null references public.ai_conversations(id) on delete cascade,
 sender_role text not null check(sender_role in ('user','assistant','system')),
 content text not null check(char_length(content) between 1 and 20000),
 metadata jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now()
);
create index if not exists ai_conversations_buyer_created_idx on public.ai_conversations(buyer_business_id,created_at desc);
create index if not exists ai_messages_conversation_created_idx on public.ai_messages(conversation_id,created_at);
alter table public.ai_conversations enable row level security;
alter table public.ai_messages enable row level security;
drop policy if exists ai_conversations_member_read on public.ai_conversations;
create policy ai_conversations_member_read on public.ai_conversations for select to authenticated
using (public.has_business_role(buyer_business_id,array['owner'::public.member_role,'manager'::public.member_role,'staff'::public.member_role]));
drop policy if exists ai_conversations_member_insert on public.ai_conversations;
create policy ai_conversations_member_insert on public.ai_conversations for insert to authenticated
with check (created_by=auth.uid() and public.has_business_role(buyer_business_id,array['owner'::public.member_role,'manager'::public.member_role]));
drop policy if exists ai_conversations_member_update on public.ai_conversations;
create policy ai_conversations_member_update on public.ai_conversations for update to authenticated
using (created_by=auth.uid() and public.has_business_role(buyer_business_id,array['owner'::public.member_role,'manager'::public.member_role]))
with check (created_by=auth.uid() and public.has_business_role(buyer_business_id,array['owner'::public.member_role,'manager'::public.member_role]));
drop policy if exists ai_messages_member_read on public.ai_messages;
create policy ai_messages_member_read on public.ai_messages for select to authenticated
using (exists(select 1 from public.ai_conversations c where c.id=conversation_id and public.has_business_role(c.buyer_business_id,array['owner'::public.member_role,'manager'::public.member_role,'staff'::public.member_role])));
drop policy if exists ai_messages_member_insert on public.ai_messages;
create policy ai_messages_member_insert on public.ai_messages for insert to authenticated
with check (sender_role='user' and exists(select 1 from public.ai_conversations c where c.id=conversation_id and c.created_by=auth.uid() and public.has_business_role(c.buyer_business_id,array['owner'::public.member_role,'manager'::public.member_role])));

-- Contract records track commercial terms and in-app acceptance events.
-- This is an auditable workflow record, not a substitute for jurisdiction-specific legal e-signature.
create table if not exists public.supply_contracts (
 id uuid primary key default gen_random_uuid(),
 buyer_business_id uuid not null references public.businesses(id),
 supplier_business_id uuid not null references public.businesses(id),
 rfq_id uuid references public.rfqs(id),
 offer_id uuid references public.rfq_offers(id),
 title text not null,
 terms text not null,
 currency text not null default 'IQD' check(currency='IQD'),
 contract_value numeric(14,2) not null check(contract_value>0),
 starts_on date not null,
 ends_on date not null check(ends_on>=starts_on),
 status text not null default 'draft' check(status in ('draft','pending_supplier','active','completed','cancelled')),
 created_by uuid not null references auth.users(id),
 supplier_accepted_by uuid references auth.users(id),
 supplier_accepted_at timestamptz,
 buyer_accepted_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check(buyer_business_id<>supplier_business_id)
);
create index if not exists supply_contracts_buyer_idx on public.supply_contracts(buyer_business_id,created_at desc);
create index if not exists supply_contracts_supplier_idx on public.supply_contracts(supplier_business_id,created_at desc);
alter table public.supply_contracts enable row level security;
drop policy if exists supply_contracts_participant_read on public.supply_contracts;
create policy supply_contracts_participant_read on public.supply_contracts for select to authenticated
using (public.is_business_member(buyer_business_id) or public.is_business_member(supplier_business_id));
drop policy if exists supply_contracts_buyer_create on public.supply_contracts;
create policy supply_contracts_buyer_create on public.supply_contracts for insert to authenticated
with check (created_by=auth.uid() and status in ('draft','pending_supplier') and public.has_business_role(buyer_business_id,array['owner'::public.member_role,'manager'::public.member_role]) and exists(select 1 from public.businesses b where b.id=buyer_business_id and b.business_type='buyer') and exists(select 1 from public.businesses s where s.id=supplier_business_id and s.business_type='supplier' and s.is_active and s.verification_status='approved'));
drop policy if exists supply_contracts_supplier_accept on public.supply_contracts;
create policy supply_contracts_supplier_accept on public.supply_contracts for update to authenticated
using (status='pending_supplier' and public.has_business_role(supplier_business_id,array['owner'::public.member_role,'manager'::public.member_role]))
with check (status in ('active','pending_supplier') and public.has_business_role(supplier_business_id,array['owner'::public.member_role,'manager'::public.member_role]) and supplier_accepted_by=auth.uid() and supplier_accepted_at is not null);

begin;
create extension if not exists pgtap with schema extensions;
select plan(6);
select ok(to_regclass('public.order_workflow_events') is not null,'order workflow audit events table exists');
select ok(to_regclass('public.order_handoff_codes') is not null,'one-time handoff code table exists');
select ok((select relrowsecurity from pg_class where oid='public.order_workflow_events'::regclass),'workflow audit events enforce RLS');
select ok((select relrowsecurity from pg_class where oid='public.order_handoff_codes'::regclass),'handoff codes enforce RLS');
select ok(has_function_privilege('authenticated','public.transition_order_status(uuid,text,text)','EXECUTE')
 and not has_function_privilege('anon','public.transition_order_status(uuid,text,text)','EXECUTE'),'order transitions are authenticated-only');
select ok(has_function_privilege('authenticated','public.issue_order_handoff_code(uuid)','EXECUTE')
 and not has_function_privilege('anon','public.issue_order_handoff_code(uuid)','EXECUTE')
 and not has_table_privilege('authenticated','public.order_handoff_codes','SELECT'),'handoff code issuance is RPC-only and raw codes are never table-readable');
select * from finish();
rollback;

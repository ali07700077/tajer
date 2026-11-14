# TAJER Engineering Task Board

> Repository task ledger. Update status only when supported by a commit, test result, or review record. Production changes require explicit owner approval.

## Active delivery — PR #11 / Issue #9

- [x] Add demo catalogue migration and required-column drift checks.
- [x] Restrict demo catalogue reads through RLS; keep demo data out of permanent migration inserts.
- [x] Make optional demo catalogue fallback resilient.
- [x] Add database pgTAP coverage for demo visibility and privileges.
- [x] Add supplier directory null-safety and demo labelling.
- [x] Add CI workflow controls: least-privilege token permission and concurrency cancellation.
- [ ] Verify latest CI run is green on the current PR head.
- [ ] Review Claude's follow-up review after the latest fixes.
- [ ] Resolve remaining review items: authenticated-role read coverage, actual denied write attempts, migration idempotency verification, numeric precision alignment, and scope decision for the supplier directory.
- [ ] Verify RFQ/order flows cannot treat demo catalogue rows as real purchasable inventory.
- [ ] Keep PR #11 in Draft until all required checks and review evidence are complete.

## Next engineering phases

### Phase 1 — Repository and database integrity
- [ ] Inspect all migrations in order and compare schema assumptions with generated types and application queries.
- [ ] Establish disposable local/staging Supabase validation workflow.
- [ ] Add migration smoke tests and documented rollback/recovery procedures.
- [ ] Audit RLS policies for every exposed table and role.

### Phase 2 — Core marketplace workflows
- [ ] Verify buyer/supplier onboarding and role authorization.
- [ ] Verify catalogue, MOQ, RFQ, quotation, and order lifecycle end-to-end.
- [ ] Add server-side validation and audit events where required.
- [ ] Add tests for tenant isolation and authorization boundaries.

### Phase 3 — Host integration and release readiness
- [ ] Verify SuperQi Mini App requirements with authoritative platform documentation/owner.
- [ ] Confirm hosting, callback, authentication, and deployment requirements before implementation.
- [ ] Prepare staging acceptance checklist, observability, backups, and rollback plan.
- [ ] Obtain owner approval before production deployment.

## Explicitly out of MVP scope
- Payments, wallets, escrow, credit, settlement, and custody of customer funds. Any proposal requires a separate ADR, security/dependency review, and explicit owner approval.
- Production migrations, production data changes, secret rotation, repository administration, and deployment without explicit owner approval.

## Working rules
- Use feature branches and pull requests; never push directly to `main`.
- Record every meaningful handoff in `AI_SYNC_LOG.md`.
- Report exact commands and outcomes; never describe an unrun check as passed.
- Never commit credentials or expose service-role keys.

# TAJER — Engineering Master Specification
Version: 1.0
Status: Working baseline; implementation must pass acceptance tests before production.
Market: Iraq
Product: B2B wholesale marketplace
Primary experience: Arabic RTL, responsive web; SuperQi Mini App integration is a later, approval-dependent delivery target.

## 1. Product mission
Connect Iraqi retailers and business buyers with verified wholesalers and suppliers. Support discovery, wholesale pricing, RFQs, supplier offers, negotiation, order management, and operational visibility. The platform is a marketplace and workflow layer; it does not hold customer funds or provide wallet/payment services in the initial release.

## 2. User roles
- Visitor: browse public supplier/product information where policy permits.
- Buyer owner: manage buyer business profile, branches, members, RFQs, offers, and orders.
- Buyer staff: operate within assigned business permissions.
- Supplier owner: manage supplier business profile, catalog, price tiers, stock declarations, RFQ responses, and orders.
- Supplier staff: operate within assigned permissions.
- Platform support: handle support cases with least-privilege access.
- Platform reviewer: review supplier/business verification submissions.
- Platform administrator: manage platform configuration and access under audited controls.

## 3. Core release scope
### Identity and business onboarding
- Supabase Auth email/password initially; add phone OTP only after provider and cost review.
- User profile, business membership, invitation flow, role assignment.
- Business types: buyer, supplier, hybrid.
- Business verification workflow: draft, submitted, under_review, approved, rejected, suspended.
- Never trust client-provided role, verification, ownership, price, or order-state fields.

### Catalog and inventory
- Supplier catalog with categories, SKU, Arabic/English name, description, images, unit, MOQ, active status.
- Wholesale price tiers by quantity range and currency (IQD initially).
- Stock status and optional declared quantity; do not imply real-time ERP inventory unless integrated.
- Search, category filtering, supplier filtering, sorting, pagination.
- Product moderation and audit history.

### RFQ and negotiation
- Buyer creates RFQ with line items, quantities, delivery city, target date, notes, attachments if supported.
- Suppliers respond with price tiers, availability, lead time, offer validity, delivery terms.
- Buyer compares offers and may request revision.
- RFQ states: draft, published, receiving_offers, negotiating, awarded, cancelled, expired.
- Offer states: submitted, revised, accepted, declined, withdrawn, expired.
- Enforce business membership and supplier eligibility on the server/database.

### Orders
- Order created from an accepted offer; immutable snapshot of line descriptions, quantities, agreed prices, and terms.
- Status flow: pending_confirmation, confirmed, preparing, ready_for_dispatch, dispatched, delivered, cancelled, disputed.
- State changes must be validated server-side and audited.
- No payment collection, wallet, escrow, or settlement in initial release.

### Dashboards
- Buyer dashboard: active RFQs, offers received, orders, recent activity.
- Supplier dashboard: catalog status, incoming RFQs, submitted offers, orders.
- Admin dashboard: business reviews, user support, moderation queue, audit events, aggregate metrics.
- Analytics must distinguish demo/seed data from live records.

## 4. Technical baseline
- Frontend: existing Vite + React + TypeScript application. Preserve it; do not migrate to Next.js without a written ADR.
- Backend/data: existing Supabase PostgreSQL and Supabase Auth.
- Data access: Supabase client with publishable/anon key only in browser; never expose service_role or database password.
- Hosting: Vercel candidate; deployment ownership, project linkage, environment variables, and protection must be verified before claiming a live production deployment.
- Repository: GitHub repository ali07700077/tajer. Keep main and feature branches protected where supported; use pull requests for release changes.
- Arabic RTL first, responsive from 320px width; currency IQD; timezone Asia/Baghdad.
- SuperQi integration: only after official integration docs, technical approval, and credentials through approved secure channels.

## 5. Security requirements
- RLS enabled on every exposed table.
- Policies must scope records by authenticated user membership and business role.
- Deny by default; no broad authenticated write policies.
- SECURITY DEFINER functions require fixed search_path, minimal grants, input validation, and review.
- Sensitive verification/admin fields cannot be client-updated.
- Audit critical mutations: membership/role changes, verification decisions, product moderation, RFQ/offer/order state changes.
- Validate uploaded files, MIME types, size limits, and storage access.
- Secrets only in approved environment secret stores; never commit .env files.
- Rate-limit authentication and high-impact operations at a suitable layer.
- Test cross-business access denial, privilege escalation, and unauthenticated access.

## 6. Architecture boundaries
- UI components must not contain privileged business logic.
- Domain services own validation and orchestration.
- Supabase RLS is the final data-access boundary, not a substitute for UI checks.
- Shared TypeScript domain types must match database schema.
- Use migrations as the source of truth; no undocumented production schema edits.
- Keep demo fixtures separate from live Supabase data.

## 7. Delivery phases and acceptance gates
### Phase 0 — Repository and environment baseline
Deliver: architecture docs, reproducible install/build/typecheck, env example, branch/PR workflow.
Gate: clean install, typecheck and production build pass; no secrets committed.

### Phase 1 — Identity and business onboarding
Deliver: sign up/sign in/sign out, profile, create business, membership, role-aware navigation, verification submission.
Gate: tests prove a user cannot access another business or assign privileged roles.

### Phase 2 — Supplier catalog
Deliver: categories, products, images, MOQ, price tiers, supplier catalog management, buyer search.
Gate: RLS tests and CRUD tests for buyer/supplier/admin permissions.

### Phase 3 — RFQ and offers
Deliver: RFQ lifecycle, supplier responses, offer comparison, revisions and award.
Gate: only eligible suppliers can respond; only authorized buyer members can manage RFQ.

### Phase 4 — Orders and operations
Deliver: order snapshots, status transitions, activity log, dashboards.
Gate: invalid transitions rejected; audit records written.

### Phase 5 — Admin, support and reporting
Deliver: verification queue, moderation, role/permission administration, reports.
Gate: admin operations least privilege and fully audited.

### Phase 6 — Hardening and launch
Deliver: accessibility, mobile QA, performance, security review, backup/restore exercise, monitoring, operational runbook.
Gate: release checklist signed off; no unresolved critical/high security issues.

### Phase 7 — SuperQi integration and AI
Only after formal platform approval and documentation. AI search/recommendations are later enhancements, not dependencies for core marketplace launch.

## 8. Engineering workstreams
1. Product & business analysis — requirements, acceptance criteria, prioritization.
2. Architecture — boundaries, ADRs, technical coherence.
3. Frontend — responsive Arabic RTL flows and accessibility.
4. Backend — domain services and API integration.
5. Database — migrations, constraints, indexes, RLS and data lifecycle.
6. Security — threat model, privilege review, secret handling.
7. QA — unit, integration, RLS, end-to-end and regression tests.
8. DevOps — CI, preview/prod environments, observability, backups.
9. Research & AI — evaluated enhancements after core workflows are stable.

These are coordinated engineering workstreams executed with available tools; they are not claims that external human teams are independently working in the background.

## 9. Immediate implementation backlog
- [ ] Verify the repository tree and preserve existing source/migrations.
- [ ] Add CI for install, typecheck, build, and tests.
- [ ] Add architecture decision records and environment setup guide.
- [ ] Replace hard-coded demo metrics with explicit demo labels or live queries.
- [ ] Implement authentication state/session lifecycle and protected routes.
- [ ] Implement business onboarding and membership selection.
- [ ] Map existing Supabase schema to generated/shared TypeScript types.
- [ ] Review every RLS policy and SECURITY DEFINER function before enabling writes.
- [ ] Implement catalog CRUD and buyer search against real data.
- [ ] Implement RFQ and offer workflows with database constraints and audit events.

## 10. Definition of done
A feature is done only when requirements, UI, data model, authorization, error/loading/empty states, tests, documentation, and deployment impact are reviewed. A UI mock or local-only state is not a completed feature.

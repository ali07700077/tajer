# TAJER — Delivery Backlog and Team Instructions

## Operating rule
Work from the existing Vite + React + TypeScript application and existing Supabase project. Do not create a replacement app, duplicate migrations, delete the original `tajer/` source folder, or introduce a new framework without an approved architecture decision record.

## Required review roles
- Product owner: define user stories and acceptance criteria.
- Tech lead: approve architecture and integration boundaries.
- Frontend: implement Arabic RTL responsive flows.
- Backend/database: implement migrations, constraints, RLS, and domain operations.
- Security: review auth, role boundaries, RLS, storage, and privileged functions.
- QA: run typecheck, build, unit/integration/E2E and authorization tests.
- DevOps: CI, environment separation, deployment, monitoring and rollback.
- Research: assess SuperQi requirements and later AI capabilities.

## Sprint 0 — Stabilize
1. Inventory repository and identify canonical source tree.
2. Confirm npm scripts and dependency lockfile.
3. Ensure clean install, typecheck and production build.
4. Add CI workflow.
5. Document environment variables without real credentials.
6. Review current Supabase migrations against live schema; do not blindly replay.

## Sprint 1 — Real identity and business accounts
1. Auth session provider and route guards.
2. Registration, login, logout, password recovery.
3. Profile and create/select business.
4. Business member roles and invitations.
5. Verification submission and reviewer workflow.
6. RLS and cross-business isolation tests.

## Sprint 2 — Catalog
1. Category tree and supplier catalog.
2. Product CRUD, image storage, SKU, unit, MOQ.
3. Quantity price tiers and stock declaration.
4. Buyer search/filter/sort/pagination.
5. Product moderation and audit events.

## Sprint 3 — RFQ and offers
1. RFQ creation with line items and delivery details.
2. Eligible supplier discovery.
3. Supplier offer submission/revision.
4. Buyer offer comparison and award.
5. Notifications and event history.
6. RLS and lifecycle transition tests.

## Sprint 4 — Orders
1. Create immutable order snapshot from accepted offer.
2. Order status workflow with server-side validation.
3. Buyer/supplier order views.
4. Delivery notes and dispute records.
5. Audit and reporting.

## Sprint 5 — Admin and launch readiness
1. Verification/moderation/support console.
2. Least-privilege staff permissions.
3. Reporting and operational metrics.
4. Security and performance review.
5. Backup/restore rehearsal and deployment runbook.
6. Production acceptance review.

## Definition of done
No feature is complete based only on a visible button or mock screen. It must have real persistence, server/database authorization, validation, loading/error/empty states, tests, and documentation. Demo fixtures must be visibly labeled and isolated from live data.

## Constraints
- Iraq-first, IQD, Arabic RTL, responsive web.
- Keep payments/wallet out of initial scope.
- SuperQi integration only with official docs and approval.
- AI enhancements after core buyer/supplier workflows are stable.
- Never commit secrets or expose service_role/database credentials.

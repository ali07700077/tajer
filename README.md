# TAJER — Iraq B2B Wholesale Marketplace

TAJER is an Arabic-first, RTL wholesale marketplace foundation for Iraq. The current application is a web-based Mini App intended for an approved host integration; it is not a standalone native Android application.

## Stack

- React 19, TypeScript, and Vite
- Supabase Auth and PostgreSQL with Row Level Security
- Playwright for browser end-to-end tests
- Supabase CLI and pgTAP for database tests

## Local setup

1. Install Node.js 22 and npm.
2. Install dependencies:
   - If a committed `package-lock.json` exists, run `npm ci`.
   - This repository currently has no npm lockfile. Until one is committed, run `npm install --no-audit --no-fund`.
3. Copy `.env.example` to `.env.local`.
4. Set the public browser configuration variables:
   - `VITE_SUPABASE_URL`
   - `VITE_SUPABASE_PUBLISHABLE_KEY`
5. Start the local Supabase stack with the Supabase CLI and apply migrations to the disposable local database.
6. Run `npm run dev`.

## Validation

- `npm run typecheck`
- `npm run build`
- `npx playwright test`
- `supabase test db` (requires the local Supabase stack)

CI runs on pushes to `main` and pull requests targeting `main`. It uses `npm ci` when a package lockfile is present; otherwise it emits a warning and uses the documented npm install fallback.

## Database and credential safety

- Never run local development migrations or seed fixtures against production.
- Review migration history, schema compatibility, RLS policies, grants, and rollback implications before applying database changes.
- Never commit `.env`, access tokens, passwords, or service-role/secret keys.
- Only the publishable/anon key belongs in browser configuration. Never expose `service_role` in client code.
- Treat seed data as disposable local test data, not real merchants, products, prices, or inventory.
- Public catalogue access must be explicitly read-only and limited by RLS to approved public/demo rows.

## Current scope

The MVP focuses on supplier and buyer experiences, catalogue browsing, minimum order quantities (MOQ), RFQs, supplier quotations, orders, and role-based workspaces.

Payments, wallets, escrow, credit, settlement, and custody of customer funds are not enabled product capabilities in this MVP. Existing database objects in these areas must not be activated or removed without a separate architecture decision, dependency review, and owner approval.

SuperQi hosting, embedded-app APIs, credentials, and approval status must be verified with the platform owner; this repository does not claim an integration or approval that has not been confirmed.

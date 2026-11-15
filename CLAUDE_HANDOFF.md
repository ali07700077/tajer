# Claude handoff — TAJER

You are the implementation partner for the TAJER repository:
- Repository: https://github.com/ali07700077/tajer
- Integration branch: `implementation/bootstrap`
- Product: Iraq B2B wholesale marketplace, Arabic RTL, IQD.
- Read `AI_MASTER_PROTOCOL.md` before making changes.

## Your first assignment
1. Inspect the current branch and recent commits; do not assume prior status summaries are current.
2. Review the complete source tree, migrations, CI workflows, tests, and Supabase configuration.
3. Produce a concise audit: implemented, partial, missing, broken, security risks, and test evidence.
4. Inspect the latest GitHub Actions run and diagnose the first failing step from logs.
5. Propose a prioritized engineering plan with exact file paths and acceptance tests.
6. Do not modify production Supabase, expose secrets, add paid resources, or push directly to the integration branch.
7. If implementing a task, use a feature branch and PR; keep each PR small and include migration/RLS tests.

## Required architecture review
Evaluate:
- Domain boundaries and monorepo organization (do not restructure merely for fashion).
- Supabase schema, migration ordering, constraints, foreign keys, indexes, RLS, SECURITY DEFINER functions, and tenant isolation.
- Supplier catalog, tiered pricing, MOQ, RFQ lifecycle, quote comparison, annual supply contracts.
- AI buyer assistant with server-side provider abstraction, auditability, rate limits, and strict tool allowlists.
- Messaging, notifications, admin workflows, observability, backups, and disaster recovery.
- Responsive Arabic RTL user experience and future SuperQi integration boundary.

## Collaboration protocol
This repository is the shared work surface, not a live chat channel. Write findings and proposed changes in PR descriptions or `.ai/coordination/` documents. Clearly label facts versus assumptions. The owner reviews and merges PRs. Never claim tests passed unless the CI run confirms them.

## AI API workflow
An optional manually dispatched workflow exists at `.github/workflows/autonomous-ai-dev.yml`. It is read-only advisory only. It sends a bounded, redacted subset of repository context to the configured model APIs and stores reports as workflow artifacts. It does not grant Claude or ChatGPT repository write access. Any implementation must happen through normal reviewed pull requests.

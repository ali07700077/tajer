# TAJER AI Co-Pilot Bridge

## Purpose
This workflow runs a sequential implementation cycle:
1. OpenAI reads the available `AI_SYNC_LOG.md`, the task, and optional GitHub issue context, then creates the architecture plan.
2. Claude receives that exact plan and returns a unified code patch.
3. The runner validates patch paths, applies the patch on a new isolated branch, runs available project checks, pushes the branch, and opens a pull request.

This uses provider APIs. It does not connect interactive ChatGPT and Claude sessions or transfer their private chat histories.

## Owner setup
1. Add repository Actions secrets `OPENAI_API_KEY` and `ANTHROPIC_API_KEY` in Settings → Secrets and variables → Actions.
2. Confirm API access and billing with both providers. API usage can incur separate charges.
3. Ensure branch protection/rulesets require CI and owner review before merging to `main`.
4. Merge this bridge PR after reviewing its permissions and code.
5. Run Actions → TAJER AI Co-Pilot Bridge → Run workflow on `main`, provide a concrete task and optional issue number.
6. Review the generated AI implementation PR and download its workflow artifact.

## Permissions
The workflow token receives:
- `contents: write` — create and push a feature branch.
- `pull-requests: write` — open the implementation PR.
- `issues: read` — read optional issue context.

It does not receive `administration`, `secrets`, `actions`, `deployments`, or `environments` write permissions. It cannot change repository settings, secrets, branch protection, or environment approvals.

## Patch safety boundary
Claude-generated patches are restricted to:
- `src/`, `app/`, `components/`, `tests/`, `test/`, `docs/`
- `README.md`, `package.json`, `package-lock.json`, `tsconfig.json`, `vite.config.ts`

The bridge rejects paths outside this allowlist, including `.github/`, environment/secret files, Supabase migrations, and production infrastructure. Extend the allowlist only after reviewing the need and risk.

## Execution and review
- Available `typecheck` or `build` and `test` scripts are run when present.
- A successful local run does not replace GitHub CI, code review, security review, or application testing.
- The workflow creates a feature branch and PR; it never merges automatically.
- Human owner approval remains required for merging to `main`.
- No production deployment or production database operation is performed.

## Staging deployment
Staging deployment is not enabled by this bridge yet. It should be added only after a dedicated staging environment, scoped deployment credentials, and environment protection rules are configured. The current GitHub token has no deployment permission.

## Product and security boundaries
Payments, wallets, escrow, credit, settlement and custody remain outside MVP scope unless a separate owner-approved architecture decision changes that boundary. Issue and sync-log content are treated as untrusted input. Secrets are never sent to model providers.

## Limitations
This is API-based sequential orchestration, not a live shared conversation between the interactive ChatGPT and Claude products. API keys, provider access, model availability, and billing are controlled separately by the repository owner.

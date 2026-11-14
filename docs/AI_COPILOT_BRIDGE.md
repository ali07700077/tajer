# TAJER AI Co-Pilot Bridge

## Purpose
This workflow runs a sequential, two-stage engineering handoff:
1. OpenAI reads the available `AI_SYNC_LOG.md`, the task, and optional GitHub issue context, then creates the architecture plan.
2. Anthropic receives that exact plan plus the same context and returns a proposed implementation for human review.

The workflow calls provider APIs. It does not connect interactive ChatGPT and Claude sessions or transfer their private chat histories.

## Setup (repository owner)
1. Open GitHub **Settings → Secrets and variables → Actions**.
2. Add repository Actions secrets named `OPENAI_API_KEY` and `ANTHROPIC_API_KEY`. Never commit keys or paste them into Issues, PRs, or source files.
3. Confirm API access and billing with both providers. API usage may incur separate charges.
4. After this PR is reviewed and merged by the repository owner, open **Actions → TAJER AI Co-Pilot Bridge → Run workflow** on `main`.
5. Enter a concrete task and, optionally, a GitHub issue number.
6. Download the `tajer-ai-handoff-<run-id>` artifact to review the architecture plan and Claude's proposal.

## Sequential flow
- Stage 1: OpenAI creates an implementation-ready architecture plan.
- Stage 2: Claude receives the full OpenAI plan and creates a file-by-file implementation proposal, including diffs where the supplied context is sufficient.
- Output: `ai-bridge-output/AI_HANDOFF.md` as a workflow artifact.

The script reads `AI_SYNC_LOG.md` from the checked-out workflow ref when present. If it is absent, the report explicitly records that limitation; the script does not silently invent repository state. Ensure the current sync log is merged into `main` before running if it must be included.

## Security model
- Manual dispatch only; no automatic execution from arbitrary issue comments.
- Workflow token is read-only: `contents: read`, `issues: read`.
- Checkout does not persist GitHub credentials.
- No repository writes, commits, pushes, branch creation, PR creation, SQL execution, deployment, or production access.
- Issue text and sync-log content are treated as untrusted input and bounded before sending to model APIs.
- The AI output is a proposal, not a verified patch or test result. A maintainer must inspect actual source files, apply approved changes on a feature branch, run CI, and review through a PR.
- Payments, wallets, escrow, credit, settlement and custody remain outside MVP scope unless a separate owner-approved decision changes that boundary.

## Limitations
This is API-based sequential orchestration, not a live shared conversation between the interactive ChatGPT and Claude products. Each provider's API key, model availability, and billing are controlled separately by the repository owner. Model names are configured in the workflow.

## Output and approvals
The artifact contains the OpenAI architecture plan followed by Claude's implementation proposal. It does not claim tests passed unless actual test evidence is supplied. It does not authorize merging, production migrations, deployment, or changes to production data.

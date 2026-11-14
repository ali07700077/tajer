# TAJER AI Co-Pilot Bridge

## Purpose
The GitHub Actions bridge invokes the OpenAI and Anthropic APIs for independent, read-only engineering analysis. It is a coordination mechanism, not a direct ChatGPT-to-Claude conversation and not a grant of permissions to either product's chat UI.

## Setup (repository owner)
1. In GitHub, open **Settings → Secrets and variables → Actions**.
2. Add repository Actions secrets named `OPENAI_API_KEY` and `ANTHROPIC_API_KEY`. Never commit keys or paste them into Issues, PRs, or source files.
3. Confirm the account has API access and billing configured with both providers. API usage may incur separate charges.
4. Keep the workflow on `main`; invoke it manually from **Actions → TAJER AI Co-Pilot Bridge → Run workflow**.
5. Supply a concrete task and, optionally, an issue number. The workflow reads that issue and uploads a report artifact.

## Security model
- Manual dispatch only; no automatic execution from arbitrary issue comments.
- Workflow token is read-only: `contents: read`, `issues: read`.
- Checkout does not persist GitHub credentials.
- No repository writes, commits, pushes, branch creation, PR creation, SQL execution, deployment, or production access.
- SDK versions are pinned; model names are configurable in the workflow.
- Issue text is treated as untrusted input and bounded before sending to model APIs.
- Output is an artifact for human review. A maintainer must implement approved changes in a feature branch and review them through a PR.

## Limitations
This workflow calls provider APIs; it does not connect the interactive ChatGPT and Claude sessions, transfer their private conversation histories, or grant either session GitHub access. Each provider's API key, model availability, and billing are controlled separately by the repository owner.

## Output
The artifact contains separate OpenAI and Anthropic analyses. It does not claim tests passed unless the models were given actual test evidence.

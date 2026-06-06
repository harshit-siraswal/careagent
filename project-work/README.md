# CareAgent Project Work Packs

This folder holds executable work packs for project areas that are not just product documentation. Use these files when a workstream needs implementation sequencing, deployment notes, acceptance checks, or handoff instructions.

Primary source of truth remains:

- `docs/24-ai-system-architecture-and-project-handbook.md`
- Current frontend source in `C:\Users\ASUS\Desktop\careagent`
- Current backend source in `C:\Users\ASUS\Desktop\careagent-backend`

Work packs in this folder should stay practical:

- State what is already built.
- State what is still missing.
- Name the repo and files to change.
- Include safe rollout steps.
- Include tests or checks that prove the work is done.
- Avoid storing secrets, provider credentials, tokens, or local environment files.

## Current Packs

| Pack | Purpose | Status |
| --- | --- | --- |
| `remaining-work/` | Execution queue derived from the newest handbook and gap reports. | Started |
| `openclaw-agent/` | OpenClaw prototype gateway and agent runtime deployment plan. | Started |

## How To Use

1. Read `docs/24-ai-system-architecture-and-project-handbook.md`.
2. Pick the relevant project-work pack.
3. Inspect the current repo code before changing anything.
4. Update the pack when implementation facts, deployment decisions, or exit criteria change.
5. Keep final architecture decisions reflected back in `docs/24-ai-system-architecture-and-project-handbook.md`.


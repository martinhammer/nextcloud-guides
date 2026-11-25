---
name: github-ci
description: "GitHub Actions CI for Nextcloud apps outside the nextcloud org: the org templates as source of truth, the post-sync step, .yml.patch files, the audit script, known failures. This skill should be used when adding, syncing or auditing anything in .github/workflows, when a CI job fails or a scheduled run goes red, and when a job passes without testing anything."
paths: ".github/workflows/**"
---

# Nextcloud GitHub CI

**The source of truth is `nextcloud/.github/workflow-templates/`.** Not
`nextcloud/app_template` (it lags behind), and not another app's copy (frozen on
the day it was copied). Dependabot bumps only action SHAs, never steps.

- Never hand-edit a synced workflow. A deliberate change lives in a
  `.github/workflows/<name>.yml.patch` that every sync re-applies.
- After every sync, do the guide's post-sync step (runner label, matrix entries
  for `stableNN` branches the repo doesn't have).
- Each app's CLAUDE.md lists only its own deviations (its patches, deliberately
  absent workflows). The procedure itself is here.

Read `${CLAUDE_SKILL_DIR}/references/nextcloud-github-ci.md` before touching workflows: the
baseline set, what the repository must provide, syncing, the audit script (run it
and compare), reading a failure, and the field notes on past failures.

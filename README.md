# nextcloud-guides

This is a set of guidelines, best practices and how-tos related to my Nextcloud app development efforts.

The guides have been prepared using AI coding tools (Claude Code in particular). They have been tested on my particular environment, your mileage may vary.

## Guides

| Guide | What it covers |
| --- | --- |
| [App icon contract](skills/app-icons/nextcloud-app-icon-contract.md) | `img/app.svg` / `app-dark.svg`: where paint may go, the file pair, a check script |
| [Charts](skills/charts/nextcloud-charts.md) | Theme-aware Chart.js charts: one runtime palette, live theme changes, accessibility |
| [Dev environment](skills/dev-environment/nextcloud-dev-environment-maintenance.md) | `nextcloud-docker-dev`: containers, versions, maintenance runbook, notes for app developers |
| [ESLint config v9 migration](skills/eslint-v9-migration/nextcloud-eslint-config-v9-migration.md) | `@nextcloud/eslint-config` 8 → 9 (ESLint 10, flat config) |
| [GitHub CI](skills/github-ci/nextcloud-github-ci.md) | Org workflow templates, syncing them outside the `nextcloud` org, audit script |
| [OCS error messages](skills/ocs-errors/nextcloud-ocs-error-messages.md) | Reading OCS error messages so error toasts aren't blank |
| [HTTP client](skills/http-client/SKILL.md) | `IClient` vs plain Guzzle: `getAsync()` is synchronous, `stream` is ignored |

## Use with Claude Code

The repository is also a Claude Code plugin (`nextcloud`) and its own marketplace.
Each guide is a skill: Claude sees its short description in every session where the
plugin is enabled and reads the full guide only when the task needs it.

```sh
claude plugin marketplace add ~/Code/nextcloud-guides      # or: martinhammer/nextcloud-guides
cd ~/Code/<your-nextcloud-app>
claude plugin install nextcloud@nextcloud-guides --scope project
```

`--scope project` enables the plugin in that repository only (in `.claude/settings.json`).
Added from a local directory, the plugin is read in place: edits to the guides take
effect at the next session or after `/reload-plugins`.

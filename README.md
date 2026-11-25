# nextcloud-guides

This is a set of guidelines, best practices and how-tos related to my Nextcloud app development efforts.

The guides have been prepared using AI coding tools (Claude Code in particular). They have been tested on my particular environment, your mileage may vary.

## Guides

| Guide | What it covers |
| --- | --- |
| [App project files](skills/app-project-files/SKILL.md) | Shared `.gitignore`, `.nextcloudignore` and Makefile (stage, package, appstore), script names, a check script |
| [App icon contract](skills/app-icons/references/nextcloud-app-icon-contract.md) | `img/app.svg` / `app-dark.svg`: where paint may go, the file pair, a check script |
| [Charts](skills/charts/references/nextcloud-charts.md) | Theme-aware Chart.js charts: one runtime palette, live theme changes, accessibility |
| [Dashboard widget](skills/dashboard-widget/SKILL.md) | API vs Vue widgets, the cost of `load()`, panel size, icon URLs, the permanent widget id |
| [ESLint config v9 migration](skills/eslint-v9-migration/references/nextcloud-eslint-config-v9-migration.md) | `@nextcloud/eslint-config` 8 → 9 (ESLint 10, flat config) |
| [GitHub CI](skills/github-ci/references/nextcloud-github-ci.md) | Org workflow templates, syncing them outside the `nextcloud` org, audit script |
| [HTTP client](skills/http-client/SKILL.md) | `IClient` vs plain Guzzle: `getAsync()` is synchronous, `stream` is ignored |
| [OCS error messages](skills/ocs-errors/references/nextcloud-ocs-error-messages.md) | Reading OCS error messages so error toasts aren't blank |
| [PHP backend](skills/php-backend/references/nextcloud-php-backend.md) | Config APIs and reserved keys, migrations, app version, OpenAPI, public OCS endpoints, capabilities, Composer/vendor-bin, Psalm, test bootstrap |
| [Responsive layout](skills/responsive-layout/references/nextcloud-responsive-layout.md) | Nextcloud's 1024/512 breakpoints, content-width steps, list/detail, two-line cards, touch |
| [Vue frontend](skills/vue-frontend/references/nextcloud-vue-frontend.md) | `@nextcloud/vue` 9 drift, component quirks, core CSS vs app CSS, theme colour pairs, dialogs, first day of week, build and CI wiring |

## Guides for people

Not skills: guides for maintaining the environment the apps are developed in.

| Guide | What it covers |
| --- | --- |
| [Dev environment](guides/nextcloud-dev-environment-maintenance.md) | `nextcloud-docker-dev`: containers, versions, maintenance runbook, notes for app developers |

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

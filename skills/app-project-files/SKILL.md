---
name: app-project-files
description: "The shared project files of a Nextcloud app: .gitignore, .nextcloudignore (what stays out of the release) and the Makefile (build, lint, test, openapi, stage, package, appstore), kept identical across apps above an App-specific marker line, with a check script. This skill should be used when creating a new Nextcloud app, when adding to or changing any of these three files, when a file shows up in or is missing from a release or staged tree, when choosing npm or composer script names, and when a make target behaves differently from one app to the next."
paths: ".gitignore, .nextcloudignore, Makefile"
---

# Shared project files

Three files are the same in every app, so build, packaging and ignore rules
are decided once. The shared versions are in `${CLAUDE_SKILL_DIR}/assets/`:
copy them, never retype them.

| File in the app | Asset | Based on |
|---|---|---|
| `.gitignore` | `assets/gitignore` | `nextcloud/app_template`'s `.gitignore`, plus build output, Claude Code, secrets and local deploy files |
| `.nextcloudignore` | `assets/nextcloudignore` | `nextcloud/app_template`'s `.nextcloudignore`, plus docs, Claude Code, Makefile, OpenAPI specs, screenshots |
| `Makefile` | `assets/app.mk` (copy it as `Makefile`) | Our own: app_template packages with krankerl and has no Makefile |

## Rules

- **Each file is the shared part, then the line
  `# --- App-specific (below this line) ---`, then this app's additions.**
  Change the shared part in the asset and copy it to every app, never in one app.
  The Makefile takes the app id, name and version from `appinfo/info.xml`, so
  its shared part needs no editing.
- **`.nextcloudignore` is the only list of what stays out of a release.** Both
  `make stage` (working tree) and `make package` (committed HEAD) copy the app
  through `rsync --exclude-from=.nextcloudignore`. Patterns are gitignore-style,
  but **no `!` lines** (rsync can't read them). A new top-level file or folder
  that must not ship (docs, tools, samples) gets a line in the app-specific part.
- **`.gitignore` decides what is in git; `.nextcloudignore` what is in the
  release.** Files that are gitignored never reach either tree, except `js/`,
  `css/` and the production `vendor/`, which the Makefile adds from the build.
- **`.claude/settings.json` and `.claude/rules/` are committed**; everything
  else in `.claude/` and `CLAUDE.local.md` stays local. None of it ships.
- **Release format:** `make package` writes
  `build/release/<id>-v<version>.tar.gz` with a single top-level `<id>/`
  directory. `make appstore` copies it to `build/artifacts/<id>.tar.gz`, the path
  the `nextcloud/.github` appstore-build-publish workflow signs and uploads.
  These are release targets: the person builds and signs releases.
- **Script names are fixed, because the Makefile and the org CI templates call
  them.**
  - npm: `build`, `lint`, `stylelint`, `ts:check` (`vue-tsc --noEmit`), and
    `test` (Vitest) when there is a `vitest.config.*`.
  - composer: `lint`, `cs:check`, `cs:fix`, `psalm`, `test:unit`, and `openapi`
    when there is an `openapi.json`.
  - Other names (`typecheck`, `test:frontend`) may exist as aliases, never
    instead of these.
- `make check` (lint + psalm + test + openapi) is the local equivalent of CI.

## Check an app

```sh
bash ${CLAUDE_SKILL_DIR}/scripts/check-project-files.sh <app-dir> --ship-list
```

It is read-only. It reports `DRIFT` (the shared part differs, with a diff),
`MISSING`, `NEGATION` (`!` lines in `.nextcloudignore`) and `SCRIPT` (a script
the Makefile calls is missing). `--ship-list` prints what a release built from
HEAD would contain. Run it after changing any of the three files, and read the
ship list whenever a top-level file or folder is added.

A deviation the app keeps for now goes in the app's `docs/backlog.md`, not here.

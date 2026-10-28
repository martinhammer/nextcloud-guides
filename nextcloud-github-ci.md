# Nextcloud GitHub CI

Which GitHub Actions workflows a Nextcloud app should run, where they come from, what
each one needs from the repository, and how to keep them current. Run the audit at
the end against your own repo and compare the result with this guide.

- **Applies to:** any Nextcloud app on GitHub whose `.github/workflows/` came from
  `nextcloud/app_template` or from the org templates in `nextcloud/.github`
- **Researched against:** `nextcloud/.github` `workflow-templates/` at `807f558`
  (2026-10-28) and `nextcloud/app_template` (October 2026)

---

## The rule

> **The source of truth is `nextcloud/.github/workflow-templates/`. Not the
> skeleton app, and not another app's copy.**

Workflows are copied into a repo and then never update themselves. There are three
places to copy from, and they drift apart:

| Source | What it is | How current it is |
| --- | --- | --- |
| `nextcloud/.github` `workflow-templates/` | The org's maintained templates | Current. Fixes land here first |
| `nextcloud/app_template` | The skeleton a new app is scaffolded from | **Lags behind.** In Oct 2026 it still had a Psalm step the org removed in April, and still shipped `node.yml` and `update-nextcloud-ocp-approve-merge.yml`, both since retired (see field notes) |
| Another app's `.github/workflows/` | Whatever was current when that app copied it | Frozen on the day it was copied, apart from Dependabot bumping action versions |

Dependabot's `github-actions` ecosystem bumps only the **pinned action SHAs**. It
never changes the steps. A fix to a template reaches your repo only when you sync.

## The baseline set

These are the workflows every app should have: the set `app_template` ships, corrected
for templates upstream has since renamed or retired (see below). "Local" is what to run
before pushing to reproduce the check.

| Workflow | Trigger | What it checks | Local |
| --- | --- | --- | --- |
| `lint-eslint.yml` | PR | ESLint, skipped when no frontend path changed | `npm run lint` |
| `lint-stylelint.yml` | PR | stylelint | `npm run stylelint` |
| `npm-build.yml` | PR | `package-lock.json` is valid, and `npm ci` + `npm run build` leaves the tree clean. Formerly `node.yml`; its summary job is still called `node`, so required-check names carry over | `npm ci && npm run build && git status` |
| `lint-php.yml` | PR | `php -l` on the lowest and highest supported PHP | `composer run lint` |
| `lint-php-cs.yml` | PR | php-cs-fixer dry run | `composer run cs:check` |
| `psalm-matrix.yml` | PR | Psalm against each `nextcloud/ocp` branch the app supports | `composer run psalm` |
| `openapi.yml` | PR | Regenerating `openapi*.json` leaves the tree clean | `composer run openapi && git status` |
| `lint-info-xml.yml` | PR | `appinfo/info.xml` against the app store's `info.xsd` | — |
| `block-unconventional-commits.yml` | PR | Commit messages follow Conventional Commits | — |
| `fixup.yml` | PR | No `fixup!` / `squash!` commits | — |
| `update-nextcloud-ocp-matrix.yml` | weekly | Opens a PR bumping `nextcloud/ocp`, then approves it and turns on auto-merge itself | — |
| `npm-audit-fix.yml` | weekly | Opens a PR with `npm audit fix` and rebuilt assets, then approves it and turns on auto-merge itself | — |
| `appstore-build-publish.yml` | release published | Builds the app, signs it and uploads it to the app store. `app_template` ships it with a `.yml.patch` (see "Apps outside the `nextcloud` org") | — |

The scheduled workflows' approve and auto-merge steps depend on repo settings that
are **off by default**, and when a setting is off the step fails, so every run goes
red after the PR has been opened:

| Step | Needs | Gated by `AUTOMERGE: false`? |
| --- | --- | --- |
| *GitHub actions bot approve* (`gh pr review --approve`) | Settings → Actions → General → **Allow GitHub Actions to create and approve pull requests** | **No**, it always runs |
| *Enable auto merge* | Settings → General → **Allow auto-merge**, and on an unprotected branch, required status checks (otherwise there is nothing to wait for) | Yes |

Pick one per repo:
- **Let them merge themselves:** turn on both settings and protect the default
  branch with required checks.
- **Merge bot PRs by hand:** add a `.yml.patch` to `update-nextcloud-ocp-matrix.yml`
  and `npm-audit-fix.yml` that deletes both steps (they are the last two steps of
  each file). Setting `AUTOMERGE: false` alone is not enough, because the approve
  step still runs.

**Renamed or retired templates.** When upstream renames or drops a template, it
leaves a **stub** under the old name: a workflow named `No-op please …` whose only
step prints what to do and **fails** (`exit 1`). That way an app still running the
old copy is told about it on its next sync. Do not sync a stub over your file. Do what
its message says:

| Old file | Status | Do this |
| --- | --- | --- |
| `node.yml` | Renamed to `npm-build.yml` (2026-05-16) | `git mv` it to `npm-build.yml`, then sync that |
| `update-nextcloud-ocp-approve-merge.yml` | Retired (2026-09-16). Approve and auto-merge moved into `update-nextcloud-ocp(-matrix).yml` and `npm-audit-fix.yml` | Delete it, in the same change that syncs `update-nextcloud-ocp-matrix.yml`. Until then your old copy still does the approving |

Add templates from the catalogue as the app needs them. Use the same file name, so a
sync can find them:

| If the app has… | Add | It runs |
| --- | --- | --- |
| PHPUnit tests | `phpunit-sqlite.yml`, plus `phpunit-{mysql,mariadb,pgsql,oci}.yml` for real DB coverage | `composer run test:unit` (and `test:integration`), inside a `nextcloud/server` checkout with the app installed |
| Frontend unit tests | `node-test.yml` | `npm run test` (and `test:coverage`) |
| End-to-end tests | `cypress.yml` or `playwright.yml` | — |
| TypeScript | `lint-typescript.yml` | `npm run check-types` and/or `npm run ts:check` |
| REUSE licence headers | `reuse.yml` | — |
| Stable branches | `block-merge-eol.yml`, `block-merge-freeze.yml` | — |
| Dependabot PRs to auto-merge | `dependabot-approve-merge.yml` | — |

> **Check the script names.** The test templates call their scripts with
> `--if-present` (or check whether the script exists first). If the script has a
> different name in your app (`test:frontend` instead of `test`, `type-check` instead
> of `ts:check`), the job **passes without running anything**. Add the expected name,
> as an alias if you want to keep your own, and check the job log to confirm the tests
> actually ran.

Also keep `.github/dependabot.yml` with three ecosystems: `composer` (`/` and
`/vendor-bin/*`), `npm`, and `github-actions`. Give all three the same weekly slot.

## What the repository must provide

The workflows call named scripts and read versions from files. If any of these is
wrong, a check fails or, worse, quietly checks nothing.

- **`appinfo/info.xml` `<nextcloud min-version max-version>`** drives
  `nextcloud-version-matrix`. It decides which `ocp` branches Psalm runs against,
  plus `php-min` and `php-max`.
- **`psalm.xml` `phpVersion`** must equal `php-min`. The Psalm matrix job greps for it
  and fails if it differs.
- **`composer.json` scripts:** `lint`, `cs:check`, `cs:fix`, `psalm`, `openapi`, with
  the tools in `vendor-bin/*` (bamarni bin plugin). **`nextcloud/ocp` in
  `require-dev`**, because CI removes it and installs each matrix branch in turn.
- **For `phpunit-*` workflows:** the app's `tests/bootstrap.php` must load the server's
  `tests/bootstrap.php` (at `../../../tests/bootstrap.php` from the app's `tests/`)
  when it exists. The workflow removes `nextcloud/ocp`, so without that nothing
  defines `OCP\*`. And **no library the server already ships may be in the app's own
  `require`/`require-dev`** (e.g. `doctrine/dbal` added for Psalm). The workflow
  installs dev dependencies and enables the app, and a second copy in the app's
  `vendor/` breaks that. See the field notes.
- **`composer.json` `config.platform.php`** pins the PHP version Composer resolves
  against. It is a fake version, not the one installed: `"8.2"` means 8.2.0. See the
  field notes for when that matters.
- **`package.json` scripts:** `lint`, `stylelint`, `build`. **`engines.node` /
  `engines.npm`** choose the Node and npm versions in CI.
- **Committed:** `package-lock.json` (`npm ci` needs it) and `openapi*.json`. Build
  output (`js/`, `css/`) must be either committed or gitignored, consistently with
  `npm-build.yml`'s clean-tree check.
- **Repo secret `COMMAND_BOT_PAT`**, for the scheduled workflows that open PRs
  (`npm-audit-fix`, `update-nextcloud-ocp-matrix`). Use a token that can push
  branches and open PRs. Without it, the PR step fails. The PR has to come from a
  different account than `GITHUB_TOKEN`, because the approve step approves with
  `GITHUB_TOKEN` and GitHub does not let an account approve its own PR.

## Apps outside the `nextcloud` org

The templates are written for repos in the `nextcloud` organisation. In any other
account, four things differ:

- **Owner guards switch whole jobs off.** Some templates run their job only for a
  given owner, and anywhere else the job is **skipped**. A skipped job counts as
  success, so nothing turns red; the work simply stops happening.

  | Template | Guard | What you lose elsewhere |
  | --- | --- | --- |
  | `update-nextcloud-ocp-matrix.yml`, `update-nextcloud-ocp.yml` | `repository_owner == 'nextcloud'` | The weekly `nextcloud/ocp` bump PRs |
  | `appstore-build-publish.yml` | `repository_owner == 'nextcloud-releases'` | App store releases |

  Remove the guard with a `.yml.patch` (see below), so it is re-applied on every
  sync. `app_template` already does this for `appstore-build-publish.yml`; its
  `appstore-build-publish.yml.patch` deletes the guard "for community apps" and is
  the model to copy. For the `ocp` workflows, the patch only has to delete these
  lines:

  ```diff
  -    # Only allowed to be run on nextcloud repositories
  -    if: ${{ github.repository_owner == 'nextcloud' }}
  -
  ```

  Guards that exclude an owner rather than require one (`openapi.yml` skips only for
  `nextcloud-gmbh`) need nothing.
- **`runs-on: ubuntu-latest-low`** (in most templates) is not one of GitHub's standard
  hosted-runner labels. It is a runner the Nextcloud org provides. Elsewhere, jobs
  that ask for it are never picked up. Use `ubuntu-latest`, and re-apply that after
  every sync.
- **`sync-workflow-templates.yml` does not work as shipped.** It checks out
  `<owner>/.github`, which is your account rather than `nextcloud`, and needs the
  org's `COMMAND_BOT_WORKFLOWS` secret. Sync by hand instead (below).
- **Org-only templates** need secrets you do not have and add nothing for a single
  app: `ai-policy`, `command-*`, `pr-feedback`, `release-relay`,
  `update-stable-titles`. Leave them out.

## Keeping workflows in sync

**Deliberate local changes go in a patch file.** This is the org's own convention: a
change to `.github/workflows/foo.yml` lives as `foo.yml.patch` next to it, made with
`git diff .github/workflows/foo.yml > .github/workflows/foo.yml.patch`, and every
sync re-applies it. An edit that is not in a patch is reverted by the next sync, as
it should be.

**Before updating, deal with renamed and retired templates** (see "Renamed or retired
templates" above): rename `node.yml` to `npm-build.yml`, and plan to delete
`update-nextcloud-ocp-approve-merge.yml`. The update script copies over every file
you already have, so it would replace a working `node.yml` with the failing stub. The
audit below reports these as `RETIRED`.

**To update**, use the manual script from the `nextcloud/.github` README (*Update
workflows manually*). It clones the templates, rsyncs over only the files you already
have, and re-applies the patches. Outside the org, then run:

```sh
sed -i 's/ubuntu-latest-low/ubuntu-latest/' .github/workflows/*.yml
```

Then check the diff for any `repository_owner ==` guard that came in without a patch,
review the rest, and run CI before merging. **Sync on a schedule, every few months,
and whenever one check starts failing on every PR at once.**

## Audit your repo

Run this from the app's repo root. It changes nothing. For each workflow it reports
whether you match the current template, once your `.yml.patch` files are applied and
pinned SHAs and the runner label are ignored.

```bash
#!/usr/bin/env bash
# Compare this app's GitHub workflows with the Nextcloud org templates.
# Run from the app repo root. Needs: gh (authenticated), base64, diff, patch.
# VERBOSE=1 prints the differences.
set -euo pipefail

tmp=$(mktemp -d)
# Pinned SHAs differ for harmless reasons (Dependabot timing), and outside the org
# `ubuntu-latest-low` is replaced by `ubuntu-latest`, so normalise both away.
norm() {
	sed -E -e 's/(uses:[[:space:]]*[^@[:space:]]+)@[^[:space:]]+([[:space:]]*#.*)?$/\1@PIN/' \
		-e 's/ubuntu-latest-low/ubuntu-latest/' "$1"
}
# Exit 1 = no such template (404); 2 = the request failed, which must not pass for "local".
template() {
	local c
	if ! c=$(gh api "repos/nextcloud/.github/contents/workflow-templates/$1" --jq .content 2> "$tmp/err"); then
		grep -q 'HTTP 404' "$tmp/err" && return 1
		return 2
	fi
	printf '%s' "$c" | base64 -d
}

# Baseline = the workflows app_template ships today (not its .yml.patch files), plus
# whatever this repo already has.
baseline=$(gh api repos/nextcloud/app_template/contents/.github/workflows \
	--jq '.[].name | select(endswith(".yml"))')
mine=$(cd .github/workflows && ls -- *.yml 2>/dev/null || true)
owner=$(gh repo view --json owner --jq .owner.login)

for n in $(printf '%s\n%s\n' "$baseline" "$mine" | sort -u); do
	f=.github/workflows/$n
	rc=0
	template "$n" > "$tmp/$n" || rc=$?
	if [ "$rc" = 1 ]; then
		echo "local    $n  (no org template — yours to maintain)"
		continue
	elif [ "$rc" != 0 ] || [ ! -s "$tmp/$n" ]; then
		echo "ERROR    $n  (could not fetch the template: $(head -1 "$tmp/err"))"
		continue
	fi
	# A renamed or retired template is left behind as a failing "No-op please …" stub.
	if grep -q '^name: No-op' "$tmp/$n"; then
		[ -f "$f" ] && echo "RETIRED  $n  ($(sed -n 's/^name: No-op //p' "$tmp/$n" | head -1))"
		continue
	fi
	if [ ! -f "$f" ]; then
		echo "MISSING  $n  (in app_template's baseline)"
		continue
	fi
	ref=$tmp/$n
	if [ -f "$f.patch" ]; then
		if patch -s -o "$tmp/$n.patched" "$tmp/$n" < "$f.patch"; then
			ref=$tmp/$n.patched
		else
			echo "PATCH    $n  ($n.patch no longer applies to the template)"
			continue
		fi
	fi
	# An owner guard skips the whole job (and a skip shows as success) in other
	# accounts. Check your file, and the template plus your patch, i.e. what a sync
	# would give you.
	for g in $(cat "$f" "$ref" | grep -o "repository_owner == '[^']*'" | sed "s/.*== '//; s/'$//" | sort -u); do
		[ "$g" = "$owner" ] && continue
		if grep -q "repository_owner == '$g'" "$f"; then
			echo "GUARD    $n  (job runs only for '$g', this repo is '$owner')"
		else
			echo "GUARD    $n  (a sync would add a guard: job runs only for '$g', this repo is '$owner')"
		fi
	done
	if ! diff -q <(norm "$f") <(norm "$ref") > /dev/null; then
		echo "DRIFT    $n"
		[ "${VERBOSE:-}" ] && diff <(norm "$f") <(norm "$ref") | sed 's/^/           /' || true
	elif ! diff -q "$f" "$ref" > /dev/null; then
		echo "pins     $n  (only action pins / runner label differ)"
	else
		echo "same     $n"
	fi
done
```

How to read the result:

| Status | Meaning | Action |
| --- | --- | --- |
| `same`, `pins` | In step with upstream (`pins`: only SHAs or the runner label differ) | None. Dependabot handles the pins |
| `DRIFT` | Steps differ from the template | Sync. If the difference is deliberate, move it into a `.yml.patch` |
| `PATCH` | The template changed under your patch | Re-make the patch against the new template |
| `MISSING` | A baseline workflow is absent | Add it, or record why the app does not need it |
| `RETIRED` | Upstream renamed or dropped this template; syncing would install a failing stub | Do what the message says: rename the file, or delete it (see "Renamed or retired templates") |
| `GUARD` | The workflow's job runs only for another owner, so here it is silently skipped, or would be after a sync. Printed in addition to the status | Remove the guard with a `.yml.patch` (see "Apps outside the `nextcloud` org") |
| `ERROR` | The template could not be fetched (rate limit, network) | Re-run. Never read it as `local` |
| `local` | No org template has this name | Fine if it is yours (e.g. an `assign.yml`). If it is a renamed copy of a template, rename it back so syncs reach it |

Then go through the checklist:

- [ ] Every baseline workflow is present, or its absence is explained in the repo.
- [ ] No `DRIFT`. Every deliberate change is a `.yml.patch`.
- [ ] No `RETIRED`: `node.yml` is now `npm-build.yml`, and
      `update-nextcloud-ocp-approve-merge.yml` is gone once
      `update-nextcloud-ocp-matrix.yml` is synced.
- [ ] Outside the org: no `ubuntu-latest-low` left in `.github/workflows/`, and no
      `GUARD`. Each owner guard is removed by a `.yml.patch`.
- [ ] The scheduled workflows' approve/auto-merge steps either have their repo
      settings on (Actions may approve PRs, Allow auto-merge, required checks) or
      are removed by a `.yml.patch`.
- [ ] `psalm.xml` `phpVersion` equals `php-min` for the `info.xml` range.
- [ ] The `composer.json` and `package.json` scripts listed above exist.
- [ ] Every test suite the repo has (PHPUnit, frontend unit tests, type checks) is run
      by a workflow, under the script name that workflow calls. Confirm it in a job
      log, not from a green tick.
- [ ] `COMMAND_BOT_PAT` is set, if `npm-audit-fix` or `update-nextcloud-ocp-matrix`
      is present.
- [ ] `.github/dependabot.yml` covers `composer` (incl. `/vendor-bin/*`), `npm` and
      `github-actions`.

## Reading a failure

- **Matrix workflows end in a `…-summary` job** that fails when any matrix job fails.
  Open the failing job itself, not the summary.
- **If one check fails on every PR at once, including Dependabot bumps that touch
  nothing it checks, the environment changed, not the code.** Look at what the
  failing step pulls in fresh (`dev-latest`, `:latest`, `npm i -g …`), then run the
  audit: the template may already have dropped or fixed that step.
- `gh run view <run> --log-failed` sometimes returns nothing. The raw job log always
  works: `gh api repos/<owner>/<repo>/actions/jobs/<job-id>/logs`.

---

## Field notes

Findings from real CI failures. Add to this rather than rediscovering.

### 2026-10-24 — Psalm fails on every PR: `roave/security-advisories` vs the platform PHP pin

**Symptom.** Every `static-psalm-analysis` matrix job fails on every PR, before Psalm
runs, at the step *Check for vulnerable PHP dependencies*:

```
composer require --dev roave/security-advisories:dev-latest
  - php is present at version 8.2 and cannot be modified by Composer
  - roave/security-advisories dev-latest conflicts with php <8.2.35|>=8.3,<8.3.36|…
```

Other apps with an identical `composer.json` pass.

**Who is affected.** Apps whose `psalm-matrix.yml` (or `psalm.yml` / `phpstan.yml`)
still has that step. It came from `app_template`. The org templates dropped it on
2026-04-21 (nextcloud/.github#712: *"This should no longer be needed as of composer
2.9"*, since Composer 2.9 itself refuses packages with known advisories through
`audit.block-insecure`, which defaults to `true`). Apps that set up their workflows
from the org templates, or synced after April, never had the step and pass.

**Mechanism.**

- `config.platform.php: "8.2"` makes Composer treat PHP as **8.2.0**, whatever the
  runner has installed (8.2.35 in this case, which would have passed).
- `roave/security-advisories` lists vulnerable **PHP versions** as conflicts as well
  as packages. When it added a floor of 8.2.35, the fake 8.2.0 fell inside it.
- The step runs `composer require … dev-latest`, which fetches today's roave instead
  of the snapshot in `composer.lock`. Installing from the lock alone passes, because
  the locked snapshot predates the new floor.

**Fix.** Sync the workflow with the org template, or at least delete the step:

```yaml
      - name: Check for vulnerable PHP dependencies
        run: composer require --dev roave/security-advisories:dev-latest
```

Do this in every Psalm/PHPStan workflow the app has, then rebase open PRs
(`@dependabot rebase` on Dependabot's).

**Not recommended: raising the pin** to the floor named in the error (`"8.2.35"` +
`composer update --lock`). It turns CI green, but it breaks again with every PHP
security release that roave picks up.

**Still latent after the fix.** As long as `roave/security-advisories` stays in
`require-dev` (`app_template` still puts it there), any **local** `composer update`
resolves today's roave against the fake platform version and fails with the same
message. CI is no longer affected, but whoever next updates dependencies is. Choose
one per app:

- **Remove roave from `require-dev`** (`composer remove --dev
  roave/security-advisories`) and rely on Composer ≥ 2.9's built-in blocking. This is
  the direction upstream took. Composer's check covers packages only, not the PHP
  version, but a check against a fake platform version was not telling you anything
  about your PHP anyway.
- **Keep it**, and expect to raise `config.platform.php` whenever a local update hits
  this error.

### 2026-10-25 — Adding test workflows: green jobs that test nothing, and an app that will not enable

Two traps hit when adding `phpunit-sqlite.yml`, `node-test.yml` and
`lint-typescript.yml` to an app that had test suites but never ran them in CI.

**1. Script names.** `node-test.yml` runs `npm run test --if-present`, and
`lint-typescript.yml` runs `npm run --if-present check-types` and `ts:check`. The app
called them `test:frontend` and `type-check`, so as copied both jobs would have
passed without running anything. Fix: add the names the templates expect, as aliases
if the existing names are documented elsewhere:

```json
"ts:check": "npm run type-check",
"test": "npm run test:frontend",
```

**2. `phpunit-sqlite` fails before a single test, in two ways.** It removes
`nextcloud/ocp`, installs the app with dev dependencies at `<server>/apps/<app>`, runs
`occ app:enable`, then `composer run test:unit`.

- *`Class "OCP\AppFramework\Db\QBMapper" not found`*, from 38 of 135 tests. The app's
  `tests/bootstrap.php` loaded only the app's autoloader and the `nextcloud/ocp`
  stubs, and the workflow had just removed the stubs. Fix: load the server's
  bootstrap first when it is there, and keep the stubs as the fallback for
  standalone runs:

  ```php
  $serverBootstrap = __DIR__ . '/../../../tests/bootstrap.php';
  if (is_file($serverBootstrap)) {
  	require_once $serverBootstrap;
  }
  ```

- *`Undefined constant Doctrine\DBAL\Types\Types::NUMBER`* from `occ app:enable`.
  `doctrine/dbal` was in the app's `require-dev` only so Psalm could resolve
  `Doctrine\DBAL\Schema\Table` in migrations. Installed with dev dependencies, the
  app's `vendor/autoload.php` (which the app's `Application` requires) loaded that
  DBAL over the server's own copy, a different major version. Release builds use
  `--no-dev`, which is why nobody had noticed. Fix: move it into the Psalm tool
  namespace and point Psalm at it:

  ```sh
  composer remove --dev doctrine/dbal
  composer bin psalm require --dev 'doctrine/dbal:^4.2'
  ```
  ```xml
  <extraFiles>
  	<directory name="vendor"/>
  	<directory name="vendor-bin/psalm/vendor/doctrine/dbal/src"/>
  </extraFiles>
  ```

  Check the standalone test run afterwards, because DBAL may have had a second job.
  The `nextcloud/ocp` stubs define `IQueryBuilder::PARAM_*` as
  `Doctrine\DBAL\ParameterType` constants, so any test that mocks a query builder
  without a server needs DBAL too (16 tests failed with `Class
  "Doctrine\DBAL\ParameterType" not found`). Give PHPUnit's namespace its own copy as
  well: `composer bin phpunit require --dev 'doctrine/dbal:^4.2'`. The PHPUnit
  binary loads that namespace's autoloader itself. Inside a server checkout the
  server's DBAL still wins, because its autoloader registers later and Composer
  prepends. (Verified: `ParameterType` resolved to `<server>/3rdparty/doctrine/dbal`.)

  The general rule: **a dev tool's dependency goes in its `vendor-bin` namespace,
  never in the app's `composer.json`, if the server ships that library too.**

**Verifying without pushing.** Reproduce the workflow locally: clone the server
branch, copy in its `3rdparty/`, put the app at `apps/<app>`, run
`composer remove nextcloud/ocp --dev --no-scripts && composer install` in the app,
then in a PHP image with the server's extensions (e.g.
`ghcr.io/nextcloud/nextcloud-dev-php83`) run `occ maintenance:install
--database=sqlite …`, `occ app:enable --force <app>` and `composer run test:unit`.
Docker Desktop cannot mount arbitrary paths like `/tmp`, so stream the tree in with
`tar -cf - . | docker run -i … tar -x`. Then check the job log for the test count,
not just the tick.

### 2026-10-28 — Review: retired templates, owner guards, and what a naive sync breaks

A review of this guide found that it lagged upstream in four ways. Three of the
upstream changes were months old when the guide was written; checking only the
current template *contents*, not their *names* and job conditions, is how they were
missed.

- **`node.yml` was renamed to `npm-build.yml`** (2026-05-16). The old name is now a
  stub that fails with "please switch to npm-build.yml".
- **`update-nextcloud-ocp-approve-merge.yml` was retired** (2026-09-16). Approve and
  auto-merge moved into the scheduled workflows themselves, and the old name is a
  stub that fails on every PR with "please remove this file".
- **`update-nextcloud-ocp-matrix.yml` gained a job-level owner guard** (2026-06-15,
  `repository_owner == 'nextcloud'`). Outside the org a synced copy skips silently,
  and the `ocp` bump PRs just stop.
- **`app_template` now ships `.yml.patch` files** (`appstore-build-publish.yml.patch`),
  which the first version of the audit script reported as `local` workflows.

**What a naive full sync does to an app that predates these changes** (copy every
template over its existing file, as the manual update script does): CI goes red twice,
once from the `node.yml` stub and once from the approve-merge stub, and outside the org
the `ocp` bump PRs stop without any failure. So:

1. `git mv .github/workflows/node.yml .github/workflows/npm-build.yml`
2. Sync, including `update-nextcloud-ocp-matrix.yml`.
3. Outside the org: add `update-nextcloud-ocp-matrix.yml.patch` removing the owner
   guard. Then decide how bot PRs get merged: either turn on the repo settings the
   approve/auto-merge steps need, or remove those steps in the same patch (and in an
   `npm-audit-fix.yml.patch`). With the settings off, the approve step fails
   every run.
4. Delete `update-nextcloud-ocp-approve-merge.yml` in the same change as step 2,
   since its old copy did the approving until then.
5. Run the audit: no `RETIRED`, no `GUARD`.

**Lesson for audits:** besides diffing contents, check each template's `name:` for
`No-op` and each job's `if:` for an owner. Both turn a sync into a silent change of
behaviour. The audit script now does both. It also stopped treating a failed request as
"no such template": a transient API error had reported a retired template as `local`.
Now only a 404 means `local`, and anything else is `ERROR`.

# Nextcloud Dev Environment: Configuration, Maintenance and Release Tracking

How the `nextcloud-docker-dev` setup decides what version it is running, what has to be
pulled by hand to keep it current, and what app developers need to know about the
versions they are testing against — so nobody has to reverse-engineer it from a
surprising toast notification again.

- **Applies to:** a `nextcloud-docker-dev` checkout driving one or more Nextcloud
  instances from local git worktrees
- **Assumes:** Docker Compose, code mounted from `workspace/`, apps developed in
  `apps-extra/`
- **Audience:** the environment maintainer (all sections) and app developers
  ([Part 4](#part-4--what-app-developers-need-to-know) onwards)

---

## The one thing to understand first

> **Nothing in this environment updates itself. The version *is* the git commit you
> have checked out.**

There is no updater, no package manager and no release channel doing work on your
behalf. The Nextcloud version reported in the admin UI is read straight out of
`version.php` in whichever directory is bind-mounted into the container. If that
directory has not been pulled since July, you are running July's Nextcloud — whatever
the calendar says.

Four independent layers each carry a version, each updates by a different command, and
they drift apart silently.

| Layer | What pins it | How it updates | Cost of staleness |
| --- | --- | --- | --- |
| **Harness**<br>`nextcloud-docker-dev` | git HEAD of the clone | `git pull` | No container definition for new major versions; missing fixes to compose/bootstrap |
| **Container images**<br>`ghcr.io/nextcloud/nextcloud-dev-*` | `:latest` tag *as last pulled* | `make pull-installed` | Old PHP patch level, stale extensions; `:latest` is a lie until you re-pull |
| **Nextcloud server**<br>`workspace/server`, `workspace/stableNN` | git HEAD of each worktree | `git pull` **per worktree** | You are testing against code nobody ships any more |
| **Apps**<br>`apps-extra/*` | git HEAD per app, or nothing at all | `git pull` per app | App code out of step with the server it is mounted into |

The `:latest` row is the one people trust wrongly. A tag is a pointer resolved at pull
time; the image on disk stays frozen at whatever `:latest` meant the day you pulled it.
`docker compose up` will happily run a four-month-old `:latest` forever.

---

## Part 1 — How this environment is laid out

### The mapping from directory to instance

One clone of `nextcloud/server` backs every instance. Additional major versions are
**git worktrees** of that one clone, not separate clones — so all branches share a single
object store, and disk cost per extra version is one working tree.

```
nextcloud-docker-dev/
├── .env                       ← project name, paths, DB, ports, xdebug
├── docker-compose.yml         ← one service per instance; defines which dir is mounted
└── workspace/
    ├── server/                ← the real clone. Branch: master
    │   ├── .git/              ← the single object store, shared by all worktrees
    │   └── apps-extra/        ← apps mounted at /var/www/html/apps-extra
    └── stable34/              ← git worktree of ../server. Branch: stable34
        └── apps-extra/        ← worktrees of ../../server/apps-extra/<app>
```

Each compose service bind-mounts one of those directories to `/var/www/html`:

| Service | Hostname | Mounts | Image default |
| --- | --- | --- | --- |
| `nextcloud` | `nextcloud.local` | `${REPO_PATH_SERVER}` → `workspace/server` | `nextcloud-dev-php85` |
| `stable34` | `stable34.local` | `${STABLE_ROOT_PATH}/stable34` | `nextcloud-dev-php83` |
| `stableNN` | `stableNN.local` | `${STABLE_ROOT_PATH}/stableNN` | `nextcloud-dev-php83` |

The `nextcloud` service is conventionally "whatever `workspace/server` is checked out
to". It is **not** guaranteed to be master — it is guaranteed to be nothing at all. See
[Part 3](#part-3--worked-example-why-a-35-instance-offered-an-update-to-35).

### Reading your own configuration

Everything site-specific lives in `.env`. Read it before assuming any default:

```bash
cat .env                       # project name, paths, SQL flavour, ports, subnet
docker compose config          # .env fully resolved into the compose definition
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'
```

Three `.env` values have consequences worth knowing:

| Variable | Effect | Gotcha |
| --- | --- | --- |
| `COMPOSE_PROJECT_NAME` | Prefixes container **and volume** names | Named `master` by convention, unrelated to the git branch. `master-stable34-1` is not a contradiction. |
| `PHP_VERSION` | Overrides the image tag for **every** service at once | Unset is usually right: each service then takes its own sensible default (85 for `nextcloud`, 83 for the stable ones). Setting it globally forces one PHP onto instances that may not support it. |
| `STABLE_ROOT_PATH` | Where `stableNN` services look for code | Must be the `workspace/` directory itself, not `workspace/server` |

### The volume asymmetry — the trap in this layout

The `nextcloud` service stores `config/`, `data/` and `apps-writable/` in **named**
volumes. Every `stableNN` service stores them in **anonymous** volumes.

```bash
docker volume ls --format '{{.Name}}' | grep "^${COMPOSE_PROJECT_NAME}"
# master_config  master_data  master_apps-writable  master_mysql  master_redis
#   ↑ the nextcloud service only. The stable instances' volumes are unnamed hashes.

docker inspect master-stable34-1 \
  --format '{{range .Mounts}}{{.Type}} {{.Name}} -> {{.Destination}}{{"\n"}}{{end}}'
```

What this means in practice:

- **`docker compose down -v` destroys every instance's config and data**, stable
  instances included. They will re-run the installer on next start, with a fresh admin
  password and no app state.
- **`docker compose up --renew-anon-volumes` silently resets the stable instances only**,
  leaving `nextcloud` untouched — a confusing half-wipe.
- Anonymous volumes are **orphaned, not reused**, whenever a stable container is
  recreated from a changed service definition. They accumulate; `docker volume prune`
  reclaims them.

Treat stable instances as disposable. Never put state there you are not willing to
re-create, and reach for `docker compose down` (no `-v`) by default.

---

## Part 2 — How Nextcloud versions and releases actually work

### The branch model

| Ref | What it is | Moves |
| --- | --- | --- |
| `master` | The **next** major, in development | Constantly |
| `stableNN` | Maintenance branch for major NN | Backports only, until EOL |
| `vNN.M.P` (tag) | A published release | Never |
| `vNN.M.PrcX`, `…betaX` | Pre-releases | Never |

The critical consequence: **`master` is a moving target that changes identity.** When
major NN is released, upstream cuts `stableNN` and master immediately becomes NN+1 dev.
A checkout of master is only meaningful together with its date.

### The cadence

Nextcloud ships **a major every ~4 months**, supported for **12 months** with
**monthly maintenance releases** (second Thursday-ish; check the schedule, not this
document).

| Major | Released | EOL | Notes |
| --- | --- | --- | --- |
| 34 | 9 Jun 2026 | 8 Jun 2027 | Hub 26 Spring |
| 35 | 16 Sep 2026 | 15 Sep 2027 | Hub 26 Summer |
| 36 | TBA | TBA | Hub 27 Winter; currently `master` |

Authoritative sources — check these, do not rely on the table above:

- **Schedule and EOL dates:** <https://github.com/nextcloud/server/wiki/Maintenance-and-Release-Schedule>
- **What shipped:** <https://github.com/nextcloud/server/releases> and
  <https://nextcloud.com/changelog/>
- **Machine-readable, no browser:**
  ```bash
  git ls-remote --tags --refs https://github.com/nextcloud/server \
    | awk '{print $2}' | sed 's|refs/tags/||' \
    | grep -E '^v3[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -5
  ```

Because majors land every four months and live twelve, **three majors are supported at
any time**. An app declaring support for the current release will be expected to work on
two older ones.

### The version tuple — four components, and the fourth is the one that bites

`version.php` holds two different representations and they do not agree:

```php
$OC_Version = [35, 0, 0, 1];        // major, minor, patch, BUILD
$OC_VersionString = '35.0.0 dev';   // human label — lossy, drops the build
$OC_Channel = 'git';                // what the source thinks; config can override it
```

The fourth component is a **build counter**, not a patch number. It advances through the
development cycle and reaches a specific value at GA. Comparisons — including the
updater's — are made on the full tuple, never on the string.

| Build | Means |
| --- | --- |
| `35.0.0.**1**` | An early dev snapshot taken while master was still 35 |
| `35.0.0.**10**` | The released 35.0.0 |

So `35.0.0.1 < 35.0.0.10`: a dev build and the release it grew into both call themselves
"35.0.0", and the dev one is numerically **older**. This is the entire mechanism behind
the confusing update prompt in Part 3.

### Reading the version of anything

```bash
# a local checkout, without starting anything
grep -E 'OC_Version|OC_Channel' workspace/server/version.php

# a running instance, authoritative
docker exec -u www-data master-nextcloud-1 php occ status

# what the instance believes is available, and which channel it asked
docker exec -u www-data master-nextcloud-1 php occ config:list system \
  | grep -E 'updater.release.channel|"version"'
docker exec -u www-data master-nextcloud-1 php occ config:list core \
  | grep lastupdateResult

# upstream, without fetching
git ls-remote --heads https://github.com/nextcloud/server \
  'refs/heads/master' 'refs/heads/stable3*'
```

> **Anchor `ls-remote` patterns with `refs/heads/`.** A bare pattern matches any
> trailing path component, so `stable34` also returns every `backport/NNNNN/stable34`
> branch — hundreds of lines of noise. `refs/heads/stable34` matches the branch alone.

### How far behind am I?

`git status` cannot tell you — it compares against your last fetch, not against upstream.
Ask GitHub directly:

```bash
LOCAL=$(git -C workspace/server rev-parse HEAD)
gh api "repos/nextcloud/server/compare/${LOCAL}...master" \
   --jq '{behind_by_commits: .ahead_by}'
```

(`ahead_by` in that response is how far **upstream** is ahead of you. It saturates at
1000 — a result of exactly 1000 means "at least".)

---

## Part 3 — Worked example: why a 35 instance offered an update to 35

This is the symptom that prompted this guide, and it is worth keeping because every
part of the diagnosis generalises.

**Symptom.** The admin overview reports `Nextcloud Hub 26 Spring (35.0.0 dev)` and, in
the same viewport, a toast reading *"Nextcloud 35.0.0 is available."*

**Diagnosis.** Four facts, each cheap to check:

1. `workspace/server` was checked out from `master` on **5 Jul 2026** and never pulled.
2. On that date master was still 35-in-development: `$OC_Version = [35, 0, 0, 1]`.
3. Upstream has since cut `stable35`, **released 35.0.0 on 16 Sep 2026** as build
   `35.0.0.10`, and moved master on to `36.0.0 dev`.
4. The instance config sets `updater.release.channel = stable`, **overriding**
   `$OC_Channel = 'git'` in `version.php`. So `updatenotification` polls the stable
   channel and compares `35.0.0.1 < 35.0.0.10`.

The cached evidence sits in the database verbatim:

```
core lastupdateResult = {"version":"35.0.0.10","versionstring":"Nextcloud 35.0.0", …}
```

**Conclusion.** The toast is correct and harmless. It is not a bug, not a corrupted
install, and not a sign the instance is broken — it is an accurate report that a dev
snapshot predating GA is older than GA. The two "35.0.0"s in the screenshot are different
builds four months apart.

**The generalisable lesson:** a stale `master` checkout does not stay labelled "master".
It silently becomes an unmaintained pre-release of whatever major branched off it, and
starts being compared against that major's real releases.

### ⚠ Never click "Open updater" or "Download now"

The web updater and `updater.phar` are built to replace a release tarball in place. Here,
`/var/www/html` is a **bind-mounted git worktree**. Running the updater against it will
overwrite tracked files, leave the worktree in an inconsistent state, and can take the
shared object store down with it — destroying your other checked-out majors too.

There is no supported in-place upgrade in this environment. Every version change is a git
operation. To stop being asked:

```bash
# quietest option: tell the instance it is a git checkout, which is true
docker exec -u www-data master-nextcloud-1 php occ config:system:set \
  updater.release.channel --value="git"

# or just silence the notifier on a throwaway dev box
docker exec -u www-data master-nextcloud-1 php occ app:disable updatenotification
```

Prefer the first. It makes the config agree with reality instead of hiding the
disagreement, and it leaves app-update notifications working.

---

## Part 4 — Maintenance runbook

### 4.1 Routine: after each monthly patch release

Run this when the schedule says a patch shipped, or monthly regardless. Roughly ten
minutes including container restarts.

```bash
cd ~/Code/nextcloud-docker-dev

# 1. Harness
git pull

# 2. Images (only those already present; `make pull-all` grabs everything)
make pull-installed

# 3. Server code — ONE PULL PER WORKTREE. See the refspec warning below.
git -C workspace/server pull
cd workspace/stable34 && git pull origin stable34 && cd -

# 4. Submodules, in every worktree that moved
git -C workspace/server submodule update --init
git -C workspace/stable34 submodule update --init

# 5. Apps you track from upstream
for d in workspace/server/apps-extra/*/; do
  [ -e "$d/.git" ] && git -C "$d" pull
done

# 6. Recreate containers so the new images are used, then migrate
docker compose up -d nextcloud stable34
docker compose exec -u www-data nextcloud php occ upgrade
docker compose exec -u www-data stable34 php occ upgrade
```

`occ upgrade` exits cleanly and does nothing when no migration is pending, so it is safe
to run unconditionally. Step 6 needs `up -d`, not `restart`: `restart` reuses the running
container and therefore the old image.

> **⚠ The fetch refspec is narrowed to master.** `bootstrap.sh` configures the server
> clone with `remote.origin.fetch = +refs/heads/master:refs/remotes/origin/master`, so a
> bare `git fetch` in `workspace/server` **only ever sees master**. Stable branches have
> no upstream tracking, and `git pull` with no arguments fails in those worktrees.
> Always name the remote and branch: `git pull origin stable34`, run **from inside** the
> worktree. Fetching into a checked-out branch from elsewhere
> (`git fetch origin stable34:stable34`) is refused by git while that branch is checked
> out in a worktree.
>
> To widen it permanently, so ordinary `git fetch` covers every branch:
> ```bash
> git -C workspace/server config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
> ```

### 4.2 Rollover: adding a new major version

Do this twice a year, when a new major is released. Two independent jobs: **add a
worktree for the version that just shipped**, and **let `master` move on**.

```bash
cd ~/Code/nextcloud-docker-dev

# 1. The harness must know the new service exists. Upstream adds a `stableNN`
#    service to docker-compose.yml and extends bootstrap.sh — you get it by pulling.
git pull
grep -n '^  stable35:' docker-compose.yml     # confirm the service landed

# 2. New worktree for the released major
cd workspace/server
git fetch origin stable35:stable35            # safe: not yet checked out anywhere
git worktree add ../stable35 stable35
git -C ../stable35 submodule update --init

# 3. Worktrees for each app that has a matching stable branch
cd apps-extra/viewer
git worktree add ../../../stable35/apps-extra/viewer stable35

# 4. DNS for the new hostname — it is NOT added by `git pull`
cd ~/Code/nextcloud-docker-dev
./scripts/update-hosts                        # adds stable35.local; needs sudo
grep stable35 /etc/hosts

# 5. Start it
docker compose up -d stable35                 # → http://stable35.local

# 6. Let master become the new dev branch
git -C workspace/server pull                  # master is now NN+1 dev
docker compose up -d nextcloud
docker compose exec -u www-data nextcloud php occ upgrade
```

Step 6 is the one that gets skipped, and skipping it is what produces the Part 3
symptom. **Pulling master after a major release is not optional** — it is the act that
stops your "master" instance from being a stale pre-release.

Step 4 is the other easy miss: hostnames come from `/etc/hosts`, which `git pull` does
not touch. A new `stableNN.local` resolves nowhere until `update-hosts` runs.

Retire the oldest worktree at the same time, once its major is EOL:

```bash
git -C workspace/server worktree remove ../stable32
docker compose rm -sf stable32
docker volume prune       # reclaims its orphaned anonymous volumes
```

### 4.3 Shallow clones

`bootstrap.sh` clones `--depth 1` by default. `git log`, `git bisect`, `git blame` and
comparisons against tags are all unusable on a shallow clone, and it is the default
nobody notices until they need history.

```bash
test -f workspace/server/.git/shallow && echo "SHALLOW — history truncated"

# fix, once, when you can spare the bandwidth (also widen the refspec, above)
./scripts/download-full-history.sh
```

New environments: `./bootstrap.sh --full-clone`, or `--clone-no-blobs` for full history
without the blob download.

### 4.4 Health check

Answers "what am I actually running?" without starting or changing anything.

```bash
#!/usr/bin/env bash
# nc-env-status.sh — read-only. Run from the nextcloud-docker-dev root.
set -uo pipefail

echo "=== harness ==="
git log -1 --format='%h %ci %s'
LOCAL=$(git rev-parse HEAD)
gh api "repos/nextcloud/nextcloud-docker-dev/compare/${LOCAL}...master" \
   --jq '"commits behind upstream: \(.ahead_by)"' 2>/dev/null \
   || echo "commits behind upstream: (gh unavailable)"

echo; echo "=== checkouts ==="
for d in workspace/*/; do
  [ -e "$d/version.php" ] || continue
  printf '%-28s %-10s %-24s %s\n' \
    "$(basename "$d")" \
    "$(git -C "$d" branch --show-current)" \
    "$(git -C "$d" log -1 --format='%h %cs')" \
    "$(grep -oE "OC_VersionString = '[^']+'" "$d/version.php" | cut -d"'" -f2)"
  [ -f "$d/.git/shallow" ] && echo "    ⚠ shallow clone — history truncated"
done

echo; echo "=== upstream heads ==="
git ls-remote --heads https://github.com/nextcloud/server \
  'refs/heads/master' 'refs/heads/stable3*' | sed 's|refs/heads/||'

echo; echo "=== latest releases ==="
git ls-remote --tags --refs https://github.com/nextcloud/server \
  | awk '{print $2}' | sed 's|refs/tags/||' \
  | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -4

echo; echo "=== images (age = when YOU last pulled :latest) ==="
docker images --format '{{.Repository}}:{{.Tag}}\t{{.CreatedSince}}' \
  | grep -E 'nextcloud-dev|mariadb|redis'

echo; echo "=== running ==="
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'
```

---

## Part 5 — What app developers need to know

### 5.1 The version you are testing against is not the version users run

Your `nextcloud.local` instance is a git checkout that is exactly as current as the last
`git pull`. Before filing "works on my machine" or chasing a behaviour change, confirm
what you are actually on:

```bash
docker exec -u www-data master-nextcloud-1 php occ status
```

A dev build is **not** the release it is named after. Code merged after your checkout
date is absent; code reverted before GA may still be present. Behaviour differences
between your `35.0.0 dev` and a user's `35.0.0` are expected, not anomalies.

### 5.2 Declare a version range, then actually test the ends of it

`appinfo/info.xml` declares the supported range:

```xml
<dependencies>
    <nextcloud min-version="33" max-version="35"/>
</dependencies>
```

Nextcloud refuses to enable an app outside that range, and the app store will not offer
it to instances outside it. Three majors are supported at once, so a range of three is
normal — and it means **three instances to test on**, which is what the `stableNN`
containers are for.

| | Where | Test |
| --- | --- | --- |
| `min-version` | oldest `stableNN` worktree | Your floor still works |
| middle | the other `stableNN` | The version most users are on |
| `max-version` | `nextcloud.local` (master) | You are not about to be broken by the next major |

Bump `max-version` only after testing against that major, and publish a release that
declares it. Until you do, the app store correctly reports the app as incompatible.

### 5.3 "N apps have no compatible version" is about the store, not your code

The admin overview lists apps for which **the app store has no published release**
matching the target version. It says nothing about the code on disk. A locally-mounted
app can declare `max-version="35"` and work perfectly while still appearing in that list,
because the store has no 35-compatible *release* of it — normal and expected for
unpublished or in-development apps.

Check the two facts separately:

```bash
# what each app's code claims — print the app name, not just the bare tag
for f in workspace/server/apps-extra/*/appinfo/info.xml; do
  printf '%-22s %s\n' "$(basename "$(dirname "$(dirname "$f")")")" \
    "$(grep -o '<nextcloud[^>]*>' "$f" | head -1)"
done

# what the instance actually enabled
docker exec -u www-data master-nextcloud-1 php occ app:list
```

Read that listing against the instance's major. An app whose `max-version` is below it
cannot be enabled at all — that is a local blocker you fix by testing and bumping the
range, and it is a different problem from the store-compatibility message above.

### 5.4 PHP floor moves with the major

The server enforces a minimum and an upper bound at runtime, and both move. Read them
from the checkout rather than assuming:

```bash
grep -A2 'PHP_VERSION_ID' workspace/server/lib/versioncheck.php
```

| Nextcloud | PHP | Default dev image |
| --- | --- | --- |
| 34 | 8.2 – 8.5 | `nextcloud-dev-php83` |
| 35 | 8.3 – 8.5 | `nextcloud-dev-php85` |

If your app supports a range of majors, its PHP floor is the **lowest** in that range —
but your syntax must also parse on the highest. Testing only on `nextcloud.local`
(PHP 8.5) will not catch an 8.2 incompatibility; that is what the stable containers are
for. Override per-run with `PHP_VERSION=84 docker compose up -d nextcloud` rather than
editing `.env`, which would move every service at once.

### 5.5 Keep one copy of your app, mounted many times

An app checked out once and exposed to several majors via **git worktrees** has one
history and one source of truth. An app that exists as two independently-edited copies
under `workspace/server/apps-extra/` and `workspace/stable34/apps-extra/` has neither:
the copies diverge, and nothing tells you when.

```bash
# is this app a real checkout, or a loose copy?
for d in workspace/server/apps-extra/*/; do
  printf '%-40s %s\n' "$d" \
    "$([ -e "$d/.git" ] && git -C "$d" branch --show-current || echo '⚠ NOT A GIT CHECKOUT')"
done

# do the two trees actually agree?
diff -rq --exclude=.git \
  workspace/server/apps-extra/myapp \
  workspace/stable34/apps-extra/myapp
```

For an app that supports several majors from one branch, the simplest fix is to stop
duplicating it: put it once in `ADDITIONAL_APPS_PATH` (set in `.env`) and let every
container mount it at `/var/www/html/apps-shared`. One directory, one copy, all
instances — and no divergence to detect.

For an app with real per-major branches, use worktrees, exactly as the server does:

```bash
cd workspace/server/apps-extra/myapp
git worktree add ../../../stable34/apps-extra/myapp stable34
```

---

## Checklist

**Monthly** — or whenever the schedule says a patch shipped:

- [ ] `git pull` in `nextcloud-docker-dev`
- [ ] `make pull-installed`
- [ ] `git pull` in **every** `workspace/*` worktree (name the branch for stable ones)
- [ ] `git submodule update --init` in each worktree that moved
- [ ] `docker compose up -d <services>` — `up -d`, not `restart`
- [ ] `occ upgrade` on each instance
- [ ] Skim the changelog for the majors you support

**At every major release** — twice a year, non-negotiable:

- [ ] `git pull` the harness first; confirm the new `stableNN` service exists in
      `docker-compose.yml`
- [ ] Create the `stableNN` worktree for the version that just shipped, plus app
      worktrees
- [ ] `./scripts/update-hosts` for the new hostname
- [ ] **Pull `master`** so it becomes the new dev major — the step that prevents the
      Part 3 symptom
- [ ] Retire the worktree and container for the major that just hit EOL
- [ ] Review every app's `max-version` against the new release

**Never:**

- [ ] Run the web updater or `updater.phar` against a bind-mounted git worktree
- [ ] `docker compose down -v` unless you intend to wipe **every** instance's config
- [ ] Trust `:latest` to be latest without pulling
- [ ] Trust `git status` to tell you how far behind upstream you are

---

## Field notes

Findings from this environment. Add to it rather than rediscovering.

**A stale `master` checkout changes identity without telling you.** It does not stay
"master" — it becomes an unmaintained pre-release of whatever major branched off it, and
starts being compared against that major's real releases. The dev build number is lower
than GA's, so the instance correctly reports an update to a version it appears to already
be. Pulling master right after a major release is the cheapest possible prevention.

**`$OC_Channel` in `version.php` is not the channel in use.** The source ships
`'git'`, but `updater.release.channel` in the instance config overrides it, and the
bootstrap leaves it at `stable`. Anything reasoning about update behaviour must read the
config, not the file.

**The server clone only fetches master.** `bootstrap.sh` narrows
`remote.origin.fetch` to a single branch, so bare `git fetch` never sees stable branches
and stable worktrees have no upstream tracking. `git pull` with no arguments fails there.
This is invisible until the first time you try to update a stable worktree the obvious
way.

**Stable instances keep config in anonymous volumes; the main one does not.** The
asymmetry means `down -v` and `--renew-anon-volumes` have very different blast radii
depending on which instance you were thinking about. Nothing in the UI hints at it.

**`docker compose restart` does not adopt a newly pulled image.** It restarts the
existing container, which is still built on the old image. `up -d` recreates it. A
"pulled but nothing changed" report is almost always this.

**Shallow by default.** `--depth 1` is `bootstrap.sh`'s default and it is a cost you pay
much later, the first time you need `git bisect` on a regression. Worth undoing early.

**Two copies of an app are not a branching strategy.** Duplicated app directories across
`server/apps-extra` and `stableNN/apps-extra` look identical on the day they are made and
drift from then on, with no signal. Either one shared copy via `ADDITIONAL_APPS_PATH`, or
real worktrees — not both trees edited by hand.

---

Verified against a live setup on 19 Sep 2026: `nextcloud-docker-dev` at `df4ca69`,
`workspace/server` at `3a64d4a` (`35.0.0 dev`, build `35.0.0.1`), `workspace/stable34` at
`cf73e9f` (`34.0.1`), against upstream `nextcloud/server` master (`36.0.0 dev`),
`stable34` (`34.0.4`) and the released `v35.0.0` (build `35.0.0.10`). Schedule figures
from the server wiki's Maintenance and Release Schedule; where it and this document
disagree, the wiki is right.

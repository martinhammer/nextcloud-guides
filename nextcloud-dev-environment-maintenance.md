# Nextcloud Dev Environment: Configuration, Maintenance and Release Tracking

What each container in the `nextcloud-docker-dev` zoo is for, how the setup decides
which Nextcloud version it is running, and what has to be pulled by hand to keep it
current.

- **Applies to:** a `nextcloud-docker-dev` checkout driving one or more Nextcloud
  instances from local git worktrees
- **Assumes:** Docker Compose, code mounted from `workspace/`, apps developed in
  `apps-extra/`
- **Audience:** the environment maintainer (all sections) and app developers
  ([Part 5](#part-5--what-app-developers-need-to-know) onwards)

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

## Part 1 — The container zoo

### 1.1 Why only six containers are running out of sixty services

`docker-compose.yml` defines around sixty services — Collabora, OnlyOffice,
Elasticsearch, Keycloak, LDAP, Talk, S3, ClamAV, three globalscale nodes, five database
flavours. **Almost none of them run.** Compose starts a service only when you name it or
when something you named depends on it:

```bash
docker compose config --services | wc -l       # everything defined
docker compose ps --services                   # what is actually up
```

`docker compose up -d nextcloud` brings up six containers because the `nextcloud`
service declares `depends_on: [database-mysql, redis, mail, proxy]`. Everything else
stays dormant until explicitly requested. So the zoo is a **menu, not a manifest** —
read `docker ps`, never the compose file, to know what you are running.

This is also why the file is safe to leave alone. A service for a tool you never use
costs nothing.

### 1.2 What each running container is for

A default setup with one dev instance and one stable instance:

| Container | Image | Role | Per-instance or shared? |
| --- | --- | --- | --- |
| `<project>-nextcloud-1` | `nextcloud-dev-php85` | Apache + PHP serving `workspace/server` | **Per instance** |
| `<project>-stable34-1` | `nextcloud-dev-php83` | Apache + PHP serving `workspace/stable34` | **Per instance** |
| `<project>-proxy-1` | `nginx-proxy` | Hostname-based routing; owns host `:80`/`:443` | Shared |
| `<project>-database-mysql-1` | `mariadb:10.6` | **One DB server, one database per instance** | Shared |
| `<project>-redis-1` | `redis:8` | Cache + file locking | Shared |
| `<project>-mail-1` | `nextcloud-dev-mailhog` | Catches all outbound mail | Shared |

Only the Nextcloud containers multiply. Adding `stable35` adds exactly **one** container
— it joins the existing database, Redis, proxy and mail.

> **`<project>` comes from `COMPOSE_PROJECT_NAME` in `.env`, and by convention it is
> `master`.** That is a project label, not a git branch. Docker Desktop shows it as the
> collapsible parent row grouping the containers. `master-stable34-1` is not a
> contradiction — it is "the `stable34` container of the project named `master`".

### 1.3 One database container, one database per instance

The single MariaDB container holds a separate database per Nextcloud instance:

```console
$ docker exec <project>-database-mysql-1 mysql -uroot -pnextcloud -e 'SHOW DATABASES;'
Database
information_schema
mysql
nextcloud            ← the `nextcloud` service  (nextcloud.local)
performance_schema
stable34             ← the `stable34` service   (stable34.local)
sys
```

The name is derived in the container's bootstrap from the hostname, not configured
anywhere you would think to look:

```bash
DBNAME=$(echo "$VIRTUAL_HOST" | cut -d '.' -f1)     # docker/bin/bootstrap.sh
```

So `VIRTUAL_HOST=stable34.local` → database `stable34`. Everything connects as
`root`/`nextcloud` to host `database-mysql`.

Three consequences worth holding:

- **Instances are isolated at the schema level, not the server level.** A migration that
  goes wrong on `stable34` cannot corrupt `nextcloud`, but one `mysqldump --all-databases`
  backs up every instance at once — and one `docker volume rm <project>_mysql` destroys
  every instance at once.
- **The database survives container recreation** — it lives in the named volume
  `<project>_mysql`, not in the container.
- **A reinstall does not drop the old database.** Databases from majors you have since
  retired sit there indefinitely. Harmless, but they are why `SHOW DATABASES` accumulates
  names you no longer recognise.

Useful entry points:

```bash
# the repo's own helper
./scripts/mysql.sh

# from the host — PORTBASE+2; with PORTBASE=821 that is 8212
mysql -h 127.0.0.1 -P 8212 -uroot -pnextcloud stable34

# a web UI, if you want one
docker compose up -d phpmyadmin     # → http://phpmyadmin.local
```

Switching `SQL=` in `.env` from `mysql` to `pgsql` points **new installs** at a different
database *container*; it does not migrate anything. Existing instances keep the `dbtype`
recorded in their own config until reinstalled.

### 1.4 One Redis, shared safely

Every instance is configured identically — `host: redis, port: 6379`, no `dbindex`, no
per-instance prefix:

```php
// docker/.../redis.config.php, copied into config/ at install time
'redis' => ['host' => 'redis', 'port' => 6379],
'memcache.local'   => '\OC\Memcache\Redis',
'memcache.locking' => '\OC\Memcache\Redis',
```

They do not collide, because Nextcloud namespaces every cache key by `instanceid`.
From `lib/private/Memcache/Factory.php`:

```php
// Include instanceid in the prefix, in case multiple instances use the same cache
$this->globalPrefix = $customprefix . hash('xxh128', $instanceid . $installedApps);
```

Each instance generates its own `instanceid` at install time, so the prefixes differ:

```bash
docker exec -u www-data <project>-nextcloud-1 php occ config:system:get instanceid
docker exec -u www-data <project>-stable34-1  php occ config:system:get instanceid
```

Two practical notes. **Flushing Redis hits every instance** (`docker exec
<project>-redis-1 redis-cli FLUSHALL`) — usually fine on a dev box, but it clears file
locks and caches for majors you were not debugging. And because the prefix includes the
installed-app set, **enabling or disabling an app invalidates that instance's cache
wholesale**, which is the usual explanation for a one-off slow page load after touching
apps.

### 1.5 The proxy: how a hostname reaches the right container

`nginx-proxy` watches the Docker socket, reads the `VIRTUAL_HOST` environment variable
off each running container, and generates a vhost for it. Nothing routes by port.

```
browser → 127.0.0.1:80 → proxy container → VIRTUAL_HOST match → instance container
```

| Hostname | Set by | Reaches |
| --- | --- | --- |
| `nextcloud.local` | `VIRTUAL_HOST` on the `nextcloud` service | `workspace/server` |
| `stable34.local` | `VIRTUAL_HOST` on the `stable34` service | `workspace/stable34` |
| `mail.local` | `VIRTUAL_HOST` on `mail` (port 8025) | MailHog inbox |

Two things must line up, and only one of them comes from `git pull`:

1. The compose service must exist and carry a `VIRTUAL_HOST` — that comes from the repo.
2. **The hostname must resolve on your machine** — that comes from `/etc/hosts`, which
   `git pull` never touches. `./scripts/update-hosts` adds every alias it finds in
   `docker-compose.yml`, pointing them at `127.0.0.1`.

A brand-new `stableNN.local` will not resolve until `update-hosts` has run. The failure
mode is a plain DNS error in the browser, with no hint that a container is up and waiting.

`DOMAIN_SUFFIX` in `.env` controls the `.local` part. `PROTOCOL=http` keeps the proxy off
TLS; switching to `https` needs certificates in `data/ssl/` — see `docs/basics/ssl.md`.

### 1.6 Host ports

Only the proxy and a few debugging services publish ports. `PORTBASE` in `.env` offsets
them so several complete setups can coexist on one machine.

| Host port | Service | With `PORTBASE=821` |
| --- | --- | --- |
| `80`, `443` | `proxy` | fixed, not offset |
| `PORTBASE`+1 | `nextcloud2` (direct, bypassing proxy) | 8211 |
| `PORTBASE`+2 | `database-mysql` **or** `database-pgsql` | 8212 |
| `PORTBASE`+8 | `ldapadmin` | 8218 |

Everything binds to `127.0.0.1` unless `IP_BIND` says otherwise — the setup uses default
passwords throughout and is not safe to expose.

> **MySQL and PostgreSQL both claim `PORTBASE`+2.** They cannot both publish at once; the
> second to start fails to bind. Only a problem if you deliberately run two database
> flavours side by side.

To run a second independent environment, give it its own `COMPOSE_PROJECT_NAME`,
`PORTBASE` **and** `DOCKER_SUBNET`. All three must differ or the two setups will fight
over container names, host ports and IP ranges.

### 1.7 Where state actually lives

Three storage mechanisms, with very different durability. Knowing which is which tells
you what a given command will destroy.

The column that matters is the middle one: **stopping is not the same as removing, and
removing a container is not the same as removing its volume.**

| What | Mechanism | `stop`/`start` | `down` then `up` | `down -v` |
| --- | --- | --- | --- | --- |
| Server + app **code** | bind mount from `workspace/` | ✅ | ✅ it is your git worktree | ✅ untouched |
| Databases | named volume `<project>_mysql` | ✅ | ✅ | ❌ **all instances** |
| `nextcloud` config/data/apps-writable | named volumes `<project>_config`, `_data`, … | ✅ | ✅ | ❌ |
| `stableNN` config/data/apps-writable | **anonymous** volumes | ✅ | ❌ **orphaned** | ❌ |

That last cell is the one nobody expects, and it is not a `-v` problem. A named volume is
looked up by name, so a rebuilt container reattaches to it. An anonymous volume is
identified only by its attachment to a container — remove the container and the link is
gone. `up` then creates a **new, empty** anonymous volume, and the old one survives on
disk as an unreferenced orphan holding data nothing can reach.

So `docker compose down && docker compose up -d` silently re-runs the installer on every
`stableNN` instance while leaving `nextcloud` and the databases perfectly intact.

```bash
docker volume ls --format '{{.Name}}' | grep "^${COMPOSE_PROJECT_NAME}"
# master_config  master_data  master_apps-writable  master_mysql  master_redis
#   ↑ the nextcloud service only — the stable instances' volumes are unnamed hashes

docker inspect <project>-stable34-1 \
  --format '{{range .Mounts}}{{.Type}} {{.Name}} -> {{.Destination}}{{"\n"}}{{end}}'
```

The asymmetry between the last two rows is the trap in this layout:

- **`docker compose down -v` destroys every instance's config and data**, stable
  instances included, plus the databases. Your code is safe — it is a bind mount — but
  everything else goes.
- **`docker compose down` (no `-v`) still resets the stable instances**, for the reason
  above. Harmless if you treat them as disposable; surprising if you assumed `-v` was the
  only destructive form.
- **`docker compose up --renew-anon-volumes` resets the stable instances only**, leaving
  `nextcloud` untouched. A confusing half-wipe.
- Orphaned anonymous volumes accumulate with every such cycle. `docker volume ls -qf
  dangling=true | wc -l` counts them; `docker volume prune` reclaims the space.

Treat stable instances as disposable. Nothing you cannot re-create belongs on one.

### Which button does what

Docker Desktop's project-row controls map onto compose verbs that are **weaker** than
`down` — they stop containers without removing them, so nothing above is at risk:

| Docker Desktop (project row) | Compose equivalent | Containers | Anonymous volumes |
| --- | --- | --- | --- |
| **Stop** ⏹ | `docker compose stop` | kept, `Exited` | kept — same container, same volume |
| **Play** ▶ | `docker compose start` | the **same** containers resume | kept |
| **Delete** 🗑 | `docker compose down` | removed | ❌ orphaned |

Stop/Play is therefore the safest way to park the environment, and the right default for
day-to-day use.

It has one cost, and it is the same trap as `restart`: **`start` resumes the existing
container, so it can never pick up a newly pulled image.** After `make pull-installed`,
the Play button will keep running the old image indefinitely, reporting no error. Only
`docker compose up -d` recreates containers against the new image — which is why the
runbook in Part 4 ends with `up -d` rather than a restart.

Note that user files live in a volume at `/var/www/html/data`, **not** in the git
worktree — which is why uploading test files never dirties `git status`.

### 1.8 Everyday commands

```bash
# start / stop
docker compose up -d nextcloud stable34  # creates or recreates; adopts new images
docker compose stop                      # = Docker Desktop's Stop. Safest park.
docker compose start                     # = Docker Desktop's Play. Keeps the old image.
docker compose down                      # removes containers; ⚠ resets stableNN instances
docker compose down -v                   # ⚠ wipes every instance's DB, config, data

# occ, the tool you will use most
docker compose exec -u www-data nextcloud php occ status
./scripts/occ.sh status                  # same thing, repo helper

# logs
docker compose logs -f nextcloud         # container/apache
docker compose exec nextcloud tail -f /var/www/html/data/nextcloud.log

# shell
docker compose exec -u www-data nextcloud bash
```

Always `-u www-data`. Running `occ` as root writes root-owned files into the bind-mounted
worktree, and the web server then cannot read them.

**Use `up -d` after pulling images — not `restart`, and not Docker Desktop's Play
button.** All three of `restart`, `start` and Play reuse the existing container, and
therefore the old image. Only `up -d` recreates it against the new one.

---

## Part 2 — Code layout: which directory feeds which container

### 2.1 The worktree model

One clone of `nextcloud/server` backs every instance. Additional majors are **git
worktrees** of that one clone, not separate clones — all branches share a single object
store, so the disk cost of an extra version is one working tree.

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

| Service | Hostname | Mounts | Image default |
| --- | --- | --- | --- |
| `nextcloud` | `nextcloud.local` | `${REPO_PATH_SERVER}` → `workspace/server` | `nextcloud-dev-php85` |
| `stableNN` | `stableNN.local` | `${STABLE_ROOT_PATH}/stableNN` | `nextcloud-dev-php83` |

The `nextcloud` service is conventionally "whatever `workspace/server` is checked out
to". It is **not** guaranteed to be master — it is guaranteed to be nothing at all, which
is the root of the stale-master problem in the field notes.

### 2.2 The `.env` values with consequences

```bash
cat .env               # site-specific settings
docker compose config  # .env fully resolved into the compose definition
```

| Variable | Effect | Gotcha |
| --- | --- | --- |
| `COMPOSE_PROJECT_NAME` | Prefixes container **and volume** names | Conventionally `master`; unrelated to any git branch |
| `PHP_VERSION` | Overrides the image tag for **every** service at once | Unset is usually right — each service then takes its own default (85 for `nextcloud`, 83 for stable). Setting it globally forces one PHP onto instances that may not support it. |
| `STABLE_ROOT_PATH` | Where `stableNN` services look for code | Must be `workspace/`, not `workspace/server` |
| `PORTBASE`, `DOCKER_SUBNET` | Host ports and container network | Must both differ between parallel setups |
| `SQL` | Which database container new installs target | Does not migrate existing instances |

---

## Part 3 — How Nextcloud versions and releases work

### 3.1 The branch model

| Ref | What it is | Moves |
| --- | --- | --- |
| `master` | The **next** major, in development | Constantly |
| `stableNN` | Maintenance branch for major NN | Backports only, until EOL |
| `vNN.M.P` (tag) | A published release | Never |
| `vNN.M.PrcX`, `…betaX` | Pre-releases | Never |

The critical consequence: **`master` is a moving target that changes identity.** When
major NN is released, upstream cuts `stableNN` and master immediately becomes NN+1 dev.
A checkout of master is only meaningful together with its date.

### 3.2 The cadence

Nextcloud ships **a major every ~4 months**, supported for **12 months** with **monthly
maintenance releases**.

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

### 3.3 The version tuple — four components, and the fourth is the one that bites

`version.php` holds two representations and they do not agree:

```php
$OC_Version = [35, 0, 0, 1];        // major, minor, patch, BUILD
$OC_VersionString = '35.0.0 dev';   // human label — lossy, drops the build
$OC_Channel = 'git';                // what the source thinks; config can override it
```

The fourth component is a **build counter**, not a patch number. It advances through the
development cycle and reaches a specific value at GA. Comparisons — including the
updater's — use the full tuple, never the string.

| Build | Means |
| --- | --- |
| `35.0.0.**1**` | An early dev snapshot taken while master was still 35 |
| `35.0.0.**10**` | The released 35.0.0 |

So `35.0.0.1 < 35.0.0.10`: a dev build and the release it grew into both call themselves
"35.0.0", and the dev one is numerically **older**. See the field note on stale master
checkouts for what this does in practice.

### 3.4 Reading the version of anything

```bash
# a local checkout, without starting anything
grep -E 'OC_Version|OC_Channel' workspace/server/version.php

# a running instance, authoritative
docker exec -u www-data <project>-nextcloud-1 php occ status

# what the instance believes is available, and which channel it asked
docker exec -u www-data <project>-nextcloud-1 php occ config:list system \
  | grep -E 'updater.release.channel|"version"'
docker exec -u www-data <project>-nextcloud-1 php occ config:list core \
  | grep lastupdateResult

# upstream, without fetching
git ls-remote --heads https://github.com/nextcloud/server \
  'refs/heads/master' 'refs/heads/stable3*'
```

> **Anchor `ls-remote` patterns with `refs/heads/`.** A bare pattern matches any trailing
> path component, so `stable34` also returns every `backport/NNNNN/stable34` branch —
> hundreds of lines of noise. `refs/heads/stable34` matches the branch alone.

### 3.5 How far behind am I?

`git status` cannot tell you — it compares against your last fetch, not against upstream.
Ask GitHub directly:

```bash
LOCAL=$(git -C workspace/server rev-parse HEAD)
gh api "repos/nextcloud/server/compare/${LOCAL}...master" \
   --jq '{behind_by_commits: .ahead_by}'
```

(`ahead_by` there is how far **upstream** is ahead of you. It saturates at 1000 — a
result of exactly 1000 means "at least".)

### 3.6 ⚠ Never run the web updater here

The web updater and `updater.phar` are built to replace a release tarball in place. Here,
`/var/www/html` is a **bind-mounted git worktree**. Running the updater against it will
overwrite tracked files, leave the worktree inconsistent, and can take the shared object
store down with it — destroying your other checked-out majors too.

There is no supported in-place upgrade in this environment. **Every version change is a
git operation.** To stop being offered one:

```bash
# quietest option: tell the instance it is a git checkout, which is true
docker exec -u www-data <project>-nextcloud-1 php occ config:system:set \
  updater.release.channel --value="git"

# or silence the notifier entirely on a throwaway dev box
docker exec -u www-data <project>-nextcloud-1 php occ app:disable updatenotification
```

Prefer the first: it makes the config agree with reality instead of hiding the
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
to run unconditionally. Step 6 needs `up -d`, not `restart`.

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

Twice a year, when a new major is released. Two independent jobs: **add a worktree for
the version that just shipped**, and **let `master` move on**.

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

# 5. Start it — one new container, joining the existing DB/Redis/proxy/mail
docker compose up -d stable35                 # → http://stable35.local

# 6. Let master become the new dev major
git -C workspace/server pull                  # master is now NN+1 dev
docker compose up -d nextcloud
docker compose exec -u www-data nextcloud php occ upgrade
```

Step 6 is the one that gets skipped, and skipping it is what produces the stale-master
symptom in the field notes. **Pulling master after a major release is not optional.**

Step 4 is the other easy miss: hostnames come from `/etc/hosts`, which `git pull` does
not touch. A new `stableNN.local` resolves nowhere until `update-hosts` runs.

The new instance creates its own database (`stable35`) on first start, from its
`VIRTUAL_HOST`. Nothing to provision by hand.

Retire the oldest worktree at the same time, once its major is EOL:

```bash
git -C workspace/server worktree remove ../stable32
docker compose rm -sf stable32
docker volume prune       # reclaims its orphaned anonymous volumes
# the stable32 database lingers in MariaDB; drop it if you care about the clutter
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

echo; echo "=== databases ==="
docker compose exec -T database-mysql \
  mysql -uroot -pnextcloud -e 'SHOW DATABASES;' 2>/dev/null \
  | grep -vE 'information_schema|performance_schema|^mysql$|^sys$|^Database$'
```

---

## Part 5 — What app developers need to know

### 5.1 The version you are testing against is not the version users run

Your `nextcloud.local` instance is a git checkout, exactly as current as the last
`git pull`. Before filing "works on my machine" or chasing a behaviour change, confirm
what you are actually on:

```bash
docker exec -u www-data <project>-nextcloud-1 php occ status
```

A dev build is **not** the release it is named after. Code merged after your checkout
date is absent; code reverted before GA may still be present. Differences between your
`35.0.0 dev` and a user's `35.0.0` are expected, not anomalies.

### 5.2 Declare a version range, then test the ends of it

`appinfo/info.xml` declares the supported range:

```xml
<dependencies>
    <nextcloud min-version="33" max-version="35"/>
</dependencies>
```

Nextcloud refuses to enable an app outside that range, and the app store will not offer
it to instances outside it. Three majors are supported at once, so a range of three is
normal — and that means **three instances to test on**, which is what the `stableNN`
containers are for. Each is one extra container sharing the same database server, so the
cost of keeping them around is low.

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
because the store has no 35-compatible *release* of it — normal for unpublished or
in-development apps.

Check the two facts separately:

```bash
# what each app's code claims — print the app name, not just the bare tag
for f in workspace/server/apps-extra/*/appinfo/info.xml; do
  printf '%-22s %s\n' "$(basename "$(dirname "$(dirname "$f")")")" \
    "$(grep -o '<nextcloud[^>]*>' "$f" | head -1)"
done

# what the instance actually enabled
docker exec -u www-data <project>-nextcloud-1 php occ app:list
```

Read that listing against the instance's major. An app whose `max-version` is below it
**cannot be enabled at all** — a local blocker you fix by testing and bumping the range,
and a different problem from the store-compatibility message above.

### 5.4 The PHP floor moves with the major

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
but the syntax must also parse on the highest. Testing only on `nextcloud.local`
(PHP 8.5) will not catch an 8.2 incompatibility; that is what the stable containers are
for. Override per-run with `PHP_VERSION=84 docker compose up -d nextcloud` rather than
editing `.env`, which moves every service at once.

### 5.5 Keep one copy of your app, mounted many times

An app checked out once and exposed to several majors via **git worktrees** has one
history and one source of truth. An app that exists as two independently-edited copies
under `workspace/server/apps-extra/` and `workspace/stable34/apps-extra/` has neither:
the copies diverge, and nothing tells you when.

```bash
# is this app a real checkout, or a loose copy?
for d in workspace/server/apps-extra/*/; do
  printf '%-48s %s\n' "$d" \
    "$([ -e "$d/.git" ] && git -C "$d" branch --show-current || echo '⚠ NOT A GIT CHECKOUT')"
done

# do the two trees actually agree?
diff -rq --exclude=.git \
  workspace/server/apps-extra/myapp \
  workspace/stable34/apps-extra/myapp
```

For an app that supports several majors from one branch, stop duplicating it: put it once
in `ADDITIONAL_APPS_PATH` (set in `.env`) and every container mounts it at
`/var/www/html/apps-shared`. One directory, all instances, no divergence to detect.

For an app with real per-major branches, use worktrees, exactly as the server does:

```bash
cd workspace/server/apps-extra/myapp
git worktree add ../../../stable34/apps-extra/myapp stable34
```

### 5.6 Useful defaults

Every instance installs with the same fixtures, which is what makes them disposable:

- **Admin:** `admin` / `admin`. **Users:** `user1`–`user6`, `jane`, `john`, `alice`,
  `bob` — password same as username.
- **All outbound mail** goes to MailHog at `http://mail.local`; nothing leaves the host.
- `password_policy` is disabled at install so the trivial passwords work.
- Auto-enabled apps come from `NEXTCLOUD_AUTOINSTALL_APPS` in `.env`.

---

## Checklist

**Monthly** — or whenever the schedule says a patch shipped:

- [ ] `git pull` in `nextcloud-docker-dev`
- [ ] `make pull-installed`
- [ ] `git pull` in **every** `workspace/*` worktree (name the branch for stable ones)
- [ ] `git submodule update --init` in each worktree that moved
- [ ] `docker compose up -d <services>` — not `restart`, and not Docker Desktop's Play
- [ ] `occ upgrade` on each instance
- [ ] Skim the changelog for the majors you support

**At every major release** — twice a year, non-negotiable:

- [ ] `git pull` the harness first; confirm the new `stableNN` service exists in
      `docker-compose.yml`
- [ ] Create the `stableNN` worktree for the version that just shipped, plus app
      worktrees
- [ ] `./scripts/update-hosts` for the new hostname
- [ ] **Pull `master`** so it becomes the new dev major
- [ ] Retire the worktree and container for the major that just hit EOL
- [ ] Review every app's `max-version` against the new release

**Never:**

- [ ] Run the web updater or `updater.phar` against a bind-mounted git worktree
- [ ] `docker compose down -v` unless you intend to wipe **every** instance's database,
      config and data — and note plain `down` already resets the `stableNN` instances
- [ ] Assume Docker Desktop's Play button picked up an image you just pulled — it did not
- [ ] `occ` as root — it leaves root-owned files in your worktree
- [ ] Trust `:latest` to be latest without pulling
- [ ] Trust `git status` to tell you how far behind upstream you are

---

## Field notes

Findings from this environment. Add to it rather than rediscovering.

**A stale `master` checkout changes identity without telling you — and then reports an
update to itself.** Observed: an instance displaying `Nextcloud Hub 26 Spring
(35.0.0 dev)` and, in the same viewport, a toast reading *"Nextcloud 35.0.0 is
available."* Both were correct. `workspace/server` had been checked out from master in
early July, when master was still 35-in-development at build `35.0.0.1`. Upstream then
cut `stable35`, released 35.0.0 as build `35.0.0.10`, and moved master on to `36.0.0
dev`. The instance compared `35.0.0.1 < 35.0.0.10` and offered the upgrade. The cached
evidence sits in the database verbatim:

```
core lastupdateResult = {"version":"35.0.0.10","versionstring":"Nextcloud 35.0.0", …}
```

The lesson generalises: a stale master checkout does not stay "master". It silently
becomes an unmaintained pre-release of whatever major branched off it, and starts being
compared against that major's real releases. Pulling master immediately after a major
release is the whole prevention.

**`$OC_Channel` in `version.php` is not the channel in use.** The source ships `'git'`,
but `updater.release.channel` in the instance config overrides it, and the bootstrap
leaves it at `stable`. Anything reasoning about update behaviour must read the config,
not the file.

**The server clone only fetches master.** `bootstrap.sh` narrows `remote.origin.fetch`
to a single branch, so bare `git fetch` never sees stable branches and stable worktrees
have no upstream tracking. `git pull` with no arguments fails there. Invisible until the
first time you try to update a stable worktree the obvious way.

**The database name comes from the hostname.** `DBNAME=$(echo "$VIRTUAL_HOST" | cut -d
'.' -f1)` in the container bootstrap — so `stable34.local` silently becomes the
`stable34` database. Nothing in `.env` or `docker-compose.yml` names it, which is why
grepping for the database name finds nothing.

**Stable instances keep config in anonymous volumes; the main one does not.** The
asymmetry means `down`, `down -v` and `--renew-anon-volumes` have very different blast
radii depending on which instance you had in mind. Nothing in the UI hints at it.

**`-v` is not the only destructive flag — plain `down` resets the stable instances.** An
earlier revision of this document stated that anonymous volumes "survive `down`", on the
reasoning that `down` without `-v` does not delete volumes. True of the volume object,
false of the data. Measured with a two-service throwaway project, one named volume and
one anonymous, a marker file written into each:

| | named volume | anonymous volume |
| --- | --- | --- |
| `stop` → `start` | marker intact | marker intact |
| `down` → `up` | marker intact | **empty — new volume; old one orphaned with the data still in it** |

A named volume is reattached by name. An anonymous volume is identified only by its
attachment to a container, so removing the container severs the only reference and `up`
creates a fresh empty one. Checking the flag's documentation rather than the outcome is
how the wrong version got written down.

**Nothing that reuses a container adopts a newly pulled image.** `restart`, `start` and
Docker Desktop's Play button all resume the container you already had, still built on the
old image, and report success. Only `up -d` recreates it. A "pulled but nothing changed"
report is almost always this — and it is especially easy to hit when the environment is
normally parked with Stop rather than brought down.

**Redis is shared and it is fine.** No `dbindex`, no per-instance prefix in the config —
Nextcloud namespaces keys by `instanceid` internally. Worth knowing before someone
"fixes" the shared cache. The flip side: `FLUSHALL` hits every instance at once, and
because the key prefix folds in the installed-app set, toggling an app silently
invalidates that instance's entire cache.

**A new `stableNN.local` will not resolve after `git pull`.** Hostnames live in
`/etc/hosts` via `./scripts/update-hosts`, which no other step calls. The symptom is a
browser DNS error with a perfectly healthy container behind it.

**Two copies of an app are not a branching strategy.** Duplicated app directories across
`server/apps-extra` and `stableNN/apps-extra` look identical the day they are made and
drift from then on, with no signal. Either one shared copy via `ADDITIONAL_APPS_PATH`, or
real worktrees — not both trees edited by hand.

---

Verified against a live setup on 19 Sep 2026: `nextcloud-docker-dev` at `df4ca69`,
`workspace/server` at `3a64d4a` (`35.0.0 dev`, build `35.0.0.1`), `workspace/stable34` at
`cf73e9f` (`34.0.1`), running six containers on MariaDB 10.6 and Redis 8, against
upstream `nextcloud/server` master (`36.0.0 dev`), `stable34` (`34.0.4`) and the released
`v35.0.0` (build `35.0.0.10`). Schedule figures from the server wiki's Maintenance and
Release Schedule; where it and this document disagree, the wiki is right.

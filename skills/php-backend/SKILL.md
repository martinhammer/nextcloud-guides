---
name: php-backend
description: "Rules for a Nextcloud app's PHP backend learned the hard way: storing app and per-user settings (IAppConfig, IUserConfig, core's reserved keys), public OCS endpoints, capabilities for clients, parameter casting, route requirements, concurrent writes and database differences, immutable migrations, app version bumps, OpenAPI docblocks and openapi.json generation, settings registration, Psalm level 1 and vendor-bin tooling, PHPUnit bootstrap modes, the Composer autoloader, database strictness. This skill should be used when writing or reviewing PHP under lib/, migrations, appinfo/info.xml, composer.json or psalm.xml, when storing any setting or per-user value, when adding a public (no-login) endpoint or a capability that clients read, when a boolean or numeric parameter is read wrongly, a route answers 404 or the wrong method, an insert fails on one database only, or a retry fails on PostgreSQL, when choosing or widening the supported Nextcloud version range, when composer openapi or Psalm fails, and whenever an app returns 500 after a schema change, fails to enable or upgrade (occ app:enable errors included), or breaks the whole instance."
paths: "lib/**/*.php, appinfo/**, tests/**/*.php, composer.json, psalm.xml, rector.php, vendor-bin/**"
---

# Nextcloud PHP backend

The rules most often broken (details and reasons in the guide):
- **Config:** app values via `IAppConfig`, user values via `OCP\Config\IUserConfig`.
  `IConfig::{get,set}AppValue` / `{get,set}UserValue` are deprecated (NC 33; Psalm
  level 1 fails on them). **Never write core's app-config keys `enabled`,
  `installed_version`, `types`**: a wrong type on `enabled` takes the whole instance
  down. Prefix app keys that could collide.
- **A shipped migration is never edited.** Renames are add-and-copy, then drop, in
  two migrations, plus a version bump. With `select('*')`, a column the entity lacks
  makes that endpoint 500.
- **Bump the app version only when an upgrade must run something** (a migration, a
  settings or job registration in `info.xml`). Never lower it.
- **Every routed controller method needs full OpenAPI docblocks**; regenerate and
  commit `openapi.json` when an endpoint changes.
- **Supported versions:** declare the range in `info.xml`, test its oldest and newest
  major, and take the PHP floor from the lowest major. A dev instance is a checkout,
  not a release.
- **Typed `bool` parameters turn `no` and `off` into `true`** (`settype()`): read
  flags through a union-typed parameter and parse them. A `{id}` route beside a
  literal sibling needs `requirements: ['id' => '\d+']`.
- **Entity/column mismatches fail only on some databases:** a NOT NULL column whose
  property starts with a value needs that `default` in the migration; `addType()`
  matches the physical column (integer flags, not `Types::BOOLEAN`).
- **On PostgreSQL a unique violation aborts the transaction**: catch-and-retry
  writes run outside one.
- **Settings panels** call both `Util::addScript()` and `Util::addStyle()`.
- **Public OCS endpoints** (`#[PublicPage]`): default the format to JSON (OCS
  answers XML to `Accept: */*`), check the owner and the app yourself, throttle
  unknown tokens.
- **Capabilities** advertise every optional endpoint or parameter to clients as a
  feature flag; `apiVersion` changes only on a breaking change.
- **Dev-tool dependencies live in `vendor-bin/<tool>`**, never in the app's
  `composer.json`, least of all a library the server ships (doctrine/dbal).
- **Tests pass in both bootstrap modes** (OCP stubs standalone; real server in CI).
- **SQLite in CI accepts what MySQL and PostgreSQL refuse** (over-long VARCHAR, NUL,
  invalid UTF-8): fit external text to its column, refuse over-long user input.

Read `${CLAUDE_SKILL_DIR}/references/nextcloud-php-backend.md` before changing config access,
migrations, controllers' API shape, composer/psalm setup, or when debugging an
enable/upgrade failure. HTTP client behaviour: the `http-client` skill. OCS error
shape: the `ocs-errors` skill.

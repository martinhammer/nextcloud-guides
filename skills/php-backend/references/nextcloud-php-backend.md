# Nextcloud PHP Backend: Rules Learned the Hard Way

What breaks in a Nextcloud app's PHP side that tests and static analysis don't
catch, and the conventions the apps follow to avoid it.

- **Applies to:** Nextcloud PHP apps targeting Nextcloud 33–36
- **Sources:** problems hit in production apps (2026-09 to 2026-11); server behaviour
  read in the `stable34`, `stable35` and `master` source; version ranges and PHP bounds
  checked against those checkouts (2026-10)

---

## Configuration

- **App values: `IAppConfig`** (`getValueBool/Int/String`, `setValue…`). **User
  values: `OCP\Config\IUserConfig`** (`getValueString/Int/Bool`, `setValueString/…`,
  `searchUsersByValueString` to find users by a value). `IConfig::getAppValue` /
  `setAppValue` and, since NC 33, `IConfig::{get,set}UserValue` /
  `getUsersForUserValue` are deprecated; Psalm at error level 1 fails on them.
- Storing per-user values as strings keeps the wire format stable when other code
  matches on them (e.g. a `'1'` flag fan-out).
- **Core owns `enabled`, `installed_version` and `types` in each app's app-config.**
  `enabled` is stored as the string `yes` with type `VALUE_MIXED`, which skips the
  type-conflict check, so `setValueBool(APP_ID, 'enabled', …)` *succeeds* and
  rewrites the row as a BOOL. The next request fails during bootstrap
  (`getAppInstalledVersions()` reads it as a string → `AppConfigTypeConflictException`),
  on every web request and every `occ` call: a full instance outage. In a dev
  container `occ status` then looks like an uninstalled server; re-running
  `maintenance:install` regenerates `secret`, after which every
  `ICredentialsManager` value is undecryptable. Name app keys so they can't collide
  (`pipeline_enabled`). Repairing such a row needs SQL in a migration, because
  `updateType()` is not on `IAppConfig`.
- **Secrets go in `ICredentialsManager`.** It decrypts with the instance `secret`;
  after that changes, reads throw `HMAC does not match`. **Catch it and treat an
  unreadable secret as absent**, so the settings page that re-enters it still loads.
  Don't delete the row in a getter; the next save overwrites it.
- **Settings and background jobs are registered in `info.xml`** (`<settings>`,
  `<background-jobs>`); a version bump makes Nextcloud re-read them.

## Migrations and the schema

- **A shipped migration is immutable.** An instance that ran it records
  `installed_version` and never runs it again, so editing it in place leaves old
  instances with the old schema. Rename a column as add-and-copy, then drop, **in two
  migration classes** (the schema step runs before the data step), and bump the
  version.
- **`select('*')` + `Entity::fromRow` calls a setter per column**, so a column the
  entity doesn't declare throws `BadFunctionCallException`. Symptom: one endpoint
  500s, the others work, and the entity changed recently; the error names no column.
- **Identifier length:** keep index names short (an app prefix like `tm_`);
  Nextcloud enforces about 30 characters (Oracle).
- **SQLite (which CI's PHPUnit job uses) refuses none of** an over-long `VARCHAR`,
  a NUL byte or invalid UTF-8; MySQL in strict mode and PostgreSQL refuse them. Text
  from outside (email, a model, an upstream API) is scrubbed and cut to its column;
  text a user typed is refused with a 400 instead, since cutting it saves something
  they did not enter. Store each external item on its own, so one bad item fails
  alone.

## App version

- **Bump it only when an upgrade has to run something:** a migration, or a change to
  settings/job registration in `info.xml`. Frontend, services, wording and tests don't
  need one; deploying picks up code. The version is not a build number.
- **Never lower it** below what an instance has installed: Nextcloud reads that as a
  downgrade.

## Controllers and the API

- OCS endpoints: `OCSController` + `DataResponse`. Error shape and client handling:
  the `ocs-errors` skill.
- **Don't name a controller parameter `format`**: OCS uses it to pick the response
  format, and a `format` in the query or body overrides it. Use e.g. `dataformat`.
- **OpenAPI:** every routed method needs a one-line summary (no trailing period), a
  `@param` per parameter, a typed `@return DataResponse<Http::STATUS_…, T, array{}>`,
  a `@throws OCS…Exception` per error path with matching `NNN: description` lines.
  Shared shapes are `@psalm-type`s in `lib/ResponseDefinitions.php`, imported with
  `@psalm-import-type`; the entity's `jsonSerialize()` carries the same `@return`.
  `array_map` over a list gives `array<array-key,…>`: wrap in `array_values()` when
  the spec says `list<…>`. Internal-only controllers get
  `#[OpenAPI(OpenAPI::SCOPE_IGNORE)]`. Regenerate (`composer openapi` /
  `make openapi`) and commit `openapi.json` with the change; CI fails otherwise.
- **Never trust a `user_id` from the client**; scope every query server-side.
- **Settings panels (`ISettings::getForm()`) call both `Util::addScript($app,
  "$app-<entry>")` and `Util::addStyle($app, "$app-<entry>")`.** The Vite build emits
  a separate CSS file per entry; without `addStyle` the panel renders unstyled. The
  entry name must match the key in `vite.config.ts`.
- **Task Processing:** probe providers with `getAvailableTaskTypes()`;
  `getAvailableTaskTypeIds()` is newer and may be missing on older majors.

### Public (unauthenticated) OCS endpoints

For a link or token that works without a login (a share link, a webhook, a
script's URL):
- `#[PublicPage]` + `#[NoCSRFRequired]` on an `OCSController` method; the caller
  then needs no `OCS-APIRequest` header.
- **OCS answers XML when the client asks for no format**, and curl
  (`Accept: */*`) and a browser bookmark ask for none. If people or scripts call
  the endpoint, default to JSON in the controller; `?format=xml` still works:
  ```php
  public function buildResponse($response, $format = 'json') {
      return parent::buildResponse($response, $format);
  }
  ```
- **Two `#[ApiRoute]`s on one method need distinct `postfix` values**
  (`#[ApiRoute(verb: 'POST', url: '/x/{token}', postfix: 'post')]`); without one
  they share a route name and the second replaces the first.
- **A public page skips Nextcloud's checks for the owner.** There is no
  meaningful `$userId` (Nextcloud injects the caller's session, or null). Resolve
  the owner from the token, and check that the owner exists, is enabled and has
  the app enabled. Otherwise answer the same 404 as for an unknown token, so
  tokens can't be probed.
- **Throttle:** `#[BruteForceProtection(action: '<app>PublicLink')]` with
  `$response->throttle()` only on tokens that never existed;
  `#[AnonRateLimit(limit: 60, period: 60)]` counts per calling address.
- **"Today" is the owner's day**: the `core` / `timezone` user value, else the
  server default. `IDateTimeZone::getTimeZone($ts, $owner)` falls back to the
  *caller's* session offset.

### Capabilities for clients

Clients (mobile apps, CLIs) find out what the server supports from capabilities,
not by sniffing versions or probing for 404s.
- `$context->registerCapability(Capabilities::class)`; the class implements
  `OCP\Capabilities\ICapability::getCapabilities()` and returns
  `[$appId => ['version' => …, 'apiVersion' => …, 'features' => [...]]]`. It is
  served in `GET /ocs/v2.php/cloud/capabilities` to any authenticated user (an
  app password works). Also implement `IPublicCapability` only for what anonymous
  callers may see.
- **Every optional endpoint or parameter a client may use gets a boolean
  feature flag.** An older server usually fails quietly: it ignores an unknown
  parameter and answers 200, or 404s a new route. A flag is the only way a client
  can tell the difference.
- Bump `apiVersion` only on a breaking change; additive changes get flags. Never
  rename or remove a flag. A planned feature's flag stays `false` until it ships.

## Supported Nextcloud versions

- **A dev instance is a git checkout, not a release.** It is exactly as current as its
  last pull: a `35.0.0 dev` lacks code merged since and may contain code reverted
  before GA. Before treating a difference as a bug, confirm what the instance runs
  (`occ status`).
- **Declare the range in `appinfo/info.xml`**
  (`<nextcloud min-version="33" max-version="35"/>`). Nextcloud refuses to enable the
  app outside it, and the app store won't offer it there. Three majors are supported
  at once, so a range of three is normal, and that means three instances to test on:
  the oldest major (your floor still works), the middle one (where most users are) and
  the newest (you're not about to break). Raise `max-version` only after testing that
  major, and publish a release that declares it.
- **"N apps have no compatible version" is about the app store, not your code.** The
  admin overview lists apps with no *published release* for the target version. A
  local app can work and still appear there. A different, local problem: an app whose
  `max-version` is below the instance's major **cannot be enabled at all**; fix it by
  testing and raising the range.
- **The PHP floor moves with the major.** Read the bounds from the server
  (`grep -A2 'PHP_VERSION_ID' lib/versioncheck.php`) rather than assuming. In late
  2026: Nextcloud 34 runs PHP 8.2–8.5, Nextcloud 35 runs 8.3–8.5. An app's floor is
  the **lowest** across its range, but its syntax must also parse on the highest; an
  instance on the newest PHP won't catch an incompatibility with the oldest. The same
  floor drives `nextcloud/ocp`, the Psalm matrix and `psalm.xml` (see Static analysis).

## Composer and the autoloader

- **Nextcloud only auto-includes `<app>/composer/autoload.php`**, not
  `vendor/autoload.php`. Libraries outside `OCA\` (e.g. Horde's PSR-0 classes) are
  then not found on web requests even though the files exist. `require_once` the
  vendor autoloader in `Application::__construct()`. A CLI `require` test only proves
  the files exist.
- **Dev tools live in `vendor-bin/<tool>`** (bamarni bin plugin): Psalm, PHPUnit,
  php-cs-fixer, Rector. **A library the server already ships never goes in the app's
  `composer.json`**, not even `require-dev`: a dev install puts a second copy in
  `vendor/`, the app's autoloader shadows the server's, and `occ app:enable` dies
  (`Undefined constant Doctrine\DBAL\Types\Types::NUMBER`). `doctrine/dbal` belongs in
  `vendor-bin/psalm` and `vendor-bin/phpunit` only.
- **Libraries Nextcloud ships differ by major**: `symfony/console` is 6.4 in NC 34 and
  7.4 in NC 36, so `occ` commands use only API common to every supported major, and
  it stays a dev dependency.
- **Runtime dependencies** go in `require` so they ship in the `--no-dev` build.
- **Platform pins:** declare extensions Nextcloud guarantees but the dev machine may
  lack in `config.platform` (e.g. `ext-gd`) rather than installing them.

## Static analysis

- **Psalm `errorLevel=1` with `findUnusedCode=true`.** Classes only Nextcloud
  instantiates (DI, `info.xml`-registered jobs, settings, migrations) look unused:
  mark them `@psalm-suppress UnusedClass`. Entities carry
  `@psalm-suppress PropertyNotSetInConstructor` for the base `$id`. A baseline
  (`--set-baseline`) is only for framework false positives that can't be annotated;
  fix real issues.
- **OCP stubs:** `nextcloud/ocp` pinned to `dev-stableNN` of the **lowest** supported
  major. The CI Psalm matrix is derived from `info.xml` `min/max-version`;
  `psalm.xml` `phpVersion` must equal that floor's PHP (8.2 for NC 33), and
  `composer.json` `php`/`platform.php` stays aligned. Check an API against a server
  checkout of every supported major (nextcloud-docker-dev's `workspace/`).
- **Rector:** skip `PrivatizeFinalClassMethodRector` for `tests/`. It doesn't see
  `setUp()` as a `TestCase` override (PHPUnit lives in `vendor-bin`), makes it
  private in `final` test classes, and `RemoveUnusedPrivateMethodRector` then deletes
  it: every test fails with "must not be accessed before initialization".

## Tests

- **`tests/bootstrap.php` has two modes.** Standalone, it registers the OCP stubs
  as PSR-4 and the suite runs from the repo alone. In CI (`phpunit-sqlite.yml`) the
  stubs are removed, the app sits in a server checkout, and the bootstrap loads the
  server's bootstrap, so `OCP\*` are the real classes. A test that passes in only one
  mode is a broken test.
- **Keep parsing and domain logic free of OCP types** so it is testable with no stubs.
- Run one test file:
  `vendor-bin/phpunit/vendor/bin/phpunit tests/unit/<Path>Test.php -c tests/phpunit.xml`.

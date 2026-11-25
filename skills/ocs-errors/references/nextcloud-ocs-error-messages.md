# Nextcloud OCS Error Messages

Why an app's error toasts come up **blank**, where an OCS error message actually
lives, and one small client helper that reads it correctly whichever way the server
produced it — so an app shows the server's reason ("Origin is required") instead of
nothing at all.

- **Applies to:** frontends calling an app's `OCSController` endpoints through
  `@nextcloud/axios` (or any HTTP client) and showing the error to the user
- **Verified on:** a live Nextcloud 34 instance (responses captured below); the
  relevant server source is identical in `stable34`, `stable35` and `master` as of
  September 2026

---

## The rule

> **Read `ocs.data.message` first, then `ocs.meta.message` — joined with `||`, never
> `meta.message ?? fallback`.**

An OCS error message is in one of two places depending on how the controller
produced the error. For the most common app pattern — *returning* a
`DataResponse(['message' => …], 400)` — `meta.message` is not missing but the
**empty string**. `??` only falls back on `null`/`undefined`, so
`meta.message ?? 'Save failed'` evaluates to `''`, and the toast shows nothing.

## The two shapes, as the server sends them

Captured from a Nextcloud 34 instance with `curl`. Same request style, two ways of
failing.

**A controller *returns* an error `DataResponse`** — the message is in `data`, and
`meta.message` is `""`:

```php
return new DataResponse(['message' => $e->getMessage()], Http::STATUS_BAD_REQUEST);
```

```json
{"ocs":{"meta":{"status":"failure","statuscode":400,"message":""},
        "data":{"message":"flightDate must be YYYY-MM-DD"}}}
```

**A controller *throws* an `OCSException`** — the message is in `meta`, and `data` is
an empty array:

```php
throw new OCSNotFoundException('Wrong share ID, share does not exist');
```

```json
{"ocs":{"meta":{"status":"failure","statuscode":404,"message":"Wrong share ID, share does not exist"},
        "data":[]}}
```

| Server side | HTTP (v2) | `ocs.meta.message` | `ocs.data` |
| --- | --- | --- | --- |
| `return new DataResponse(['message' => $m], 4xx)` | 4xx | `""` | `{"message": $m}` |
| `throw new OCS…Exception($m)` | exception's code | `$m` | `[]` |
| 401/403 raised by middleware (not logged in, admin required…) | 401 / 403 | the middleware's message | `[]` |
| Uncaught exception / fatal error | 500 | — (often no OCS envelope at all) | — |

## Where this comes from in the server

`meta.message` is only ever filled from a `statusMessage` that the controller's own
`DataResponse` has no way to set. The renderer
(`lib/private/AppFramework/OCS/V2Response.php`):

```php
'message' => $status >= 200 && $status < 300 ? 'OK' : $this->statusMessage ?? '',
```

When a controller returns a `DataResponse`, `OCSController` builds the
`V2Response` without a status message, so a failure renders `''` — that is the
`?? ''` on the end. The *only* paths that pass one are in
`lib/private/AppFramework/Middleware/OCSMiddleware.php`:

- `afterException()` — catches an `OCSException` and builds a new, **empty**
  `DataResponse` with `$exception->getMessage()` as the status message. Hence `data: []`.
- `afterController()` — converts a non-OCS 401/403 (from the security middleware)
  into an OCS response, lifting its `message` into `meta`.

`V1Response::render()` has the same `?? ''`, so v1 behaves the same way here (but see
[OCS v1](#ocs-v1-errors-arrive-as-http-200) for a bigger problem).

## Why the bug is so common

Nextcloud's own apps nearly always **throw** `OCS…Exception`s, so their frontends
correctly read `meta.message`. A survey of the server repository's bundled apps
(September 2026): over 30 PHP files throw OCS exceptions, a dozen frontend files read
`ocs.meta.message`, and none read `ocs.data.message`. That is the pattern a new app
copies.

Many apps instead **return** typed error responses — the natural choice when the
controller's return type documents the error body for the OpenAPI extractor:

```php
/** @return DataResponse<Http::STATUS_OK, …>|DataResponse<Http::STATUS_BAD_REQUEST, array{message: string}, array{}> */
```

Combine the two and every error toast is blank. Nothing crashes, no test using a
hand-made fixture fails, and the request looks fine in the network tab. The user
just sees an empty red box.

## What each client pattern does

| Client code | Returned `DataResponse` | Thrown `OCSException` | Network error / 500 |
| --- | --- | --- | --- |
| `…meta?.message ?? 'Save failed'` | **blank toast** (`''`) | correct | fallback |
| `…meta?.message \|\| 'Save failed'` | fallback — real reason lost | correct | fallback |
| `…data?.message ?? 'Save failed'` | correct | fallback — real reason lost (`data` is `[]`) | fallback |
| `error.response.data.ocs.meta.message` (unguarded) | `''` | correct | **`TypeError` inside your `catch`** — no `response` |
| `ocsErrorMessage(e, 'Save failed')` (below) | correct | correct | fallback |

## Correct handling

One helper, used by every `catch` that shows a server error:

```ts
// src/ocsError.ts
/**
 * The message to show for a failed OCS request.
 *
 * A returned DataResponse(['message' => …]) lands in ocs.data.message, with
 * meta.message set to '' (not absent). A thrown OCSException lands in
 * ocs.meta.message, with data = []. Read both, and use `||` so an empty string
 * falls through to the fallback rather than producing a blank toast.
 */
export function ocsErrorMessage(e: unknown, fallback: string): string {
	const ocs = (e as { response?: { data?: { ocs?: { meta?: { message?: unknown }; data?: { message?: unknown } } } } })
		?.response?.data?.ocs
	const text = (value: unknown) => (typeof value === 'string' ? value.trim() : '')
	return text(ocs?.data?.message) || text(ocs?.meta?.message) || fallback
}
```

```ts
try {
	await store.save(form)
} catch (e) {
	showError(ocsErrorMessage(e, 'Failed to save flight'))
}
```

Design points, each of which closes one of the failure rows above:

- **`data.message` first, then `meta.message`** — covers both server conventions, so
  the frontend doesn't depend on which one a given endpoint uses.
- **`||`, not `??`** — the empty `meta.message` must fall through.
- **`typeof … === 'string'`** — `data` is `[]` for exceptions and may be a bare string
  or anything else for hand-rolled responses; a non-string never reaches the toast.
- **Optional chaining all the way down** — a network error has no `response`, and an
  XML or HTML body has no `ocs`. The helper must never throw from inside a `catch`.
- **Its own module** — if your component tests replace your API module wholesale with
  `vi.mock('…/api.ts', () => ({ … }))`, a helper defined there becomes `undefined`
  in those tests.

## Server side: pick one convention and keep to it

Both conventions work with the helper. What matters is that the error carries a
human-readable message in one of the two places:

| | Return a `DataResponse` | Throw an `OCSException` |
| --- | --- | --- |
| Message lands in | `ocs.data.message` | `ocs.meta.message` |
| Error body in OpenAPI | Typed via the `@return` union | Not part of a typed body |
| Extra error fields | Any (`['message' => …, 'field' => 'origin']`) | None — `data` is always `[]` |
| Matches Nextcloud core | No | Yes |

Avoid:

- **`new DataResponse('Invalid date', 400)`** — `data` becomes a bare string, so there
  is no `data.message` for any client to read. Always wrap it: `['message' => …]`.
- **An error with no message at all** (`new DataResponse([], 400)`) — the best any
  client can then show is a generic fallback.
- **A controller parameter named `format`** — `IRequest::getFormat()` reads the
  `format` request parameter, body included, before the `Accept` header. A body
  field called `format` silently switches the response to whatever it contains.
  Use a descriptive name (`dataformat`, `exportFormat`).

## Edge cases

### OCS v1: errors arrive as HTTP 200

`V1Response::getStatus()` returns **200 for everything except 401**. The real code
is only in `ocs.meta.statuscode` (`100` means OK). Captured from the same endpoint
as above, over `/ocs/v1.php`:

```json
HTTP 200
{"ocs":{"meta":{"status":"failure","statuscode":400,"message":"", …},
        "data":{"message":"flightDate must be YYYY-MM-DD"}}}
```

axios does not reject a 200, so **no `catch` runs**: the failure looks like success.
`generateOcsUrl()` from `@nextcloud/router` targets **v2 by default**, so this only
bites if you pass `{ ocsVersion: 1 }` or hand-build `/ocs/v1.php` URLs. If you must
use v1, check `ocs.meta.statuscode !== 100` on the success path as well.

### XML instead of JSON

`IRequest::getFormat()` takes the `format` parameter if present, otherwise the first
`application/*` type in the `Accept` header, and otherwise the response is **XML**.
`@nextcloud/axios` sends `Accept: application/json, text/plain, */*`, which yields
JSON. Appending `?format=json` to every OCS URL is a sensible extra safeguard, and
the only option if you replace the `Accept` header. When a response does come back as
XML, `response.data` is a string. The helper then finds no `ocs` and returns the
fallback rather than crashing, but the real message is lost.

### 500s

An uncaught PHP exception does not produce the OCS envelope you expect — the body may
be HTML or a different JSON shape. The fallback text is all you will get. Catch
domain exceptions in the controller and turn them into one of the two shapes above.

## Testing it

Unit and component tests are exactly where this bug survives: a hand-written fixture
like `{ ocs: { meta: { message: 'Bad date' } } }` passes with the buggy code. **Build
fixtures in the shape the server actually sends**, with `meta.message: ''`:

```ts
/** A 400 exactly as the server renders a returned DataResponse(['message' => …]). */
const serverError = (message: string) => ({
	response: { data: { ocs: { meta: { status: 'failure', statuscode: 400, message: '' }, data: { message } } } },
})

it('shows the server\'s validation message, not a blank toast', async () => {
	store.save.mockRejectedValueOnce(serverError('flightDate must be YYYY-MM-DD'))
	// … drive the form's save …
	expect(showError).toHaveBeenCalledWith('flightDate must be YYYY-MM-DD')
})
```

Then prove the test can fail: revert the fix (e.g. `git stash push <files>`), run it,
and confirm it goes red before restoring. A fallback-only test ("network error shows
'Save failed'") passes against both the old and the new code, so it is not a
regression test for this bug.

## Checklist

**Server**

- [ ] Every 4xx carries a human-readable message — `DataResponse(['message' => …], 4xx)`
      or `throw new OCS…Exception(…)`
- [ ] No bare-string error bodies (`new DataResponse('…', 400)`)
- [ ] No controller parameter named `format`

**Client**

- [ ] Every `catch` that shows a server error uses one helper reading `data.message`
      then `meta.message`
- [ ] No `meta.message ?? …` anywhere
- [ ] No unguarded `error.response.data.ocs…` inside a `catch`
- [ ] All OCS URLs come from `generateOcsUrl()` (v2), or v1 callers check
      `meta.statuscode` on success
- [ ] Error-path tests use the server's real shape (`meta.message: ''`) and were seen
      to fail against the old code

## Check commands

Run from the app's root.

```bash
# Server: which convention does the app use? (Either is fine — know which.)
grep -rnE "new DataResponse\(\[\s*'message'" lib/
grep -rnE "throw new OCS[A-Za-z]*Exception" lib/

# Client: the blank-toast bug — must print nothing
grep -rnE "meta\??\.message\s*\?\?" src/

# Client: every remaining meta.message read — each should go through the helper
grep -rnE "ocs\??\.meta\??\.message" src/

# Client: OCS v1 callers, whose errors arrive as HTTP 200
grep -rnE "ocsVersion:\s*1|/ocs/v1\.php" src/

# Server: anything called `format` in a controller — review each hit for a
# request parameter of that name (local variables are fine)
grep -rnE '\$format\b' lib/Controller/
```

To see what a failing endpoint actually sends, ask it directly (use an app password,
and pick a request that fails validation so nothing is written):

```bash
curl -s -u USER:APP_PASSWORD \
  -H 'OCS-APIRequest: true' -H 'Accept: application/json' -H 'Content-Type: application/json' \
  -X POST 'https://HOST/ocs/v2.php/apps/APPID/api/v1/…' -d '{ … invalid … }' \
  -w '\nHTTP %{http_code}\n'
```

If `meta.message` is `""` and the text is under `data`, every client read of
`meta.message` on that endpoint is showing an empty toast.

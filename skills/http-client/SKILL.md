---
name: http-client
description: "Behaviour of Nextcloud's HTTP client (IClientService / IClient) that differs from plain Guzzle: getAsync() is synchronous and 'stream' => true is ignored. This skill should be used before relying on async, parallel, streaming or callback behaviour of outgoing requests from an app's PHP code, and when such requests are slow or behave unexpectedly."
---

# Nextcloud's HTTP client

Checked on Nextcloud 34, 35 and 36 (November 2026):
- **`IClient::getAsync()` (and the other `…Async()` methods) does not run in
  parallel.** It completes the whole request before it returns; `then()` handlers
  may never run. Don't build parallel fetching on it.
- **`'stream' => true` is ignored**: the whole body downloads first. A custom
  `sink` plus an `on_headers` callback does stream.

**Probe behaviour with the client built the way Nextcloud builds it, never with
plain Guzzle.** Guzzle's default client gives wrong answers (an earlier probe that
way "proved" parallelism, and the shipped build fetched nothing). Build a harness
from a server checkout of each supported major (nextcloud-docker-dev's `workspace/`):
`OC\Http\Client\Client` with `HandlerStack::create(new CurlHandler())` plus the
event-logger middleware, as `ClientService::newClient()` does, the 3rdparty and
OCP/OC autoloaders, stubbed `IConfig`/`ICertificateManager`/`IRemoteHostValidator`,
and a local `php -S` server. Run the app's own code through it before calling an
API working.

When a new Nextcloud major changes this, update this skill.

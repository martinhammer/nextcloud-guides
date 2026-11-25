---
name: ocs-errors
description: "Showing OCS API error messages in a Nextcloud app frontend: read ocs.data.message first, then ocs.meta.message, joined with ||. This skill should be used when writing error handling for OCSController calls, when error toasts come up blank or generic, and when deciding how a controller should return errors."
---

# Nextcloud OCS error messages

**Read `ocs.data.message` first, then `ocs.meta.message`, joined with `||`, never
`meta.message ?? fallback`.** When a controller returns
`DataResponse(['message' => …], 400)`, `meta.message` is the empty string, so `??`
yields `''` and the toast shows nothing.

Read `${CLAUDE_SKILL_DIR}/references/nextcloud-ocs-error-messages.md` for the client helper to
use, the server-side convention (pick one and keep to it), edge cases (OCS v1
errors arriving as HTTP 200, XML, 500s), tests and the checklist.

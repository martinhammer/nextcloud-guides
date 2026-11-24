---
name: dev-environment
description: How the local nextcloud-docker-dev environment works - containers, which worktree feeds which instance, how Nextcloud versions and releases work - and what app developers need to know (testing a version range, the PHP floor, apps that span several majors). Use when an answer depends on which Nextcloud version or container is running, when the dev environment behaves unexpectedly, or when choosing an app's supported version range.
---

# Nextcloud dev environment (nextcloud-docker-dev)

**Nothing in this environment updates itself. The version is the git commit that is
checked out.** Four layers each carry a version and drift apart silently: the
harness clone, the container images (`:latest` as last pulled), the server
worktrees (`workspace/server`, `workspace/stableNN`), and the apps.

Read `${CLAUDE_SKILL_DIR}/nextcloud-dev-environment-maintenance.md`:
- Part 5 and the checklist when choosing or testing an app's version range.
- Parts 1–3 to work out what is running where, or why an instance misbehaves.
- Part 4 (maintenance runbook) is for the user to run. Don't pull, update, restart
  or reconfigure the environment yourself; give the commands instead. Never run
  the web updater.

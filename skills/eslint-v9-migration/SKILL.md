---
name: eslint-v9-migration
description: Migrating a Nextcloud app from @nextcloud/eslint-config 8 (ESLint 8, .eslintrc) to 9 (ESLint 10, flat eslint.config.js), and why the Dependabot bump alone always fails CI. Use when that Dependabot PR fails, when lint reports that ESLint couldn't find an eslint.config file, or when planning or doing the migration.
paths: "eslint.config.*, .eslintrc*"
---

# @nextcloud/eslint-config v9 migration

The Dependabot bump fails because v9 needs work by hand:
1. ESLint 10 reads only flat config (`eslint.config.js`); `.eslintrc.*`,
   `.eslintignore` and `eslintConfig` in `package.json` are ignored.
2. `eslint` becomes a peer dependency: the app must list it in `devDependencies`.
3. The rule set is much larger; expect many findings, most auto-fixable.

Follow the steps in `${CLAUDE_SKILL_DIR}/nextcloud-eslint-config-v9-migration.md`
in order (pre-flight inventory through verify), including its CI step. The guide's
steps have not yet been run end to end on a real app: when you migrate one, note
what differed and propose an update to the guide.

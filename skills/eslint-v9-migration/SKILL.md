---
name: eslint-v9-migration
description: "Migrating a Nextcloud app from @nextcloud/eslint-config 8 (.eslintrc) to 9 (ESLint 10, flat eslint.config.js). This skill should be used when the Dependabot bump of @nextcloud/eslint-config fails CI, when lint reports that ESLint couldn't find an eslint.config file, and when planning or carrying out the migration."
paths: "eslint.config.*, .eslintrc*"
---

# @nextcloud/eslint-config v9 migration

The Dependabot bump fails because v9 needs work by hand:
1. ESLint 10 reads only flat config (`eslint.config.js`); `.eslintrc.*`,
   `.eslintignore` and `eslintConfig` in `package.json` are ignored.
2. `eslint` becomes a peer dependency: the app must list it in `devDependencies`.
3. The rule set is much larger; expect many findings, most auto-fixable.

Follow the steps in `${CLAUDE_SKILL_DIR}/references/nextcloud-eslint-config-v9-migration.md`
in order (pre-flight inventory through verify), including its CI step. The guide's
steps have not yet been run end to end on a real app: after migrating one, note
what differed and propose an update to the guide.

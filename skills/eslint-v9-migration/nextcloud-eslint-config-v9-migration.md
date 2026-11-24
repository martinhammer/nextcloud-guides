# Migrating to `@nextcloud/eslint-config` v9 (ESLint 10, flat config)

How to move a Nextcloud app from `@nextcloud/eslint-config` 8.x (ESLint 8,
`.eslintrc.*`) to 9.x (ESLint 10, `eslint.config.js`), and why a Dependabot bump
on its own always fails CI.

- **Applies to:** Nextcloud apps (and libraries) that lint JS/TS/Vue with
  `@nextcloud/eslint-config` 8.x and an `.eslintrc.*` file
- **Researched against:** `@nextcloud/eslint-config` 9.0.1 (published package
  source, `dist/configs/*`), `eslint` 10.12.0, and the migrated configs in
  `nextcloud/server`, `nextcloud/text` and `nextcloud/app_api` (October 2026)
- **Status:** steps not yet run end to end on a real app. Update this line
  after the first migration.

---

## Why the Dependabot PR fails

Dependabot changes the version in `package.json` and the lockfile, and nothing
else. v9 is a breaking change in three ways that need work by hand:

1. **The config format changes.** ESLint 10 only reads *flat config*
   (`eslint.config.js`). It ignores `.eslintrc.*`, `.eslintignore` and the
   `eslintConfig` key in `package.json`. If no flat config exists, `npm run lint`
   fails straight away with *"ESLint couldn't find an eslint.config.(js|mjs|cjs)
   file"*.
2. **`eslint` becomes your dependency.** In v8 the package brought ESLint 8 in
   with it. v9 declares `eslint >=10` as a **peer** dependency, so the app must
   list `eslint` in its own `devDependencies`.
3. **The rule set is much bigger.** v9 merges the old `@nextcloud/eslint-plugin`
   and replaces `eslint-config-standard`/babel with `@stylistic`,
   `typescript-eslint`, `perfectionist` (import sorting), `@eslint/json` and
   others. Expect many new findings. Most of them can be fixed automatically.

## What changes, v8 → v9

| | v8 | v9 |
| --- | --- | --- |
| ESLint | 8.x, pulled in by the config package | **10.x, peer dependency: install it yourself** |
| Config file | `.eslintrc.js` / `.eslintrc.cjs` / `eslintConfig` | `eslint.config.js` (ESM) |
| Ignores | `.eslintignore` | `.gitignore` is honoured automatically, plus `globalIgnores()` in the config |
| Extending | `extends: ['@nextcloud']` | `import { recommended } from '@nextcloud/eslint-config'` and spread it |
| Node | anything recent | `^22.14 \|\| ^24 \|\| >=26` |
| Vue `<script>` parser | `@babel/eslint-parser`, which **cannot parse TS syntax** in `.vue` | `recommended` uses `@typescript-eslint/parser`, so TS in `.vue` works |
| Linted file types | `.js`, `.ts`, `.vue` | also **`.json`** (and `package.json` key order) |
| Style rules | `eslint-config-standard` + core rules (`indent`, `quotes`…) | `@stylistic/*` (tabs, no semicolons, single quotes, trailing commas, always parens around arrow parameters) |

### Pick the preset

| Preset | Vue | `<script>` in `.vue` is treated as | Use for |
| --- | --- | --- | --- |
| `recommended` | 3 | TypeScript | Vue 3 apps (the default) |
| `recommendedJavascript` | 3 | JavaScript | Vue 3 apps whose `.vue` scripts are plain JS |
| `recommendedVue2` | 2 | TypeScript | Vue 2 apps |
| `recommendedVue2Javascript` | 2 | JavaScript | Vue 2 apps with JS scripts |
| `recommendedLibrary` / `recommendedVue2Library` | 3 / 2 | TypeScript | npm libraries: no deprecated-Nextcloud-API checks, and props must be documented |

`recommended` works for `.vue` files that contain only JS too, because TS is a
superset of JS. The only difference is that the jsdoc rules then expect
TS-style docs: no `{type}` in `@param` on typed functions.

### New rules that fire most often

| Rule | What it wants | `--fix`? |
| --- | --- | --- |
| `perfectionist/sort-imports` | Imports in groups: types first, then external, then Vue components, then local; natural order within a group; no blank lines inside a group | yes |
| `perfectionist/sort-named-imports` / `-exports` | `{ a, b, c }` sorted | yes |
| `import-extensions/extensions` | Relative imports need a file extension (`'./foo.ts'`, `'./Foo.vue'`) | **no**, only an editor suggestion |
| `@typescript-eslint/consistent-type-imports` | `import type { X }` for imports used only as types | yes |
| `import-extensions/ban-inline-type-imports` | No `import { type X, y }`. Split into an `import type` line and a value import | yes |
| `antfu/top-level-function` | `function foo() {}` at top level, not `const foo = () => {}` | yes |
| `package-json/sort-package-json` | Canonical key order in `package.json` | yes |
| `vue/attribute-hyphenation: never`, `vue/v-on-event-hyphenation: never` (Vue 3) | camelCase props and events in templates (`:someProp`, `@updateValue`) | yes |
| `vue/attributes-order`, `vue/order-in-components` | Consistent order (error since 9.0.1) | yes |
| `@nextcloud/no-deprecated-library-props` / `-exports` | No deprecated `@nextcloud/vue` props or exports (for example old `NcButton` `type`) | yes |
| `no-console` | Use `@nextcloud/logger` | no |
| `jsdoc/require-jsdoc` | JSDoc on functions (warn) | no; most apps turn it off |
| `vue/no-unused-properties`, `vue/no-unused-refs` | Dead props and refs (warn) | no |
| unused `eslint-disable` comments | Disable comments that suppress nothing are reported | yes (removes them) |

## Step-by-step

### 0. Pre-flight inventory

Write these down before changing anything. Each one maps to a later step.

```bash
ls -a | grep -iE 'eslint'                        # .eslintrc.*, .eslintignore
grep -n '"eslintConfig"\|"lint' package.json     # inline config, lint scripts
grep -rn 'eslint-disable' src/                   # rule names that may no longer exist
grep -n 'eslintrc\|eslintignore' .github/workflows/*.yml
node --version                                   # must satisfy ^22.14 || ^24 || >=26
grep -n '"type"' package.json                    # "module" → eslint.config.js; otherwise .mjs
```

Note:

- every `rules:` override, `env`/`globals` entry, `overrides` block and ignore
  pattern in the old config
- which preset fits (table above)
- old lint-only devDependencies that v9 now bundles or no longer uses:
  `@nextcloud/eslint-plugin`, `@vue/eslint-config-typescript`,
  `@babel/eslint-parser`, `eslint-config-standard`, `eslint-plugin-import`,
  `eslint-plugin-n`, `eslint-plugin-promise`, `eslint-plugin-vue`,
  `eslint-plugin-jsdoc`, `eslint-webpack-plugin`

### 1. Update the dependencies

Do this on a branch, either starting from the Dependabot PR's branch or fresh:

```bash
npm install --save-dev @nextcloud/eslint-config@^9 eslint@^10
npm uninstall <old lint-only packages from step 0, if listed directly>
```

If `npm run lint` later fails with
**`TypeError: scopeManager.addGlobals is not a function`**, an ESLint-8-era
plugin is still nested in the lockfile. Run `npm update`. If that does not help,
delete `package-lock.json` and `node_modules` and run `npm install` again (the
fix the upstream changelog suggests).

If `engines.node` in `package.json` is below 22.14, raise it. The shared CI
workflows read the Node version from there.

### 2. Create `eslint.config.js`

Name it `eslint.config.js` if `package.json` has `"type": "module"`, otherwise
`eslint.config.mjs`. Minimal form:

```js
/**
 * SPDX-FileCopyrightText: 2026 <you>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

import { recommended } from '@nextcloud/eslint-config'
import { defineConfig } from 'eslint/config'

export default defineConfig([
	...recommended,
])
```

`defineConfig` is optional; `export default [ ...recommended ]` works too. It
gives editor type-checking of the config and allows `extends:` inside config
objects.

### 3. Port the old overrides

| eslintrc | flat config |
| --- | --- |
| `extends: ['@nextcloud']` | `...recommended` (spread first) |
| `rules: { … }` at top level | a config object after the spread: `{ name: 'app/rules', files: ['**/*.{js,ts,vue}'], rules: { … } }` |
| `overrides: [{ files, rules }]` | one config object per override, same `files`/`rules` |
| `env: { node: true }` | `languageOptions: { globals: { ...globals.node } }` (`import globals from 'globals'`) |
| `globals: { FOO: 'readonly' }` | `languageOptions: { globals: { FOO: 'readonly' } }` |
| `.eslintignore` / `ignorePatterns` | `globalIgnores(['path/', '**/fixtures/'])` from `eslint/config` |
| `parser`, `parserOptions` | normally drop them; the preset sets the parsers |

Rules to keep in mind:

- **Order matters.** Later objects override earlier ones, so overrides go after
  `...recommended`.
- **Give each object a `name`.** It shows up in `--inspect-config` and in error
  messages.
- **Rule names changed.** Core and `standard` style rules moved to
  `@stylistic/*` (`indent` → `@stylistic/indent`, `comma-dangle` →
  `@stylistic/comma-dangle`). A `rules` entry or `eslint-disable` comment that
  uses the old name no longer does anything, or errors as an unknown rule.
  `jsdoc/*`, `vue/*` and `@nextcloud/*` names did not change.
- **Many old ignores are now built in.** All of `.gitignore`, plus `dist/`,
  `js/`, `l10n/`, `vendor/`, `vendor-bin/` and `**/package-lock.json`, are
  ignored automatically, and ESLint itself ignores `node_modules/`. Port only
  what is left.

Example. The v8 file

```js
module.exports = {
	extends: ['@nextcloud'],
	rules: {
		'jsdoc/require-jsdoc': 'off',
		'vue/first-attribute-linebreak': 'off',
	},
}
```

becomes

```js
import { recommended } from '@nextcloud/eslint-config'
import { defineConfig } from 'eslint/config'

export default defineConfig([
	...recommended,

	{
		name: 'app/rules',
		files: ['**/*.js', '**/*.ts', '**/*.vue'],
		rules: {
			'jsdoc/require-jsdoc': 'off',
		},
	},

	{
		name: 'app/vue-rules',
		files: ['**/*.vue'],
		rules: {
			'vue/first-attribute-linebreak': 'off',
		},
	},
])
```

Before porting an override, check whether you still need it. v9's defaults
differ from v8's, so some old overrides are no longer needed and others now
disable something new. `npx eslint --inspect-config` (step 7) shows which
config object sets each rule.

### 4. Delete the legacy config

```bash
rm .eslintrc.* .eslintignore     # whichever exist
```

Remove the `eslintConfig` key from `package.json` if it exists. Then check for
other places that point at the legacy setup: the `.editorconfig` comments,
`eslint-webpack-plugin` options, and the project's README or agent instructions.

### 5. Update the npm scripts

Flat config decides which files to lint, so the CLI no longer needs a path:

```json
"lint": "eslint",
"lint:fix": "eslint --fix"
```

`eslint` with no arguments lints the whole repo (minus ignores). That covers
`package.json`, `tsconfig.json`, other JSON files, and config files such as
`vite.config.ts` and `eslint.config.js`. To keep the old scope, use
`eslint src`. Then `package.json` key order is no longer checked, and tooling
config files are not linted at all.

`--ext` is not needed. Flat config selects file types with the `files` globs in
the preset.

### 6. Update CI

The org template `lint-eslint.yml` (nextcloud/.github) still lists the
eslintrc files in its `paths-filter` as of October 2026. Edit the copy in
your app so that changes to the new config still trigger the lint job:

```yaml
          filters: |
            src:
              - '.github/workflows/**'
              - 'src/**'
              - 'appinfo/info.xml'
              - 'package.json'
              - 'package-lock.json'
              - 'tsconfig.json'
              - 'eslint.config.*'      # replaces .eslintrc.* / .eslintignore
              - '**.js'
              - '**.ts'
              - '**.vue'
```

If the lint script now covers JSON (step 5), also add `'**.json'`.

The job itself (`npm ci && npm run lint`) needs no change. It reads Node from
`engines`, which you already raised in step 1.

**Dependabot.** From now on `eslint` and `@nextcloud/eslint-config` have to move
together. A group in `.github/dependabot.yml` prevents a bump of one that fails
because of the other:

```yaml
    groups:
      eslint:
        patterns:
          - 'eslint'
          - '@nextcloud/eslint-config'
```

### 7. Run, auto-fix, then fix the rest by hand

```bash
npx eslint --inspect-config    # opens a browser UI showing which config object sets each rule
npx eslint --print-config src/SomeFile.vue   # resolved config for one file, as JSON
npm run lint                   # first look: count and kinds of findings
npm run lint:fix               # applies everything fixable
git diff                       # review the auto-fixes before going further
npm run lint                   # what remains needs a person
```

Usually left after `--fix`:

- **Missing import extensions.** Add `.ts`/`.vue`/`.js` to relative imports.
  The editor offers a quick fix, but `--fix` does not apply it.
- **`no-console`.** Switch to `@nextcloud/logger`, or add a targeted
  `// eslint-disable-next-line no-console` with a reason.
- **Unused props/refs and deprecated-API warnings.** These are real code
  changes. Fix them, or turn off the rule *on purpose* in step 3.
- **Parsing errors in `.vue`.** This means the wrong preset: TS syntax in a
  `.vue` file under a `…Javascript` preset.

For a migration PR it is fine to turn off a noisy new rule temporarily
(with a `// TODO` in the config) and fix it in a follow-up PR. Keep this
PR about the config.

### 8. Verify

- [ ] `npm ci && npm run lint` passes from a clean checkout
- [ ] `npm run build` still passes (lint changes, import sorting in particular,
      can change module evaluation order; see below)
- [ ] the stylelint job is unaffected (`@nextcloud/stylelint-config` is a
      separate package)
- [ ] the editor ESLint integration picks up the flat config (VS Code ESLint
      extension v3+ supports it by default; restart the ESLint server)
- [ ] CI is green on the PR, including the `eslint` summary check
- [ ] the Dependabot PR is closed or superseded

## Gotchas

- **Import sorting can change runtime behaviour.** `perfectionist/sort-imports`
  moves side-effect imports (`import './foo.css'`, `import '@nextcloud/dialogs/style.css'`)
  into their own group, *after* the value imports. That is usually harmless.
  If an entry point depends on import order (a global set up before another
  module reads it), `app_api` turns the rule off for that reason. Check entry
  files after `--fix`.
- **`.vue` files with TypeScript are now fully supported.** With `recommended`,
  `<script setup lang="ts">` gets the TS parser. Any project workaround such as
  "no type annotations in `.vue`" or "put types in `.ts` files only" can be
  dropped, along with the documentation that describes it. Plain
  `import { SomeType }` of a type-only symbol is now an **error**
  (`consistent-type-imports`). Use `import type`.
- **`ESLint couldn't find an eslint.config.(js|mjs|cjs) file`.** The
  dependencies were bumped but step 2 was not done. This is exactly what an
  unattended Dependabot PR produces.
- **`SyntaxError: Cannot use import statement outside a module`** when loading
  the config: the file is `eslint.config.js` but `package.json` has no
  `"type": "module"`. Rename it to `eslint.config.mjs`.
- **`npm ci` EBADENGINE / unsupported engine** in CI: `engines.node` is
  below 22.14.
- **Stale `eslint-disable` comments** for rules that were renamed or removed
  (`indent`, `import/…`, `n/…`, `promise/…`) are reported as unused directives,
  or as rule definitions that don't exist. Delete them or update the rule name.
- **JSON linting surprises.** Files that are generated but not gitignored
  (for example `openapi.json`) get linted too. They usually pass
  (`@eslint/json` recommended only checks things like duplicate keys). If one
  doesn't, add it to `globalIgnores()` instead of editing generated output.

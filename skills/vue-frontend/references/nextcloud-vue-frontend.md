# Nextcloud Vue Frontend: Pitfalls and Conventions

What goes wrong in a Nextcloud app's Vue 3 frontend that lint and type-checks often
don't catch, and the conventions the apps follow.

- **Applies to:** Vue 3 + TypeScript frontends on `@nextcloud/vue` 9 (written against
  9.13–9.14), `@nextcloud/dialogs` 8, `@nextcloud/vite-config`, built by Vite
- **Sources:** problems hit in production apps (2026-09 to 2026-11). Library behaviour
  can change with any release: when an item stops being true, update it here.

---

## `@nextcloud/vue` 9 API drift

| Component | Correct | Wrong, and what happens |
|---|---|---|
| `NcButton`, `NcActions`, `NcDialogButton` | `variant="primary"` (`secondary`, `tertiary`, `tertiary-no-background`, …) | `type="primary"`: renders as `secondary` and emits an invalid HTML `type` (vue-tsc catches it) |
| `NcTextField`, `NcInputField`, `NcPasswordField` | `v-model="form.x"` (`modelValue` / `update:modelValue`) | `v-model:value`: type-checks, binds a deprecated prop and listens for an event that never fires; forms submit stale values. **Runtime only** |
| `NcCheckboxRadioSwitch` | `v-model` | `:checked` + `@update:checked`: shows the initial state, never toggles. **Runtime only** |

- Vue 3 has no `.sync`; use `v-model:prop`.
- **When unsure of an emit**, read it in
  `node_modules/@nextcloud/vue/dist/chunks/Nc*.mjs`.
- **`npm run typecheck` (`vue-tsc --noEmit`) is the only check that sees
  third-party prop types**; ESLint can't. Run it after every `@nextcloud/vue` bump.
  It does not catch runtime-only drift or CSS regressions: those need a look at the
  running app.
- **Internal class names** (`.button-vue`) are not API. Re-verify any rule that
  targets one after a major bump; a rename fails silently.

## Component quirks

- **`NcSelect` keeps a 260px minimum width** (`.nc-select.v-select.select`, 0,3,0).
  To size it, outrank that rule:
  `.x:global(.nc-select.v-select.select) { width: 100%; min-width: 0; max-width: none }`
  and size its container. Its list keeps vue-select's 160px minimum
  (`--vs-dropdown-min-width`) and is mounted on `<body>`; remove the minimum with a
  global rule on `.nc-select__dropdown.vs__dropdown-menu`.
- **`NcDateTimePickerNative` renders an `NcInputField` since 9.10**, whose root is
  `width: 100%` and claims a whole flex row. Wrap it in a fixed-width element; a class
  on the component itself loses to the scoped rule.
- **`NcTextField` shows its label inside the empty field**, so a placeholder never
  shows: put "(optional)" in the label.
- **`NcTextArea` doesn't grow with its text**; set its height from `scrollHeight` on
  input.
- **No Tooltip directive in v9**: icon-only buttons carry a native `title` with the
  same text as their `aria-label`.
- **`NcColorPicker`** models `string | undefined`; map `''` at that boundary.
- **Icons from `vue-material-design-icons`**: the package's `exports` map hides its
  type declarations, so every import is an implicit `any` under `noImplicitAny`. Add a
  shim `src/vue-material-design-icons.d.ts` (`declare module
  'vue-material-design-icons/*.vue'`); every icon takes `title`, `fillColor`
  (defaults to `currentColor`, so CSS `color` drives it) and `size`. Delete the shim
  if the package fixes its exports.

## Nextcloud core CSS vs app CSS

- **Every bare `<button>` is styled by core** (`core/css/inputs.css`:
  `button:not(.button-vue, [class^="vs__"])…`, specificity 0,2,1; 0,4,1 with
  `:hover`/`:focus`): `min-height: var(--default-clickable-area)`, `margin: 3px`,
  `width`, padding, background, border, bold. Symptoms: a control far taller than its
  CSS says.
  - If it navigates, make it an `<a href>`: core doesn't style bare anchors. Keep
    `@click.prevent` if the router needs JS handling.
  - If it's really a button, style it under its component's root class or double the
    class to clear 0,2,1, reset `background` on `:hover`/`:focus` too, and use
    `margin: 0 !important`. `NcButton`s aren't affected.
- **A plain `<input>`** gets core's 2px border, not the `NcTextField` look; copy
  `NcInputField`'s rules (no border, a box-shadow ring) when you must use one.
- **`input.checkbox + label::before`** has an uneven margin (3px before, 6px after).
- **CSS modules rename every class in their selectors**, core's too:
  `input.checkbox` becomes `input._checkbox_x1y2z` and matches nothing, silently.
  Write classes you don't own as `:global(.checkbox)`.
- **A library component's scoped root rule is 0,2,0** (`.button-vue[data-v-…]`) and
  its stylesheet tends to load after the app's, so two classes tie and lose: use
  three to change its `display`.
- **Win on specificity, never on chunk order**: the order of CSS chunks in the build
  is not something to rely on. When doubling one rule, check you haven't made it tie with a hide
  rule that needs to win.
- **Verify layout against the server's own stylesheets**, not just its variables: a
  test page with `--color-*` but without `core/css/inputs.css` measures a design the
  real page doesn't produce. Use a server checkout of
  the target major.
- Prefix generic layout class names with the app's prefix: core styles some bare
  names globally (`.pager`).

## Theme colours

- **Status colours are pairs: the plain token is the fill, `-text` is the ink.** In
  NC 34's default theme `--color-warning` is `#FFEEC5` and `--color-warning-text`
  `#664700`; the dark theme swaps them. `color: var(--color-warning)` paints
  near-white text on white. Same for `error`, `info`, `success`. Only the `-text` half
  stays readable in both themes. Values: `apps/theming/lib/Themes/{Default,Dark}Theme.php`.
- Charts: the `charts` skill. App icons: the `app-icons` skill.

## Dialogs, toasts, native UI

- **Only toolkit UI**: `@nextcloud/vue` components; `NcDialog` (with `NcButton`s in
  `#actions`, opened by a reactive ref) for prompts and confirms; `@nextcloud/dialogs`
  for toasts (`showError`/`showSuccess`, which return a `ToastHandle`). Never
  `window.prompt/confirm/alert`, never unstyled raw controls.
- **`@nextcloud/dialogs` 8**: its entry points inject their own styles and
  the `style.css` export is gone, so importing it breaks the build. If toasts vanish,
  check the toast container's `position: fixed` first. Toasts sit at the bottom start
  by design; shift them with `--toast-offset-block-end`.

## Talking to the backend

- **`generateOcsUrl(url, params)` runs `encodeURIComponent` on every `{param}`**, so a
  multi-segment path in one param becomes `dev%2Flogs` and 404s. Interpolate the path
  into the template instead.
- Error messages: the `ocs-errors` skill (it also covers `?format=json`).

## Dates and locale

- **First day of the week: `getFirstDay()` from `@nextcloud/l10n`** (0 = Sunday …
  6 = Saturday). It reads the value the server injects from the user's Nextcloud
  locale, so it is the same in every browser and matches the user's setting. Don't
  use `Intl.Locale` week info: Chromium exposes a `weekInfo` property, Firefox
  only a `getWeekInfo()` method, and they disagree for locales without a region.
- Day and month labels: `getDayNames()`, `getDayNamesShort()`, `getDayNamesMin()`,
  `getMonthNames()`, `getMonthNamesShort()` from the same package.

## Build and CI wiring

- **Vite entry keys map to output names `<app>-<key>`**; PHP's
  `Util::addScript('<app>', '<app>-<key>')` (and `addStyle` for settings panels, see
  the `php-backend` skill) must match.
- **`js/` and `css/` are disposable build output**, gitignored and emptied on every
  build (`css/` only with `emptyOutputDirectory: { additionalDirectories: ['css'] }`,
  or hashed chunks pile up). Never edit or store anything there.
- **`package-lock.json` is committed**; CI and the Makefile use `npm ci`. Change
  dependencies with `npm install`, then commit the lockfile.
- **CI templates call `npm run ts:check` and `npm run test` with `--if-present`.**
  Keep both names (aliases of `typecheck`/`test:frontend` are fine); rename one and
  its job goes green running nothing.
- **Node version:** `.nvmrc` and `package.json` `engines` change together; CI reads
  `engines` (node and npm) with no fallback.
- **Dependabot majors gated by Nextcloud tooling peers** (e.g. vite 8 while
  `@nextcloud/vite-config` pins `vite ^7`; TypeScript 6 while
  `@nextcloud/eslint-config` 8 pins `typescript ^5`) fail at `npm ci` with
  `ERESOLVE`. Bump the Nextcloud package first; never force with
  `--legacy-peer-deps`.

## Lint

- Moving from `@nextcloud/eslint-config` 8 to 9: the `eslint-v9-migration` skill.
- **On v8, TypeScript in `.vue` files needs `@nextcloud/eslint-config/vue3`**; the
  base `@nextcloud` config parses `<script>` with Babel and fails on type syntax.
  Keeping type syntax out of `.vue` files works around it but isn't the fix.
- Stylelint extends `@nextcloud/stylelint-config`, not the transitive
  `stylelint-config-recommended-vue` ("No rules found").

## Frontend tests

- Vitest with `happy-dom`, its config separate from `vite.config.ts`.
- **Keep testable logic in plain `.ts` modules** and use `import type` across
  modules, so tests don't pull `@nextcloud/*` runtime imports. Modules that must
  import them stay thin.
- To cross a DST change in date logic, run tests in a fixed zone
  (`TZ=Europe/Berlin` in `vitest.config.ts`).

---
name: vue-frontend
description: "Pitfalls in Nextcloud app Vue 3 frontends with @nextcloud/vue 9: API drift that fails only at runtime, component sizing quirks, Nextcloud core CSS overriding app styles, theme colour pairs, dialogs, confirmations and toasts, build, dependency and CI wiring. This skill should be used when writing or reviewing .vue, .ts or CSS frontend code, when adding a dialog, confirmation or toast, when showing weeks or calendars (first day of week), when bumping @nextcloud/vue or any frontend dependency (including Dependabot bumps that fail npm ci), and whenever a control or form silently doesn't update or sends empty or stale values, renders too tall, ignores its CSS, or a toast disappears."
paths: "src/**/*.vue, src/**/*.css, src/**/*.scss, vite.config.*, package.json"
---

# Nextcloud Vue frontend

The rules most often broken (details and reasons in the guide):
- **@nextcloud/vue 9:** `NcButton` takes `variant` (not `type`); field components
  (`NcTextField`, `NcInputField`, `NcPasswordField`) take plain `v-model`, not
  `v-model:value`; `NcCheckboxRadioSwitch` takes `v-model`, not
  `:checked`/`@update:checked`. The last two **type-check and fail silently at
  runtime**: say what needs checking in the running app.
- **Run `npm run typecheck` after every `@nextcloud/vue` bump.**
- **`NcAppNavigation` needs `aria-label` (or `aria-labelledby`)**: without one it
  logs a console warning and the navigation landmark has no name.
- **Core CSS styles every bare `<button>`** at (0,2,1): make links `<a href>`, or
  double the class and reset explicitly. Win on specificity, never on load order.
  In a CSS module, write core and library classes as `:global(.name)`.
- **Status colours come in pairs:** `--color-warning` is a background,
  `--color-warning-text` the text (same for error, info, success).
- **Toolkit only:** `NcDialog` for prompts and confirms, `@nextcloud/dialogs` for
  toasts; never `window.confirm/alert/prompt`. Since dialogs v8, don't import
  `@nextcloud/dialogs/style.css`.
- **Create buttons are "New X" with the `Plus.vue` icon.** An on/off icon button
  shows the state in its icon and names the action, without `aria-pressed`.
  Place display controls and actions consistently across views.
- **First day of week: `getFirstDay()` from `@nextcloud/l10n`**, never
  `Intl.Locale` week info (browsers disagree, and it ignores the user's setting).
- **`generateOcsUrl` encodes `/` inside a `{param}`**: interpolate multi-segment
  paths into the template.
- **CI templates call `npm run ts:check` and `npm run test` with `--if-present`**:
  keep those script names (as aliases), or the jobs pass while testing nothing.

Read `${CLAUDE_SKILL_DIR}/references/nextcloud-vue-frontend.md` before frontend work in an
unfamiliar area, after a dependency bump, or when a control misbehaves. Related
skills: `responsive-layout`, `charts`, `ocs-errors`, `app-icons`, `eslint-v9-migration`.

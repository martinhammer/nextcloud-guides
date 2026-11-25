---
name: dashboard-widget
description: "Building a Nextcloud Dashboard widget: choosing an API widget (IAPIWidgetV2, no frontend code) or a Vue widget (IWidget + OCA.Dashboard.register), the cost of load() on every dashboard visit, panel size, icon URLs, buttons, reload, and the permanent widget id. This skill should be used when adding, changing or reviewing a dashboard widget (lib/Dashboard, a dashboard entry point in src/), and when a widget slows the dashboard, shows no icon, loses its buttons, or vanishes from users' layouts."
paths: "lib/Dashboard/**, src/dashboard*, src/**/*Widget*.vue"
---

# Nextcloud Dashboard widgets

Sources: the developer manual's Dashboard page
(`docs.nextcloud.com/server/latest/developer_manual/digging_deeper/dashboard.html`),
and behaviour checked in apps on Nextcloud 33–36 (November 2026).

## Pick the kind first

- **List-shaped content** (items with a title, subtitle, link and icon): an
  **API widget**. Implement `IAPIWidgetV2::getItemsV2()` returning `WidgetItems`
  (items, `emptyContentMessage`, optional `halfEmptyContentMessage`). The
  Dashboard app renders it; there is no frontend code and `load()` stays empty.
  The same items reach the mobile and desktop clients through
  `/ocs/v2.php/apps/dashboard/api/v1/widget-items`. The manual recommends this
  kind for performance. Add `IReloadableWidget::getReloadInterval()` (seconds,
  V2 only) for refresh, `IButtonWidget` for buttons, and `IOptionWidget` for round
  item icons.
- **Custom rendering** (a heatmap, a carousel, controls): a **Vue widget**,
  `IWidget` plus `OCA.Dashboard.register(id, callback)` in your own script.
- Register either kind in `Application::register()` with
  `$context->registerDashboardWidget(MyWidget::class)`. `getOrder()` is 10–100
  (0–9 are reserved for shipped apps). `IConditionalWidget::isEnabled()` hides a
  widget that doesn't apply.

## Vue widgets

- **`load()` runs for every registered widget on every dashboard visit**, whether
  or not the user has added the widget. Keep what it adds tiny: a small entry
  that only registers the callback and imports the widget code when the dashboard
  calls it, plus a small always-loaded stylesheet for the header icon class.

  ```ts
  // src/dashboard.ts: loaded on every dashboard visit
  import './dashboard.css'
  const WIDGET_ID = 'myapp-widget' // = MyWidget::ID

  let unmountPrevious: (() => void) | null = null
  document.addEventListener('DOMContentLoaded', () => {
  	window.OCA?.Dashboard?.register(WIDGET_ID, async (el: HTMLElement) => {
  		const { mountWidget } = await import('./dashboardApp.ts')
  		unmountPrevious?.() // re-adding the widget calls back with a new element
  		unmountPrevious = mountWidget(el)
  	})
  })
  ```
- Data the widget needs at once can come through
  `IInitialState::provideInitialState()` in `load()`, which saves a request. Only
  pass cheap data: `load()` runs for users who never added the widget.
- **Mount your own Vue 3 app into `el`.** Don't depend on the host's Vue: the
  dashboard was Vue 2 through Nextcloud 34 and is Vue 3 from 35.
- **Vue widgets get no `IButtonWidget` buttons**: the dashboard renders those only
  for API widgets. Draw your own footer button.
- **Size:** the panel is 320px wide, leaving about **288 × 424px** of content. In
  the one-column layout (below 710px) the height is `auto`, so cap the widget at
  424px and scroll inside it.
- For a list look inside a Vue widget, use `NcDashboardWidget` /
  `NcDashboardWidgetItem` from `@nextcloud/vue` rather than restyling.

## Icons

- **`IIconWidget::getIconUrl()` must be absolute**:
  `$url->getAbsoluteURL($url->imagePath($appId, 'app-dark.svg'))`. A settings
  section's `IIconSection::getIcon()` takes the opposite, a relative
  `imagePath()`.
- The dashboard loads it as an image, not inlined, so point at the dark (black)
  variant; the theme inverts it in dark mode. File rules: the `app-icons` skill.
- `getIconClass()` is still part of `IWidget`; its CSS must be in the
  always-loaded stylesheet.
- Item icons in API widgets: a square SVG, or a JPG/PNG of at least 44 × 44px.

## The widget id is permanent

`getId()` is stored in every user's dashboard layout: renaming it silently
removes the widget for everyone. The PHP id and the id passed to
`OCA.Dashboard.register` must match; keep one constant on each side, each with a
comment naming the other. A substantially different widget gets a new id.

When a new Nextcloud major changes any of this, update this skill.

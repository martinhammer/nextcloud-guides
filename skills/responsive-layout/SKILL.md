---
name: responsive-layout
description: "Responsive layout in Nextcloud app frontends the way Nextcloud itself does it: the 1024/512 breakpoints from @nextcloud/vue, content-width steps for lists, NcAppContent list/detail, touch vs mouse, two-line cards. This skill should be used when building or reworking any view for narrow windows or phones, hiding columns, turning a table into cards, reacting to the sidebar or navigation, or picking a breakpoint, and when the navigation drawer stays open after picking a view on a phone or a navigation item changes the URL hash unexpectedly."
---

# Nextcloud responsive layout

Two questions, two tools:

1. **Which mode is this (phone or desktop)?** Window width, Nextcloud's numbers only:
   `useIsMobile()` (< 1024px) and `useIsSmallMobile()` (< 512px) from
   `@nextcloud/vue/composables/useIsMobile` in script; `@media (width < 1024px)` /
   `(width < 512px)` in CSS, commented as `MOBILE_BREAKPOINT`. Never an app's own
   number. Touch vs mouse: `@media (hover: none)` / `(hover: hover)`.
2. **How much room does this list or table have?** Measure the content area, never
   the window: the sidebar and the navigation change it without changing the window.
   CSS container queries when only styling changes; a `ResizeObserver` composable
   (as Files' `useFileListWidth`) when script must know. Default steps: 512 and
   1024 applied to that width; add a step only when the columns need it, with a
   comment saying why.

Before building: `@nextcloud/vue` already adapts `NcAppNavigation`, `NcAppSidebar`
and `NcAppContent` (list/detail with forced `no-split` on mobile). Use those, don't
rebuild them. One gap: a click on an `NcAppNavigationItem` closes the mobile
drawer only for router links (`to`); with `href` or `@click` items, emit
`toggle-navigation` `{ open: false }` on `@nextcloud/event-bus` yourself (see the
reference).

Read `${CLAUDE_SKILL_DIR}/references/nextcloud-responsive-layout.md` for the code (composable,
container setup, column steps, two-line cards, sort menu) and the widths to check.

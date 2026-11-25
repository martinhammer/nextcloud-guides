# Nextcloud Responsive Layout

How a Nextcloud app adapts to narrow windows, phones and an open sidebar the way
Nextcloud's own code does it, so every app switches at the same points and nobody
invents breakpoints again.

- **Applies to:** Vue 3 app frontends built on `@nextcloud/vue` 9
- **Researched against (2026-11-24):** `@nextcloud/vue` 9.14.1
  (`src/composables/useIsMobile`, `NcAppContent`, `NcAppNavigation`, `NcAppNavigationItem`
  `onClick`, `NcAppSidebar`);
  `nextcloud/server` master of 2026-10-25 (`apps/appstore/src/views/AppstoreNavigation.vue`,
  `apps/files/src/composables/useFileListWidth.ts`,
  `FilesListVirtual.vue`, `core/src/components/UnifiedSearch/UnifiedSearchInput.vue`,
  `apps/comments`); `nextcloud/mail` and `nextcloud/calendar` main of 2026-11-24;
  the developer manual (CSS variables, design layout pages)
- **Status:** precedent read in the code listed above; the card, sort-menu and touch
  patterns are in production use

---

## The rules

> 1. **Mode decisions use the window and Nextcloud's two breakpoints, 1024 and 512.**
> 2. **Space decisions use the content area's width, never the window.** Default
>    steps are the same 1024 and 512.
> 3. **Use what `@nextcloud/vue` already does** before building layout of your own.
> 4. **Touch is a capability, not a width:** `(hover: none)` / `(hover: hover)`.

## Where the numbers come from

The developer manual documents one value: `--breakpoint-mobile: 1024px`, "breakpoint
for mobile responsive layout (e.g. if app navigation should be always visible)". The
library defines both:

```ts
// @nextcloud/vue src/composables/useIsMobile
export const MOBILE_BREAKPOINT = 1024
export const MOBILE_SMALL_BREAKPOINT = MOBILE_BREAKPOINT / 2   // 512
```

measured as `document.documentElement.clientWidth`, exposed as `useIsMobile()` and
`useIsSmallMobile()`. The library's own SCSS uses `$breakpoint-mobile: 1024px` and
`$breakpoint-small-mobile` (512px). It uses no container queries.

What the reference apps do:

| App | Mode | Space |
|---|---|---|
| **Files** | library breakpoints | `useFileListWidth()`: a `ResizeObserver` on `#app-content-vue`; wide ≥ 1024 (MIME column shown), medium 512–1023, narrow < 512 (mtime and size columns, inline actions dropped). Columns are left out by computed props, not hidden with CSS |
| **Mail** | `useIsMobile`; copies `$breakpoint-mobile: 1024px` into its own `css/variables.scss` | `NcAppContent` list/detail with a user-selectable layout |
| **Calendar** | some `useIsMobile` | delegated to FullCalendar plus a `ResizeObserver` on the grid; scattered one-off breakpoints (767–1000px). Not a model |
| **Server core** (Unified Search, Comments) | | CSS container queries keyed to the component's own width, "not the viewport, so it holds however crowded the header gets" |

## What the library already does

- **`NcAppNavigation`** starts closed on mobile and becomes an overlay with a focus trap.
  It closes itself on a click outside it and on Escape. **A click on an item closes it
  only for router links**: `NcAppNavigationItem`'s `onClick` emits `toggle-navigation`
  only when the item has a `routerLinkHref` (a `to` prop) and the window is mobile.
  Items with `href` (hash routing) or a plain `@click` leave the drawer open over the
  view just picked. Close it yourself the way the library does, on the event bus
  (`NcAppNavigation` has no controlled `open` prop; Nextcloud's App Store app
  uses the same event, there to open it):

  ```ts
  import { emit } from '@nextcloud/event-bus'   // declare it in package.json
  import { useIsMobile } from '@nextcloud/vue/composables/useIsMobile'

  const isMobile = useIsMobile()
  function closeNavigationOnMobile(event: MouseEvent): void {
  	// a modifier-key click opens a new tab: leave the drawer as it is
  	if (!isMobile.value || event.metaKey || event.altKey || event.ctrlKey || event.shiftKey) return
  	emit('toggle-navigation', { open: false })
  }
  ```

  and put `@click="closeNavigationOnMobile"` on each `NcAppNavigationItem`, keeping
  its `href` so open-in-new-tab still works.
- **An `NcAppNavigationItem` with neither `to` nor `href` renders `<a href="#">`**
  (`href || routerLinkHref || '#'`). A click on it sets the URL hash to `#`, which a
  hash-routed app reads as a navigation, and adds a history entry. Give such items
  `@click.prevent="…"`, or a real `href`.
- **`NcAppSidebar`** is `clamp(300px, 27vw, 500px)` wide, so on a desktop it takes up
  to 500px from the content area; below 512px it becomes full width (`100vw`).
- **`NcAppContent`** with a `list` slot: `layout` `vertical-split` (resizable list,
  `listSize`/`listMinWidth`/`listMaxWidth` in %), `horizontal-split` or `no-split`;
  **`no-split` is forced on mobile**, with `v-model:showDetails` and a back arrow.
  Use it for any list → detail screen instead of a hand-built split.

## Mode decisions

Script:

```ts
import { useIsMobile, useIsSmallMobile } from '@nextcloud/vue/composables/useIsMobile'
const isMobile = useIsMobile()            // < 1024px window
```

CSS (a custom property can't be used inside a media query, so the number is written
out):

```css
/* MOBILE_BREAKPOINT (@nextcloud/vue useIsMobile) */
@media (width < 1024px) { … }
/* MOBILE_SMALL_BREAKPOINT */
@media (width < 512px) { … }
```

Use mode for: per-device preferences (e.g. one stored value for desktop and one for
mobile, chosen by `useIsMobile()`), anything tied to the navigation becoming an
overlay (e.g. an extra "Add" button because the navigation entry is out of sight),
and layout of things that follow the window, not the content.

## Space decisions

### CSS only: container queries

```css
/* the view's root: its width is what the columns have */
.xx-list-view {
	container-type: inline-size;
	container-name: xx-list;
}

/* steps as exclusive ranges, so a narrower step never has to undo a wider one */
@container xx-list (512px <= width < 1024px) { /* drop the least-scanned columns */ }
@container xx-list (width < 512px)           { /* two-line cards */ }
```

- Put the container on the view's own root, not on a shared wrapper that other
  screens also use.
- A container query can't take a custom property either: each literal must be
  repeated, so comment every copy with where the others are.

### When script must know: a content-width composable

Modelled on Files' `useFileListWidth()`:

```ts
import { computed, onMounted, readonly, ref } from 'vue'

const width = ref(0)
let observed: HTMLElement | undefined
const observer = new ResizeObserver(([entry]) => {
	width.value = entry?.contentBoxSize?.[0]?.inlineSize ?? entry?.contentRect.width ?? 0
})

function observe() {
	const el = document.querySelector<HTMLElement>('#app-content-vue') ?? document.body
	if (el !== observed) {
		if (observed) observer.unobserve(observed)
		observer.observe(el)
		observed = el
	}
}

export function useContentWidth() {
	onMounted(observe)
	observe()
	return {
		width: readonly(width),
		isWide: computed(() => width.value >= 1024),
		isMedium: computed(() => width.value >= 512 && width.value < 1024),
		isNarrow: computed(() => width.value < 512),
	}
}
```

Leave columns out with computed flags (`v-if`), as Files does, when the data or
accessibility tree should change too; hide them with container queries when only the
look changes.

### Extra steps

The defaults are 1024 and 512 of content width. Add a step only when a list's fixed
columns plus gaps plus padding plus a floor for the flexible column don't fit, and
write that sum in a comment next to it so it can be recomputed when a column changes.

## Narrow rows: two-line cards

When the heading row no longer fits, each row becomes a two-line card: **the same
cells in the same order, only placed differently**, so no second `v-if` list.

```css
@container xx-list (width < 512px) {
	.xx-row {
		grid-template-columns: max-content minmax(0, 1fr) auto auto;
		grid-template-areas:
			'title  title title status'
			'when   where kind  kind';
	}
	.xx-row > :nth-child(1) { grid-area: title; }
	/* … one rule per kept cell; the rest display: none */
}
```

Line one: what the row is and its state. Line two: when, where, what kind. Detail
that doesn't fit belongs in the sidebar or detail view, one tap away.

- Hide header cells and data cells with the **same** `nth-child`, so headings stay
  over their columns at every step.
- If rows change `display` away from table/grid semantics, give them explicit ARIA
  roles (`table`/`rowgroup`/`row`/`columnheader`/`cell`).

**Sorting without headings:** an `NcActions` menu of radio `NcActionButton`s built
from the view's own column list, emitting the column key into the view's existing
sort handler (no sort logic of its own). Listen to `@click`, not
`update:modelValue`: the radio only emits on a change, and picking the checked
column again must flip the order. Say the current order in words in the trigger's
`aria-label`/`title`. Put the show/hide class on a wrapper element of your own, so
CSS doesn't have to outrank `NcActions`' scoped rules.

## Touch

- Wrap hover styling in `@media (hover: hover)`: a touch screen keeps `:hover` on the
  last tapped element, which reads as a selection.
- Under `@media (hover: none)`, show what hover would reveal (e.g. a note button)
  and hide what fingers can't use: phone browsers don't start HTML drag and drop, so
  hide drag handles and offer Move up/down in a menu.

## Global CSS collisions

Nextcloud core styles some bare class names globally (`.pager` floats with a margin;
every bare `<button>` gets button styling). Prefix layout classes with the app's
short prefix (e.g. `xx-`).

## Testing

Widths to check by eye: 360px, 511 → 512px, 1023 → 1024px window; and at desktop width with the
sidebar open and with the navigation collapsed (content-width steps must react to
both). In unit tests, mock `ResizeObserver` (`jsdom-testing-mocks`, as Files does).

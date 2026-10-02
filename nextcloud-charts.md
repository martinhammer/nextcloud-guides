# Nextcloud Charts

How to draw charts in a Nextcloud app so they look native in **every** theme
(light, dark, both high-contrast themes, any accent colour the user picks), stay
readable, update when the theme changes, and look the same from one app to the next.
The examples use Chart.js through `vue-chartjs`. The theme rules apply to any library
that draws on a `<canvas>`.

- **Applies to:** Vue 3 app frontends drawing charts with Chart.js (or any canvas
  library), together with HTML around them (legends, ranked bars, stat tiles)
- **Verified on:** a live Nextcloud 34 instance in headless Chromium (values and
  behaviour captured below). The theming code involved (`ThemeInjectionService`,
  `ThemingController::getThemeStylesheet`, `core/templates/layout.user.php`) is the
  same in `stable34`, `stable35` and `master` as of October 2026. Chart.js 4.5,
  vue-chartjs 5.3.
- **Reference implementation:** flightjournal's `src/colorRamp.ts`,
  `src/chartTheme.ts`, `src/chartPlugins.ts` and `src/components/analytics/`

---

## The rules

> 1. **Read theme colours from `document.body`, never `document.documentElement`.**
> 2. **Derive every chart colour from the theme at runtime, as one palette for the
>    whole page.** No hard-coded hexes, no per-chart ramps, no `rgba()` fills.
> 3. **Re-read the theme when it can change**, and let Vue reactivity redraw the
>    charts.
> 4. **Set text, gridline and font colours explicitly.** Chart.js's defaults are
>    wrong on a dark theme.
> 5. **Never put a value only in a tooltip.** Label the marks, and give every canvas
>    a text alternative. Tooltips follow the pointer.

Each rule fixes a bug that shows up in real apps. The sections below explain the
mechanism, give the code, and end with a checklist.

## Where Nextcloud puts its colours

The theming app serves each theme as a stylesheet of CSS variables. *Where* those
variables are attached depends on how the user picked the theme
(`apps/theming/lib/Service/ThemeInjectionService.php`,
`ThemingController::getThemeStylesheet`):

| User's setting | Stylesheet | Variables set on |
| --- | --- | --- |
| Always loaded first | `default` theme, `plain=1` | `:root` |
| "System default" (follows the OS) | `light`, `dark`, `light-highcontrast`, `dark-highcontrast`, `plain=1`, each `<link>` carrying a `media` query (`prefers-color-scheme`, `prefers-contrast`) | `:root`, only while its media query matches |
| A theme chosen explicitly | that theme, not plain: `[data-theme-<id>] { … }` | `<body>`, which carries `data-theme-<id>` (`core/templates/layout.user.php`) |

So the user's chosen theme lives on **`<body>`**, and `<html>` keeps the
default/OS values. Captured from the live instance:

| Situation | `<html>` primary / background | `<body>` primary / background |
| --- | --- | --- |
| System default, light OS | `#00679e` / `#ffffff` | `#00679e` / `#ffffff` |
| System default, dark OS | `#0091f2` / `#171717` | `#0091f2` / `#171717` |
| **Dark chosen explicitly, light OS** | **`#00679e` / `#ffffff`** | `#0091f2` / `#171717` |

The last row is the bug. Code that reads
`getComputedStyle(document.documentElement)` draws a light-theme chart inside a dark
page for every user who chose a theme instead of following the OS. Reading
`document.body` (or the chart's own container) gets the value that is actually in
effect.

### The values differ by theme

Each theme computes its own primary *element* colour against its own background, so
the accent changes from theme to theme as well as the background. Stock values
(`/apps/theming/theme/<id>.css?plain=1`):

| Variable | default / light | dark | light-highcontrast | dark-highcontrast |
| --- | --- | --- | --- | --- |
| `--color-primary-element` | `#00679e` | `#0091f2` | `#005c88` | `#27abff` |
| `--color-main-background` | `#ffffff` | `#171717` | `#ffffff` | `#000000` |
| `--color-main-text` | `#222222` | `#EBEBEB` | `#000000` | `#ffffff` |
| `--color-text-maxcontrast` | `#6b6b6b` | `#999999` | `#000000` | `#ffffff` |
| `--color-border` | `#ededed` | `#292929` | `#808080` | `#808080` |
| `--color-primary-light` | `#e5eff5` | `#14232c` | `#e5eef3` | `#031119` |

A user's own accent goes through `Util::elementColor`, which only darkens or lightens
it until it reaches **3.2:1** against the background (5.6:1 in the high-contrast
themes). Expect primaries as pale as a mustard `#a98d00` on white. A palette that
only works for the stock blue is not finished.

### What `getPropertyValue` gives you

It returns the variable's text after `var()` substitution. The browser does not
convert it to a standard colour format. Seen on the live instance:

| Variable | Defined as | `getPropertyValue` returns |
| --- | --- | --- |
| `--color-main-text` (dark) | `#EBEBEB` | `#EBEBEB`, upper case |
| `--color-primary-element-light` | `var(--color-primary-light)` | `#e5eff5`, resolved |
| `--color-background-selection` | `rgb(from var(--color-primary-element) r g b / 0.2)` | `rgb(from #00679e r g b / 0.2)` |
| `--color-main-background-rgb` | `255,255,255` | `255,255,255`, not a colour at all |

Parse defensively: accept `#rgb`, `#rrggbb`, `#rrggbbaa` and `rgb()`/`rgba()`, and
return `null` for anything else so the caller falls back. A
`hex.slice(1, 3)` parser silently produces `rgba(NaN, NaN, NaN, …)`, and the chart
just loses its colour.

## Which variables to use

| Chart role | Variable |
| --- | --- |
| The palette (five opacities of it, see below) | `--color-primary-element` |
| A bar under the pointer; slice outlines | `--color-primary-element` at full strength |
| Values, direct labels | `--color-main-text` |
| Axis ticks, legend text, captions | `--color-text-maxcontrast` |
| Gridlines, axis lines (hairline) | `--color-border` |
| Chart surface; gaps between touching marks | `--color-main-background` |
| Unfilled track behind a bar or meter (HTML) | `--color-primary-light` |
| Canvas font | `--font-face`, which picks up the dyslexia font when it is on |

## Building the palette

**One palette for the whole page.** Every chart draws from the same small set of
shades, so a given shade means the same thing wherever it appears. When charts
derive their own ramps (different step counts, different extension rules), two
doughnuts beside each other end up in visibly different blues. That happened, and
is the reason for this rule.

The palette is the solid `--color-primary-element` at **five opacities: 20%, 36%,
53%, 69%, 85%**. The ends are tickbuddy's polar-chart range, and the steps are even
between them. Implement each as the opaque colour that opacity produces over the page
background (plain sRGB compositing, `c·α + bg·(1−α)`), not as an `rgba()` fill. On the
plain surface the two look identical. The opaque version keeps HTML swatches matching
their canvas marks and keeps the contrast measurable.

| Theme | Palette, faintest → strongest |
| --- | --- |
| light (`#00679e` on `#ffffff`) | `#cce1ec #a3c8dc #79afcc #5097bc #267ead` |
| dark (`#0091f2` on `#171717`) | `#122f43 #0f4366 #0b578a #076bae #037fd1` |
| light high contrast (`#005c88`) | `#ccdee7 #a3c4d4 #79a9c1 #508fad #26749a` |
| dark high contrast (`#27abff` on `#000000`) | `#082233 #0e3e5c #145a86 #1b76af #2191d9` |

On all four stock themes the palette passes the ordinal ramp checks: lightness
increases at every step, adjacent steps are at least ΔL 0.06 apart, and it stays one
hue. A few extreme user accents near Nextcloud's 3.2:1 element floor bunch the steps
closer than that: bright yellow, lime or cyan on light, a dark navy on dark. The
outlines and legends still separate the slices, but the shades alone read less
clearly.

**The faintest steps need an outline.** 20% of the primary is about 1.3:1 against
the background, well below the 2:1 a filled mark needs on its own. So **every sliced
chart (doughnut, polar area) outlines its slices with a 1px solid primary line**. The
outline carries the shape and the shade only grades it, which is how tickbuddy's pale
polar slices work. Don't use the palette's pale steps on unoutlined marks.

**How each chart uses it:**

| Chart | Shades |
| --- | --- |
| Single series (bars, ranked bars, meters, rings) | Step 4 (69%), with no outline, so a pale accent is lifted to keep 3:1; solid primary on hover |
| Ordered categories (economy → first) | Fixed steps per category, so a category's shade never changes with the data. Start at step 2 if the first category usually dominates, so the largest slice isn't the faintest. |
| Unordered categories ranked by count (manufacturers) | Largest → step 5, then 4, then 3 |
| Shading by value (polar area) | The value's position between min and max, rounded to the nearest of the five steps |
| "Other", "no data" | Not a step. Use a neutral grey: `--color-text-maxcontrast` mixed toward the background to 2.2:1. |

**Don't split a series just because you can.** A per-month chart stacked by
short/medium/long haul looked informative but read as noise and was removed in
favour of one series. Add a breakdown only when the reader needs it.

**Unordered categories → rank them, then fold the tail.** Manufacturers and
airlines have no natural order. Graded shades of one colour would suggest one, so
order them by count, which makes the shading encode rank rather than an order that
isn't there. A ranked list (one colour) is the plainest form. A doughnut works too
if it names only the top three, puts the rest in a neutral-grey "Other" slice, and
labels every slice in a legend with its count. "Other" drills through to all of its
members at once. If you need more unordered colours than that, use a fixed
categorical palette tested for colour blindness; don't try to derive one from the
accent.

### Why not fixed hexes

They ignore the user's accent, and they need a second set for dark mode, a third and
fourth for the high-contrast themes, and they still break the first time an admin
sets a corporate colour.

### One palette for canvas and HTML

Legend swatches, ranked bars and meters are HTML. Publish the palette as CSS custom
properties on the view's root (`--app-chart-primary`, `--app-palette-1…5`) and use
those variables in CSS. The canvas and the HTML then read from a single computation,
so they can't drift apart.

## Reading the theme in code

```ts
// chartTheme.ts (abridged; parseColor / blend / soften / towardBackground live in a
// dependency-free colorRamp.ts so they can be unit-tested and run under Node)
export const PALETTE_OPACITY = [0.2, 0.3625, 0.525, 0.6875, 0.85] as const
export const FILL_OPACITY = PALETTE_OPACITY[3] // single-series fills

export function readChartTheme(el: Element = document.body): ChartTheme {
	const style = getComputedStyle(el)
	const color = (name: string, fallback: string) =>
		parseColor(style.getPropertyValue(name)) ?? parseColor(fallback)!
	const primary = color('--color-primary-element', '#00679e')
	const surface = color('--color-main-background', '#ffffff')
	const text = color('--color-main-text', '#222222')
	const textMuted = color('--color-text-maxcontrast', '#6b6b6b')
	return {
		// Single-series fills: palette step 4, raised only if needed for 3:1.
		primary: toHex(soften(primary, surface, FILL_OPACITY, 3)),
		primarySolid: toHex(primary), // hover, outlines
		text: toHex(text),
		textMuted: toHex(textMuted),
		grid: toHex(color('--color-border', '#ededed')),
		surface: toHex(surface),
		neutral: toHex(towardBackground(textMuted, surface, 2.2)),
		font: style.getPropertyValue('--font-face').trim() || 'system-ui, sans-serif',
		palette: PALETTE_OPACITY.map((o) => toHex(blend(primary, surface, o))),
	}
}
```

The fallbacks are the stock light theme. They are for tests and for a theme that
emits syntax the parser doesn't handle. They should never be what a real page draws.

## Keeping it live

Two things can change the theme while your page is open:

| Trigger | What changes | Signal |
| --- | --- | --- |
| The OS switches light/dark or contrast, while the user's theme is "System default" | A different `media`-gated sheet applies to `:root` | `matchMedia('(prefers-color-scheme: dark)')` and `('(prefers-contrast: more)')` fire `change` |
| The theming settings toggle themes in place (`apps/theming/src/views/UserTheming.vue`) | `data-theme-*` and `data-themes` on `<body>` | A `MutationObserver` on `body`'s `data-themes` attribute |

An accent or theme changed on the settings page reaches your page on its next load,
which a read on mount picks up.

```ts
export function useChartTheme(): Readonly<Ref<ChartTheme>> {
	const theme = ref(readChartTheme())
	// Wait a frame so the switched stylesheet has applied before reading.
	const refresh = () => requestAnimationFrame(() => { theme.value = readChartTheme() })
	const queries = ['(prefers-color-scheme: dark)', '(prefers-contrast: more)']
		.map((q) => window.matchMedia?.(q)).filter(Boolean) as MediaQueryList[]
	const observer = typeof MutationObserver === 'undefined' ? null : new MutationObserver(refresh)
	onMounted(() => {
		theme.value = readChartTheme()
		queries.forEach((q) => q.addEventListener('change', refresh))
		observer?.observe(document.body, { attributes: true, attributeFilter: ['data-themes'] })
	})
	onBeforeUnmount(() => {
		queries.forEach((q) => q.removeEventListener('change', refresh))
		observer?.disconnect()
	})
	return readonly(theme) as Readonly<Ref<ChartTheme>>
}
```

Build each chart's `data` and `options` as a `computed` over this ref. A theme change
then produces new objects, and vue-chartjs updates the chart. **Verified live:** after
switching the emulated OS scheme from light to dark mid-session, every one of the
19,519 bar pixels on a single-series chart changed from `#00679e` to `#0091f2`,
with no reload.

Reading the theme once, in a plain `onMounted`, works until the first OS switch. From
then on the charts show the old theme next to a re-themed page.

## Chart.js setup

### Register only what you use, and lazy-load the view

```ts
import { ArcElement, BarElement, CategoryScale, Chart, LinearScale, Tooltip } from 'chart.js'
Chart.register(ArcElement, BarElement, CategoryScale, LinearScale, Tooltip)
// vue-chartjs's <Bar> / <Doughnut> register their own controllers.
```

```ts
// router.ts — keeps Chart.js out of the main chunk
const AnalyticsView = () => import('./views/AnalyticsView.vue')
```

For scale: flightjournal's lazy Analytics chunk, which contains Chart.js plus the
view, is 65 kB gzipped. Its main entry chunk contains no Chart.js code.

### Set the theme on every chart; don't rely on the defaults

Chart.js's own defaults (`helpers.dataset.js`, 4.5) are `color: '#666'` and
`borderColor: 'rgba(0,0,0,0.1)'`. `#666` text is 3.1:1 on the dark background, and a
10% black gridline is invisible on it. Build the shared, theme-dependent part once
and spread it into every chart's options:

```ts
export function baseChartOptions(theme: ChartTheme): ChartOptions<'bar'> {
	const axis = {
		grid: { color: theme.grid, tickColor: theme.grid },
		border: { color: theme.grid },
		ticks: { color: theme.textMuted, font: { family: theme.font } },
	}
	return {
		responsive: true,
		maintainAspectRatio: false,
		animation: false,
		font: { family: theme.font },
		color: theme.textMuted,
		scales: { x: { ...axis }, y: { ...axis } },
		plugins: {
			legend: { display: false }, // legends are HTML; see below
			tooltip: {
				position: 'cursor', // follow the pointer; see below
				caretPadding: 8,
				titleFont: { family: theme.font },
				bodyFont: { family: theme.font },
			},
		},
	}
}
```

Passing these options to each chart, rather than setting `Chart.defaults`, means a
theme change re-renders through normal reactivity and no global state needs
changing. If you do use `Chart.defaults`, you also have to call `update()` on every
chart afterwards.

A custom plugin that draws text should take its colour and font from its plugin
options, which you fill from the theme. Don't use `ctx.font = '11px sans-serif'` or
`Chart.defaults.color`.

### Tooltips follow the pointer

By default Chart.js pins the tooltip to the mark (the top of a bar, the centre of a
slice). It looks fixed in place while the mouse moves across the bar. Register a
positioner that returns the pointer position, and use it on every chart:

```ts
import { Tooltip, type ChartType, type TooltipPositionerFunction } from 'chart.js'

declare module 'chart.js' {
	interface TooltipPositionerMap {
		cursor: TooltipPositionerFunction<ChartType>
	}
}

Tooltip.positioners.cursor = (_elements, eventPosition) =>
	(eventPosition ? { x: eventPosition.x, y: eventPosition.y } : false)
```

Chart.js runs the positioner again on every pointer move and redraws when the
result changes (`Tooltip._positionChanged`), so no extra event handling is needed.
Verified live: hovering one column at two heights moved the box with the pointer,
and near the right edge it flips to the left side as usual. Pair it with
`interaction`/tooltip `mode: 'index', intersect: false` (plus `axis: 'y'` on
horizontal bars, see Drill-through), so anywhere in a column counts, not just the
bar itself. For single-series charts also set
`displayColors: false`, because a colour square in the box tells the reader nothing.

**Make the tooltip's colour box a plain swatch.** Chart.js draws the box as an outer
square filled with `multiKeyBackground` (white by default) and outlined in the
element's *border* colour, with the fill inset by 1px on top. With the surface-coloured
gaps recommended below, that border is white, so every swatch gets a white ring. Set
`multiKeyBackground: 'transparent'` and return the element's own colour for both
fields from `callbacks.labelColor`:

```ts
tooltip: {
	multiKeyBackground: 'transparent',
	boxPadding: 4,
	callbacks: {
		labelColor: (item) => {
			const color = segments[item.dataIndex].color
			return { borderColor: color, backgroundColor: color, borderRadius: 2 }
		},
	},
},
```

### Drill-through: every element or none

If one chart on a screen opens the underlying records when clicked, users will
expect every chart to. A screen where only some are clickable feels broken. Make
every countable element drill through to the app's filtered list, including ranked
rows and record cards. Leave out only things with nothing to filter, such as a total
or an Earth-circumference figure.

- **Use the same `interaction` for hover, tooltip and click**:
  `interaction: { mode: 'index', intersect: false }`, so a click anywhere in the
  column a tooltip is showing for opens that column. **On horizontal bars add
  `axis: 'y'`.** `index` mode searches along x by default, which compares the pointer
  with the bar *ends* and highlights whichever bar happens to end nearest, often a
  different row from the one under the pointer.
- **Let the chart component emit, and the view navigate.** For example
  `emit('select', index)` from `onClick(_, elements)`. The view then turns an index
  into a filter. Don't emit for an empty bar.
- **Show that it is clickable**: set the canvas cursor to `pointer` in `onHover` while
  over a clickable element, and add a tooltip footer such as "Click to see these
  flights" (normal weight, since it is a hint rather than data).
- **The element's count must equal the filtered list's count.** Key each aggregation
  by exactly the value its filter matches, using the same bin edges and the same date
  parsing, and test each one by passing it back through the filter. A bar reading 12
  that opens 11 rows destroys trust in every chart on the page.
- **Replace, don't merge, a filter of the same kind.** Clicking "> 8,000 km" must
  remove an existing `distanceMax`, not keep it.
- Canvas clicks have **no keyboard path**. Make sure the same filters are reachable
  from the list view's own filter controls.

### vue-chartjs details

- **Options are shallow-merged.** On a change, vue-chartjs runs
  `Object.assign(chart.options, nextOptions)` and then `update()`. Always pass complete
  top-level objects (`scales`, `plugins`). A top-level key you *remove* stays on the
  chart.
- **Datasets are matched by `label`** (`datasetIdKey` defaults to `'label'`). Give
  each series a stable, unique label, otherwise updates apply to the wrong series.
- **`aria-label` is a prop** that vue-chartjs puts on the `<canvas role="img">`. If
  you wrap it in your own component, don't call your prop `ariaLabel`: `vue-tsc`
  treats `aria-label="…"` in a parent template as an HTML attribute and reports the
  required prop as missing. Use a name such as `summary` and pass it on.

## Marks and layout

| Element | Spec |
| --- | --- |
| Bars | `maxBarThickness: 24`, `borderRadius: 4`, `borderSkipped: 'start'` (square at the baseline) |
| Fills | Palette step 4 (69%, never below 3:1); `hoverBackgroundColor` = the solid primary |
| Doughnut and polar slices | Palette shades with a 1px **solid primary outline** (`borderColor: primarySolid`, `borderWidth: 1`). The outline is what lets the pale steps read. |
| Stacked bar segments | A 2px gap in the **surface colour**: `borderColor: theme.surface`, `borderWidth: { top: 2 }` (`{ right: 2 }` for horizontal bars). Only with steps of 2:1 or more, since they have no outline. |
| Gridlines and axes | 1px, solid, `--color-border`. Hide them when every bar is labelled. |
| Value labels | At the end of each bar, or on top of each stack, in `--color-main-text`, never in the series colour |
| Legend | HTML, present for 2+ series, absent for 1. Swatches use the published CSS variables. |
| Doughnut | Part-to-whole only, 6 segments or fewer. Use bars to compare similar values. |
| Bubbles on ranked rows (top routes: x = distance, size = flights) | One row per item, top-ranked at the top (a linear y-axis from −0.5 to n−0.5, not a category scale, which bubbles don't support). **Set the ticks yourself** in `afterBuildTicks` (`scale.ticks = rows.map((_, i) => ({ value: i }))`). With both bounds fixed, Chart.js counts from `min` and puts every tick at −0.5, 0.5, 1.5 …, between the rows, so a label callback keyed on whole numbers shows nothing. Make bubble **area** proportional to the value (`r = √(v / max) · maxR`); scaling the radius makes the largest look several times bigger than it is. Write the value beside each bubble, outline in the solid primary like every palette fill, and show the tooltip only over a bubble (`interaction: { mode: 'nearest', intersect: true }`), with a few px of `hitRadius` so the smallest bubbles are still easy to hover. A whole-row target makes the empty space beside a bubble trigger it. |
| Scatter of every item (all routes: x = distance, y = flights) | Use it when the outliers are the story; a top-n list drops them. Dots all one size (8px, `pointHitRadius` ≥ 8), palette fill with the solid outline, titles on both axes since both are measures. Label only the few points worth naming (the largest few, plus the extreme), beside the dot, flipped left near the right edge. Everything else goes in the tooltip and the hidden table, so the crowded corner near the axes stays readable. |
| Polar area (cyclic categories: days of the week, months) | Radius *and* shade follow the value: each slice takes the palette step nearest its position between the fewest and the most, outlined like every sliced chart. Circular gridlines only (no angle lines or ticks); labels outside the ring on one line, "Mon **34**" (name muted, value in main text), so values aren't tooltip-only. Derive the layout padding from the label constants (12px gap + one 14px line vertically) so labels at 6 and 12 o'clock aren't clipped. Size: 260px tall. Start at the locale's first day of the week. |
| Container height | Includes the category axis labels, so the card never gets its own inner scrollbar |
| Page layout | Rows that are either full-width or two equal columns, from one shared grid, so columns line up down the page; no one-off column splits. In a two-column row, both halves get the taller one's height. Keep the **headings level** and **centre each half's content vertically** in the space under its heading, so a short chart beside a long list doesn't leave all its whitespace at the bottom. |
| Animation | Off. Charts redraw on filter and theme changes, and replaying a growth animation each time is distracting. |

**Labels must never collide.** Column labels sit side by side, so on a phone they
overflow their column. Measure the container (`ResizeObserver`); when the widest
formatted label won't fit its slot (`width / columns`), turn the labels off and show a
value axis with gridlines instead. Readers then always have one way to read values.
Horizontal bars put their labels past the bar end and rarely need this.

## Canvas or HTML?

Not everything in an analytics screen should be a chart:

| Use a canvas (Chart.js) | Use HTML |
| --- | --- |
| Time series, histograms, stacked columns, doughnuts: shapes that need scales | Stat tiles and headline figures |
| | Ranked lists ("top airlines"): rows need readable labels, badges and **real links** |
| | Meters and progress figures: `--color-primary-light` track, primary fill |
| | Record cards, captions, legends |

HTML follows the theme through CSS variables with no extra code, keeps text
selectable and translatable, and gives screen readers proper structure. A canvas is
one opaque image.

## Accessibility

- Every canvas gets a **summary** (`aria-label` on `role="img"`) and a **data
  table** next to it, using Nextcloud core's `.hidden-visually` class: a caption,
  one row per category, one column per series, plus a total for stacks.
- **No value only in a tooltip.** Tooltips need hover and give keyboard and touch
  users nothing. Value labels (or the value axis fallback) plus the hidden table cover
  them.
- **Separate colours by lightness, not hue.** The palette does this by
  construction, because every step moves further from the background.
- **Text uses text variables** (`--color-main-text`, `--color-text-maxcontrast`). Both
  stock themes clear 4.5:1 (`#6b6b6b` on white is 5.3:1, `#999999` on `#171717` is
  6.3:1).
- Make hover targets larger than the marks: `interaction: { mode: 'index',
  intersect: false }` responds anywhere in a column, not just over a thin bar.

## Testing

- **Keep the colour maths and the data shaping pure** (`colorRamp.ts`, an
  `analytics.ts`-style module) and unit-test them thoroughly. These are the parts
  that hold the logic.
- **Test which element the theme is read from.** Set a variable on
  `document.documentElement` and a different one on `document.body`, then assert the
  body wins. A one-line regression here re-creates the explicit-dark bug, and no
  rendering test would catch it.
- **Test the low-contrast-accent case**: a primary at 3.2:1 must still produce evenly
  spaced steps.
- **jsdom has no canvas.** Mock `vue-chartjs` with stubs that accept
  `data`/`options`, and assert what your component *passes* to them: dataset labels,
  stack order, colours that are real `#rrggbb` values. Don't try to render Chart.js.
- **Check the palette in a real browser once**, in both a light and a dark theme,
  and once with Dark chosen explicitly on a light OS. That last case is the one the
  `:root` mistake breaks.

## Common mistakes

| Mistake | Effect | Fix |
| --- | --- | --- |
| `getComputedStyle(document.documentElement)` | Light colours inside an explicitly chosen dark theme | Read `document.body` |
| Reading the theme once in `onMounted` | Stale charts after an OS light/dark switch | `matchMedia` listeners + reactive options |
| Leaving Chart.js's text/grid defaults | `#666` text at 3.1:1 and invisible gridlines on dark | Set colours from the theme on every chart |
| `hexToRgba(hex)` slicing `#rrggbb` | `NaN` colours for `#fff`, `rgb()`, relative syntax | A parser that returns `null` → fallback |
| A ramp per chart | Neighbouring charts in visibly different shades of the same colour | One page palette; every chart picks steps from it |
| `rgba()` fills | HTML swatches that don't match the canvas; contrast you can't measure | Opaque blends over the actual background |
| Pale fills without an outline | Faint slices that barely read as shapes | A 1px solid primary outline on every sliced chart |
| Solid fills everywhere | A heavy, saturated page | Single-series fills at palette step 4; solid on hover |
| Default tooltip positioning | The box stays stuck to the bar while the pointer moves | A `'cursor'` positioner |
| Fixed hex palettes | Ignore the user's accent; need one set per theme | Derive from `--color-primary-element` |
| A plugin with `ctx.font = '11px sans-serif'` | Ignores `--font-face` (and the dyslexia font) | Pass the theme font through plugin options |
| Values only in tooltips | Unreadable by keyboard, touch and screen-reader users | Value labels + hidden data table |
| Column labels drawn regardless of width | Overlapping numbers on phones | Measure; fall back to a value axis |

## Checklist

**Theme**

- [ ] Colours read from `document.body` (or the chart's container), never `documentElement`
- [ ] Every chart colour comes from the theme. No hex literal in chart options or plugins.
- [ ] Parser handles hex and `rgb()` and falls back on anything else
- [ ] Theme re-read on `prefers-color-scheme` / `prefers-contrast` changes; options are `computed`
- [ ] Text, grid, border and font set explicitly on every chart (or every chart updated after changing `Chart.defaults`)

**Palette**

- [ ] One five-step palette for the page (20–85% of the primary, as opaque blends); every chart picks from it
- [ ] Single-series fills at step 4, never below 3:1; solid on hover
- [ ] Sliced charts (doughnut, polar) outline their slices in the solid primary
- [ ] Ordered categories have fixed steps; "Other"/"No data" are neutral grey, not a step
- [ ] The same palette is published as CSS variables for legends and HTML bars

**Marks and accessibility**

- [ ] 2px surface-coloured gaps between stacked segments and slices; no dark outlines
- [ ] Every value readable without hovering; labels never overlap
- [ ] Tooltips follow the pointer (`position: 'cursor'`)
- [ ] Every countable element drills through (pointer cursor + tooltip hint), and its count equals the filtered list's
- [ ] HTML legend for 2+ series, none for 1
- [ ] `aria-label` summary + `.hidden-visually` data table per canvas

**Build and tests**

- [ ] Only the Chart.js components you use are registered; the view is lazy-loaded
- [ ] A test proves `<body>` wins over `<html>`
- [ ] Viewed in light, dark, and explicit-dark-on-light-OS

## Check commands

Run from the app's root.

```bash
# The :root mistake. Every hit that reads theme variables should be document.body.
grep -rnE "getComputedStyle\(\s*document\.documentElement" src/

# Hard-coded colours near chart code. Review each hit.
grep -rnE "#[0-9a-fA-F]{3,8}\b|rgba?\(" src/ | grep -iE "chart|dataset|plugin|color" | grep -v "\.css"

# Global Chart.js defaults. Fine if every chart is updated after a theme change.
grep -rn "Chart\.defaults\|ChartJS\.defaults" src/

# Hand-rolled hex parsing that can't handle other formats
grep -rnE "slice\(1,\s*3\)|parseInt\([^)]*16\)" src/

# Fonts hard-coded on a canvas context (a template literal that interpolates the
# theme font is fine and is not matched)
grep -rnE "ctx\.font\s*=\s*['\"]" src/
```

To see which theme a page is really using, run this in the browser console:

```js
const v = (el, n) => getComputedStyle(el).getPropertyValue(n).trim()
console.table({
	html: { primary: v(document.documentElement, '--color-primary-element'), bg: v(document.documentElement, '--color-main-background') },
	body: { primary: v(document.body, '--color-primary-element'), bg: v(document.body, '--color-main-background') },
	themes: { primary: document.body.dataset.themes },
})
```

If `html` and `body` differ, the user has chosen a theme explicitly, and anything
reading `html` is drawing in the wrong one.

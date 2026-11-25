---
name: charts
description: "Theme-aware charts in Nextcloud app frontends (Chart.js via vue-chartjs, or any canvas library): one runtime palette taken from the theme, live theme changes, accessibility. This skill should be used when adding, restyling or reviewing any chart, legend, ranked bar, sparkline or stat tile, and when chart colours or text look wrong in a dark or high-contrast theme."
---

# Nextcloud charts

1. Read theme colours from `document.body`, never `document.documentElement`.
2. Derive every chart colour from the theme at runtime, as one palette for the
   whole page. No hard-coded hexes, no per-chart ramps, no `rgba()` fills.
3. Re-read the theme when it can change, and let Vue reactivity redraw the charts.
4. Set text, gridline and font colours explicitly: Chart.js's defaults are wrong
   on a dark theme.
5. Never put a value only in a tooltip. Label the marks, and give every canvas a
   text alternative. Tooltips follow the pointer.

The guide `${CLAUDE_SKILL_DIR}/references/nextcloud-charts.md` is long: read the
sections the task needs (its contents list is at the top), and use its code as
given, so charts match across apps.
- New chart or first chart in an app: "Building the palette", "Reading the theme in
  code", "Keeping it live", "Chart.js setup".
- Choosing or styling marks, labels, legends: "Marks and layout", "Canvas or HTML?".
- Reviewing a chart: "Common mistakes" and "Checklist"; then "Check commands".

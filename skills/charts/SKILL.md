---
name: charts
description: Drawing charts in a Nextcloud app frontend (Chart.js via vue-chartjs, or any canvas library) so they look native in every theme, accent colour and high-contrast mode, using one runtime palette. Use when adding, restyling or reviewing a chart, legend, ranked bar or stat tile, or when chart colours or text look wrong in a dark or high-contrast theme.
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

Read `${CLAUDE_SKILL_DIR}/nextcloud-charts.md` before writing chart code: it has the
palette code, the theme-reading and live-update code, Chart.js setup, the checklist
and check commands. Use them as given, so charts match across apps.

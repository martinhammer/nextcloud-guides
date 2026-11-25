---
name: app-icons
description: "Nextcloud app icon contract for img/app.svg, img/app-dark.svg and img/<appid>(-dark).svg: where paint may go, the file pair, and a check script. This skill should be used when creating, editing or reviewing an app icon, and whenever an icon shows in the wrong colour, white on white, invisible in the header, or doesn't follow the theme."
paths: "img/*.svg"
---

# Nextcloud app icon contract

**Paint belongs on the root `<svg>`, never below it.** Nextcloud recolours inlined
icons with `.icon-vue svg { fill: currentColor }`, which matches the root element
only. A `fill`, `stroke`, `color` or `stop-color` on a `<g>`, `<path>` or in a
`<style>` block is never reached and pins the glyph to one colour.

Blocking rules (full table and reasons in the guide):
- **R1** No `fill`/`stroke`/`color`/`stop-color` on any descendant (`fill="none"` is fine).
- **R2** `app.svg` has `fill="#fff"` on the root; `app-dark.svg` has no fill.
- **R3** Both declare a `viewBox` (plus `width`/`height` by convention).
- **R5** Both parse: `xmllint --noout img/app*.svg`.
- Convention **R4**: the pair is identical apart from that one fill attribute.

Before changing an icon, read `${CLAUDE_SKILL_DIR}/references/nextcloud-app-icon-contract.md`
(where each surface paints the icon, rules per supported version, checklist), and
run the check script from its "Verify" section afterwards.

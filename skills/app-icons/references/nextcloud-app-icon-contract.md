# Nextcloud App Icon Contract

Three blocking rules, two conventions, and a check script — so an app icon renders
correctly in the Apps list, the app menu and both colour themes without anyone
having to work it out again.

- **Applies to:** `img/app.svg`, `img/app-dark.svg`, `img/<appid>.svg`, `img/<appid>-dark.svg`
- **Assumes:** a single-colour glyph

---

## The rule

> **Paint belongs on the root `<svg>`. Never below it.**

Nextcloud recolours inlined icons with one rule — `.icon-vue svg { fill: currentColor }`
— which matches the `<svg>` element and nothing beneath it. CSS beats a presentation
attribute on that element, so a root fill is overridden and the icon adapts to its
surroundings. Any `fill`, `stroke`, `color` or `stop-color` on a `<g>`, a `<path>` or a
`<style>` block is never reached, wins for its subtree, and pins the glyph to one colour
— which sooner or later is the colour of the background behind it.

## Assumption: a monochrome glyph

Everything here assumes the icon is a **single-colour glyph** that Nextcloud is free to
recolour — the form every bundled app ships. That is what makes "paint only on the root"
a safe instruction: there is exactly one colour, and the platform owns it.

A deliberately multi-colour logo is outside this contract. It will trip R1 legitimately,
because its colours *must* live on descendants. If you ship one, expect it to be
inverted, masked or flattened to a single colour depending on the surface and the
release — the platform offers no way to opt out. Prefer a monochrome mark for `app.svg`
and keep the full-colour version for screenshots and the app store listing.

## Before and after

```xml
<!-- Breaks: the fill sits on a descendant, so currentColor never reaches it -->
<svg xmlns="…" viewBox="0 0 672 672">
<g fill="white">
  <path d="M612,195.7…"/>
</g>
</svg>
```

```xml
<!-- Works: the fill sits on the root, where the CSS rule overrides it -->
<svg xmlns="…" height="20px" width="20px" viewBox="0 0 672 672" fill="#fff">
<g>
  <path d="M612,195.7…"/>
</g>
</svg>
```

Rendered side by side in the Apps list, the first is invisible on a light background and
the second takes the surrounding text colour. The broken one is not *missing* — it is
painted white on white. A genuinely missing icon falls back to a cog placeholder.

## Where the icon gets painted

Three surfaces, three mechanisms. Knowing which is which tells you whether a given fix is
load-bearing or cosmetic — and stops people "fixing" a file that was never rendered the
way they assumed.

| Surface | Mechanism | Does the authored colour matter? |
| --- | --- | --- |
| **Apps list**<br>settings → Apps | Fetched, inlined, recoloured by `.icon-vue svg { fill: currentColor }` | Root: **no** — it is overridden.<br>Descendant: **yes** — this is the bug. |
| **App menu**<br>top-bar navigation | Shipped releases render `<img src="app.svg">` behind `filter: var(--*-invert-if-bright)`. Newer builds mask it instead. | **Yes** — the filter assumes a bright icon. A dark or fill-less `app.svg` stays dark on the dark header. |
| **Settings section**<br>`IIconSection::getIcon()` | Served at the URL you return and rendered as an image | **Yes** — it renders as authored (theme CSS may invert it). |

The app-menu row is the one that catches people out. Upstream states the assumption in
the stylesheet itself — *"App icons are bright by default; flip them to dark when the
primary color is bright"* — so an app with a `<navigation>` entry that ships a dark or
fill-less `app.svg` gets an invisible icon in the header. That is the same bug class as
the Apps-list one, reached from the opposite direction.

## The file pair

Ship both. They are the same artwork and should differ in exactly one attribute.

| File | Root fill | Renders as |
| --- | --- | --- |
| `img/app.svg` | `fill="#fff"` on `<svg>` | White standalone; `currentColor` when inlined |
| `img/app-dark.svg` | no fill anywhere | Black standalone; `currentColor` when inlined |

The dark variant holds no opinion on purpose: with no fill to override, it is correct
whether it is inlined or dropped into an `<img>`.

## Write for every supported version

None of the three surfaces is stable across releases. The Apps list has changed both
which file it resolves and whether it recolours the markup; the app menu has changed how
it paints. Chasing which build does what is a trap — the app has to work on every version
in its `info.xml` range at once.

| What varies | Behaviours seen in the wild | What it demands of your file |
| --- | --- | --- |
| **Apps-list lookup** | Some builds try the dark variant first; others only ever resolve `<appid>.svg` then `app.svg`. | Either file may be the one shown. **Both must be correct.** |
| **Apps-list recolouring** | Some builds strip `fill` and `color` attributes before inlining. Others hand the markup over untouched. | Never rely on stripping. **No paint below the root** (R1). |
| **App-menu painting** | Shipped releases use `<img>` behind an invert-if-bright filter, which assumes a bright icon. Newer builds mask it and ignore colour. | **`app.svg` must be bright** (R2), or it is invisible on the dark header of any release that filters. |

The intersection of all of them is a single authoring rule, and it is the whole contract:

> **A monochrome glyph, paint only on the root `<svg>`, `app.svg` bright.**

A file in that shape is correct under every behaviour above — so you never have to know
which build you are on, and it keeps working when the next release changes the mechanism
again.

If you do need to know what a specific target does, read it rather than infer it:

```bash
grep -rn "getAppIcon\|app-dark" lib/private/legacy/OC_App.php   # which file the Apps list resolves
grep -rn "replaceAll\|fill=" apps/*/src/components/App*Icon*.vue  # does it strip fills?
grep -rn "invert-if-bright\|mask:" core/src/components/App*.vue   # how the app menu paints
```

## Checklist

R1, R2, R5 and R3’s `viewBox` clause break an icon on some surface. R3’s dimensions
and R4 are conventions every bundled app follows: worth holding, but not worth a revert.

| | Severity | Rule |
| --- | --- | --- |
| **R1** | Blocking | **No `fill`, `stroke`, `color` or `stop-color` on any descendant** — as an attribute, in a `style` attribute, or via a `<style>` block.<br>The whole bug. Move it to the root `<svg>` or delete it. `fill="none"` and `stroke="none"` are fine — they pin no colour. |
| **R2** | Blocking | **`app.svg` carries `fill="#fff"` on the root; `app-dark.svg` carries no fill.**<br>Shipped releases paint the app menu with an invert-if-bright filter, so a dark or fill-less `app.svg` is invisible on the header. Unconditional: an app can gain a `<navigation>` entry in any release, and nothing re-checks the icon when it does. |
| **R3** | Blocking (`viewBox`)<br>Convention (`width`/`height`) | **Both declare `viewBox` plus `width` and `height`.**<br>A missing `viewBox` is blocking — it will not scale, and the script exits 1 on it. The dimensions are only the intrinsic-size fallback for anything that sizes nothing. |
| **R4** | Convention | **The pair is identical apart from that one fill attribute.**<br>Any other divergence costs the next reader time working out whether it was deliberate. |
| **R5** | Blocking | **Both parse:** `xmllint --noout img/app*.svg`.<br>A parse error renders nothing at all, with only a console warning. |

## Verify

Save as `check-app-icon.py` and point it at any app's icons. Exits 1 on a blocking
failure; convention warnings alone exit 0, so it drops into CI without forcing cosmetic
churn.

**Name the icon pair; do not glob.** Every path that does not end `-dark.svg` is treated
as a light variant and must be bright, so `check-app-icon.py img/*.svg` will fail on any
unrelated SVG that happens to live in `img/`.

```bash
check-app-icon.py img/app.svg img/app-dark.svg        # right
check-app-icon.py img/*.svg                           # errors on unrelated art
```

```python
#!/usr/bin/env python3
"""Audit a Nextcloud app icon.

ERROR  the icon can render wrong on a real surface — fix before shipping.
WARN   diverges from the convention every bundled app follows.

Exits 1 if any ERROR is found; warnings alone exit 0.
"""
import sys
import xml.etree.ElementTree as ET

PAINT_ATTRS = ('fill', 'color', 'stroke', 'stop-color')
PAINT_PROPS = ('fill:', 'stroke:', 'stop-color:')
# These pin no colour: they resolve through the inherited color, or to nothing.
PAINT_OK = ('none', 'currentcolor', 'inherit')
BRIGHT = ('#fff', '#ffffff', 'white')


def squash(text):
    """Lowercase and drop all whitespace, so 'fill : #fff' still matches 'fill:'."""
    return ''.join((text or '').split()).lower()


def audit(path):
    errors, warns = [], []
    try:
        root = ET.parse(path).getroot()
    except ET.ParseError as exc:
        return [f'does not parse: {exc}'], []

    for el in root.iter():
        tag = el.tag.split('}')[-1]
        # A <style> block (typical of Illustrator exports) pins paint by class
        # and defeats currentColor exactly as an attribute does.
        if tag == 'style' and any(p in squash(el.text) for p in PAINT_PROPS):
            errors.append('<style> block pins paint — strip it')
            continue
        if el is root:
            continue
        for attr in PAINT_ATTRS:
            value = el.get(attr)
            if value is not None and value.strip().lower() not in PAINT_OK:
                errors.append(f'<{tag}> carries {attr}="{value}" — must live on the root <svg>')
        style = squash(el.get('style'))
        for prop in PAINT_PROPS:
            if prop in style and not any(f'{prop}{ok}' in style for ok in PAINT_OK):
                errors.append(f'<{tag}> pins {prop.rstrip(":")} in its style attribute')

    if root.get('viewBox') is None:
        errors.append('root <svg> has no viewBox — it will not scale')
    if root.get('width') is None or root.get('height') is None:
        warns.append('root <svg> has no width/height (intrinsic-size fallback)')

    root_fill = root.get('fill')
    if path.endswith('-dark.svg'):
        if root_fill is not None:
            warns.append(f'dark variant conventionally carries no fill (found {root_fill!r})')
    elif (root_fill or '').strip().lower() not in BRIGHT:
        errors.append(f'light variant must carry fill="#fff" on the root (found {root_fill!r})'
                      ' — shipped releases paint the app menu with an invert-if-bright filter')

    return errors, warns


failed = False
for path in sys.argv[1:]:
    errors, warns = audit(path)
    status = 'ERROR' if errors else ('warn ' if warns else 'ok   ')
    print(f'{status} {path}')
    for e in errors:
        print(f'        ERROR  {e}')
    for w in warns:
        print(f'        warn   {w}')
    failed |= bool(errors)

sys.exit(1 if failed else 0)
```

### Sample run

```console
$ python3 check-app-icon.py img/app.svg img/app-dark.svg
ok    img/app.svg
ok    img/app-dark.svg

$ python3 check-app-icon.py apps/user_status/img/app.svg
ERROR apps/user_status/img/app.svg
        ERROR  <path> carries fill="#FFFFFF" — must live on the root <svg>
        ERROR  light variant must carry fill="#fff" on the root (found None) — shipped releases paint the app menu with an invert-if-bright filter
```

Calibrated against six known-good bundled icons — `federation`, `files_reminders`,
`files_sharing`, `systemtags` and both `appstore` files — which all pass clean, and
`user_status`, which carries the identical defect upstream today.

## Field notes

Findings from applying this to real apps. Add to it rather than rediscovering.

**`stroke` defeats `currentColor` just as `fill` does.**
Found in the wild: an `app.svg` carrying `stroke="#ffffff"` on a descendant alongside the
fill. An earlier version of this checker tested `fill`, `color` and `style` only, and
would have passed a file that still rendered wrong. R1 and the script now cover `stroke`
and `stop-color`, plus `<style>` blocks — the usual shape of a designer-supplied SVG.

**An invisible icon is not a missing icon.**
When no icon resolves at all, the Apps list renders a cog placeholder. A blank cell where
a glyph should be means the file loaded and painted itself the colour of the background —
check the paint before checking the paths.

**Do not let the server's fill-stripping talk you out of fixing the file.**
Some builds delete offending attributes before inlining, which is why `user_status` still
renders correctly on those. That safety net is not in every release, and it does not
apply to any surface other than the Apps list.

**The app menu was the surface everyone got wrong.**
An earlier revision of this document claimed the app menu masks the icon and therefore
ignores its colour. True of newer builds, false of every shipped release, which renders
an `<img>` behind an invert-if-bright filter. The mask present there is a vertical fade,
not the icon. Checking one branch is how a version-specific behaviour gets written down
as a general one.

**Keep the rule unconditional, so the script never has to parse anything but the icon.**
An earlier revision enforced R2 only for apps with a `<navigation>` entry, detected by
reading `info.xml`. Two problems. The detection tested for the literal string
`<navigation>` and so missed `<navigation role="admin">` — core's own appstore app spells
it that way — letting an identical broken icon pass. And a conditional rule rots: an app
can add a navigation entry in any release with nothing re-checking the icon. Every
bundled app ships a bright `app.svg` regardless, so the cheap policy is the unconditional
one. Deleting the condition deleted the bug with it.

**Whitespace is not optional to handle.**
`.st0{fill : #fff;}` is valid CSS and an earlier checker missed it, because the `<style>`
branch lowercased its text but did not strip spaces the way the style-attribute branch
did. Both branches now share one `squash()` helper that drops all whitespace, which also
catches the tab-before-colon form a plain space-strip would not.

**`fill="currentColor"` on a descendant is fine.**
It resolves through the inherited `color` and adapts correctly, so it pins nothing. The
checker allows `currentColor`, `inherit` and `none`, and compares case-insensitively —
CSS keywords are case-insensitive and some tools emit `currentcolor`, which an earlier
version failed for doing the right thing.

---

Read across `nextcloud/server` stable33, stable34 and master:
`core/src/components/AppMenuIcon.vue`, `core/src/components/AppItem.vue`,
`core/src/components/AppIcon.vue`, `apps/appstore/src/components/AppIcon.vue`,
`lib/private/legacy/OC_App.php`, `lib/public/App/IAppManager.php`, and
`NcIconSvgWrapper` from `@nextcloud/vue`. Where they disagree, the tables above record
the disagreement rather than picking one.

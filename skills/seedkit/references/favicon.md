# Favicon

No package and no stock asset — draw an SVG for this specific project at scaffold time. Every browser tab and bookmark otherwise shows the generic globe.

## Draw `assets/favicon.svg`

Place it in the directory listed in `STATICFILES_DIRS` (`assets/` in `references/tailwind.md`). Shape to adapt, not an asset to copy:

```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
  <rect width="64" height="64" rx="14" fill="#1e40af"/>
  <text x="32" y="44" font-family="system-ui, sans-serif" font-size="36"
        font-weight="700" fill="#ffffff" text-anchor="middle">S</text>
</svg>
```

Customize it to the project:

- Glyph: the project's initial letter — or, when the domain has an obvious simple motif (a few `<path>`/`<circle>` elements at most), draw that instead.
- Colors: with DaisyUI, use the selected theme's `primary` / `primary-content` pair; otherwise pick one saturated background + white.
- It must read at 16 px: one glyph, high contrast, no fine detail.

## Wire it into templates

In the `<head>` of `templates/base.html`:

```django
<link rel="icon" type="image/svg+xml" href="{% static 'favicon.svg' %}">
```

Add `{% load static %}` at the top of the template if it isn't there. The custom error templates from `references/tailwind.md` are standalone documents (they don't extend `base.html`) — repeat both lines in each.

## Optional — PNG fallbacks when tooling exists

iOS home-screen icons need PNG. Probe for a rasterizer and render fallbacks only if one is found — the SVG alone is a complete baseline, so skip silently otherwise:

```sh
# rsvg-convert (Linux: librsvg2-bin / librsvg2-tools)
rsvg-convert -w 180 -h 180 assets/favicon.svg -o assets/apple-touch-icon.png
rsvg-convert -w 32 -h 32 assets/favicon.svg -o assets/favicon-32.png

# sips (ships with macOS)
sips -s format png -z 180 180 assets/favicon.svg --out assets/apple-touch-icon.png
sips -s format png -z 32 32 assets/favicon.svg --out assets/favicon-32.png
```

ImageMagick is not a substitute here — stock builds rasterize SVG with the internal renderer, which fails on `<text>` (`unable to read font`) unless the librsvg delegate was compiled in.

Add the matching links to `<head>` only for files actually produced:

```django
<link rel="apple-touch-icon" href="{% static 'apple-touch-icon.png' %}">
<link rel="icon" type="image/png" sizes="32x32" href="{% static 'favicon-32.png' %}">
```

## Verifying

```sh
uv run manage.py runserver --noreload &
PID=$!
for i in 1 2 3 4 5; do curl -sf http://127.0.0.1:8000/ > /dev/null && up=1 && break; sleep 1; done
[ -n "$up" ] || echo "BOOT CHECK FAILED"
curl -sf http://127.0.0.1:8000/ | grep -q 'favicon.svg'
curl -sf http://127.0.0.1:8000/static/favicon.svg | grep -q '<svg'
kill "$PID"
```

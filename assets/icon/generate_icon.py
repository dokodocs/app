"""Generates the DokoDocs launcher icon from the brand logo.

Run: python generate_icon.py
Produces (in this directory):
  icon_1024.png            - full icon: the brand mark (green woven-basket +
                             document) on a WHITE background, used for iOS and
                             the Android legacy/round fallback.
  icon_foreground_1024.png - the mark only, on a transparent background, sized
                             into Android's adaptive-icon safe zone (used with
                             adaptive_icon_background = #FFFFFF in pubspec.yaml).
  logo_header.png          - 168x168 in-app header logo.

Source of truth is assets/logo/logo_dokodocs.svg (an Inkscape SVG wrapping a
1254x1254 raster of the mark). The mark is green line-art on white; the white
areas (paper, basket-weave gaps) are STRUCTURAL, so we keep a white background
rather than knocking white out to transparent — otherwise the mark dissolves
into a light launcher background and the icon looks empty. Regenerate + re-run
`dart run flutter_launcher_icons` after any change here.
"""

import base64
import io
import re

from PIL import Image

SVG = "../logo/logo_dokodocs.svg"
CANVAS = 1024
WHITE = (255, 255, 255, 255)
TRANSPARENT = (0, 0, 0, 0)


def load_mark() -> Image.Image:
    """Extract the embedded raster from the Inkscape SVG and trim its white
    margin down to the mark's bounding box."""
    svg = open(SVG, "r", encoding="utf-8", errors="ignore").read()
    m = re.search(r'href="data:image/(?:png|jpeg);base64,([^"]+)"', svg)
    if not m:
        raise SystemExit("no embedded raster found in " + SVG)
    b64 = re.sub(r"&#\d+;", "", m.group(1))          # strip XML entities
    b64 = re.sub(r"[^A-Za-z0-9+/=]", "", b64)          # strip whitespace
    raw = base64.b64decode(b64 + "=" * (-len(b64) % 4))
    im = Image.open(io.BytesIO(raw)).convert("RGBA")

    # Trim the source's built-in white margin down to the mark's bounding box,
    # via the per-pixel difference from pure white (the green line-art is the
    # only thing that differs).
    from PIL import ImageChops

    rgb = im.convert("RGB")
    diff = ImageChops.difference(rgb, Image.new("RGB", im.size, (255, 255, 255)))
    diff = diff.convert("L").point(lambda p: 255 if p > 12 else 0)
    bbox = diff.getbbox()
    if bbox:
        im = im.crop(bbox)
    return im


def fit(mark: Image.Image, target: int, scale: float) -> Image.Image:
    """Scale the mark to `scale` of a `target`x`target` box, preserving aspect."""
    box = int(target * scale)
    m = mark.copy()
    m.thumbnail((box, box), Image.LANCZOS)
    return m


def compose(mark: Image.Image, bg, scale: float) -> Image.Image:
    canvas = Image.new("RGBA", (CANVAS, CANVAS), bg)
    m = fit(mark, CANVAS, scale)
    x = (CANVAS - m.width) // 2
    y = (CANVAS - m.height) // 2
    canvas.alpha_composite(m, (x, y))
    return canvas


if __name__ == "__main__":
    mark = load_mark()
    print("trimmed mark size:", mark.size)

    # Full icon (iOS + Android legacy): mark on white, ~82% so it breathes
    # inside the rounded-square/circle masks without touching the edges.
    compose(mark, WHITE, 0.82).save("icon_1024.png")

    # Adaptive foreground: mark on transparent, ~66% to stay inside Android's
    # adaptive safe zone (paired with a white adaptive background in pubspec).
    compose(mark, TRANSPARENT, 0.66).save("icon_foreground_1024.png")

    # In-app header logo.
    compose(mark, WHITE, 0.82).resize((168, 168), Image.LANCZOS).save("logo_header.png")
    print("Wrote icon_1024.png, icon_foreground_1024.png, logo_header.png")

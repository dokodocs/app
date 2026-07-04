"""Generates the DokoDocs launcher icon.

Run: python generate_icon.py
Produces (in this directory):
  icon_1024.png            - full icon (green rounded-square bg + white
                              glyph), used for iOS and as the Android
                              legacy/round fallback
  icon_foreground_1024.png - glyph only, transparent background, sized to
                              Android's adaptive-icon safe zone (used with
                              adaptive_icon_background in pubspec.yaml)

No gradients, no text - a document outline with viewfinder-style scan
corner brackets, per the brand icon spec. Regenerate + re-run
`flutter pub run flutter_launcher_icons` after any change here.
"""

from PIL import Image, ImageDraw

CANVAS = 1024
BRAND_GREEN = (46, 125, 107, 255)  # 0xFF2E7D6B, matches AppTheme's seed color
WHITE = (255, 255, 255, 255)
TRANSPARENT = (0, 0, 0, 0)

# Document rectangle (portrait page), centered. Shrunk (v2, per user
# feedback that the original was "too big"/not friendly) with more
# negative space and thinner strokes for a softer, more professional
# look — still sized (with the corner brackets below) to stay inside
# Android's adaptive-icon safe zone, the center ~66% circle every
# launcher mask shape (circle/squircle/rounded square/teardrop)
# is guaranteed not to clip.
DOC_W, DOC_H = 220, 280
DOC_LEFT = (CANVAS - DOC_W) // 2
DOC_TOP = (CANVAS - DOC_H) // 2 - 12
DOC_RIGHT = DOC_LEFT + DOC_W
DOC_BOTTOM = DOC_TOP + DOC_H
DOC_RADIUS = 18
FOLD = 36  # folded-corner size, top-right

# Viewfinder corner brackets around the document — thinner stroke + rounded
# end caps (small filled circles) for a "cuter" softer feel than PIL's
# default flat line caps.
PAD = 40
BRACKET_ARM = 70
BRACKET_STROKE = 16


def draw_glyph(draw: ImageDraw.ImageDraw, color) -> None:
    # Document body as a rounded rect, then cut a folded corner (top-right)
    # by drawing a triangle in the "erase" color the caller supplies via a
    # separate mask step (see build_foreground/build_full below).
    draw.rounded_rectangle(
        [DOC_LEFT, DOC_TOP, DOC_RIGHT, DOC_BOTTOM],
        radius=DOC_RADIUS,
        fill=color,
    )

    # Viewfinder corner brackets (camera/scan framing), one "L" per corner.
    bx0, by0 = DOC_LEFT - PAD, DOC_TOP - PAD
    bx1, by1 = DOC_RIGHT + PAD, DOC_BOTTOM + PAD
    cap_r = BRACKET_STROKE / 2

    def round_cap(x, y):
        draw.ellipse([x - cap_r, y - cap_r, x + cap_r, y + cap_r], fill=color)

    def l_bracket(x, y, dx, dy):
        # dx/dy = +1/-1 indicating which way the arms point (into the icon)
        x_end, y_end = x + BRACKET_ARM * dx, y + BRACKET_ARM * dy
        draw.line([(x, y), (x_end, y)], fill=color, width=BRACKET_STROKE)
        draw.line([(x, y), (x, y_end)], fill=color, width=BRACKET_STROKE)
        round_cap(x, y)
        round_cap(x_end, y)
        round_cap(x, y_end)

    l_bracket(bx0, by0, 1, 1)  # top-left
    l_bracket(bx1, by0, -1, 1)  # top-right
    l_bracket(bx0, by1, 1, -1)  # bottom-left
    l_bracket(bx1, by1, -1, -1)  # bottom-right


def build_full() -> Image.Image:
    img = Image.new("RGBA", (CANVAS, CANVAS), TRANSPARENT)
    draw = ImageDraw.Draw(img)
    bg_radius = int(CANVAS * 0.18)
    draw.rounded_rectangle([0, 0, CANVAS - 1, CANVAS - 1], radius=bg_radius, fill=BRAND_GREEN)
    draw_glyph(draw, WHITE)
    # Folded corner: cut a triangle out of the document's top-right, back
    # down to the brand-green background color, then redraw the small
    # fold flap in a slightly darker tone for depth-free "flat" contrast.
    draw.polygon(
        [
            (DOC_RIGHT - FOLD, DOC_TOP),
            (DOC_RIGHT, DOC_TOP),
            (DOC_RIGHT, DOC_TOP + FOLD),
        ],
        fill=BRAND_GREEN,
    )
    return img


def build_foreground() -> Image.Image:
    img = Image.new("RGBA", (CANVAS, CANVAS), TRANSPARENT)
    draw = ImageDraw.Draw(img)
    draw_glyph(draw, WHITE)
    draw.polygon(
        [
            (DOC_RIGHT - FOLD, DOC_TOP),
            (DOC_RIGHT, DOC_TOP),
            (DOC_RIGHT, DOC_TOP + FOLD),
        ],
        fill=TRANSPARENT,
    )
    return img


if __name__ == "__main__":
    full = build_full()
    full.save("icon_1024.png")
    build_foreground().save("icon_foreground_1024.png")
    # In-app header logo: a 28dp-logical-size asset, exported at 168x168
    # (6x) so it stays sharp on the highest-density devices; Flutter's
    # Image.asset scales it down to the actual logical size at render time.
    full.resize((168, 168), Image.LANCZOS).save("logo_header.png")
    print("Wrote icon_1024.png, icon_foreground_1024.png, logo_header.png")

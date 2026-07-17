#!/usr/bin/env python3
"""
Generate DokoDocs synthetic detection fixtures (ZERO real document data).

This generator renders synthetic "document on a surface" composites across the
benchmark categories, writes a SynthDocs-format annotation (``x1,y1 x2,y2
x3,y3 x4,y4``) per image, and then INVOKES the existing converter
``synthdocs_to_dokodocs_fixtures.py`` to emit DokoDocs fixture JSON. It does not
re-implement that conversion.

Why synthetic: DokoDocs (Apache-2.0 core + paid corporate tier) never
redistributes third-party training datasets. The only images committed to the
repo are these DokoDocs-generated composites — random grey text lines and
geometry on procedural backgrounds, with no real or personal document content —
so the offline detection harness can run end-to-end and report per-category IoU
without any licence exposure. See ``docs/DATASET_NOTICE.md``.

Categories (each becomes a fixture ``tags`` entry after conversion):
  clean, cluttered_desk, low_light, curled_corner, multi_document,
  id_card, receipt, similar_color_bg, occluded_corner

Usage:
    python generate_synth_fixtures.py
        [--out-dir ../../test/fixtures/detection/synthetic]
        [--per-category 18] [--seed 1337] [--no-convert]

Outputs (in --out-dir):
    <category>_<NNNN>.png   the synthetic composite (full-resolution)
    <category>_<NNNN>.json  DokoDocs fixture (image / corners / tags)
The intermediate SynthDocs ``.txt`` files are written to a scratch ``_build/``
folder (gitignored) and removed once conversion finishes.
"""
from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

# (category tag, page "kind", base background style)
CATEGORIES = [
    ("clean", "doc", "plain"),
    ("cluttered_desk", "doc", "clutter"),
    ("low_light", "doc", "plain"),
    ("curled_corner", "doc", "plain"),
    ("multi_document", "doc", "clutter"),
    ("id_card", "id", "clutter"),
    ("receipt", "receipt", "clutter"),
    ("similar_color_bg", "doc", "similar"),
    ("occluded_corner", "doc", "clutter"),
]

CANVAS_W = 760
CANVAS_H = 1000
PAGE_COLOR = (245, 244, 240)


# --------------------------------------------------------------------------- #
# Geometry helpers
# --------------------------------------------------------------------------- #
def find_coeffs(source_coords: list[tuple[float, float]],
                target_coords: list[tuple[float, float]]) -> list[float]:
    """8 coefficients mapping ``target`` -> ``source`` for ``PIL`` PERSPECTIVE.

    PIL's ``Image.transform`` samples the SOURCE image at the location computed
    from the OUTPUT pixel via these coefficients (i.e. an output->input map).
    Given the rectangular page (``source_coords``) and the canvas quad
    (``target_coords``), the returned coefficients map each canvas pixel back to
    the page so ``page.transform(canvas, PERSPECTIVE, coeffs)`` warps the page
    into the quad. (Canonical 4-point homography solve.)
    """
    matrix = []
    for s, t in zip(source_coords, target_coords):
        matrix.append([t[0], t[1], 1, 0, 0, 0, -s[0] * t[0], -s[0] * t[1]])
        matrix.append([0, 0, 0, t[0], t[1], 1, -s[1] * t[0], -s[1] * t[1]])
    a = np.array(matrix, dtype=np.float64)
    b = np.array([c for p in source_coords for c in p], dtype=np.float64)
    coeffs, *_ = np.linalg.lstsq(a, b, rcond=None)
    return coeffs.tolist()


def make_quad(rng, aspect: float, bend: bool = False
              ) -> list[tuple[float, float]]:
    """A roughly-rectangular quad (TL,TR,BR,BL) inside the canvas with margins.

    Stays within a 7% border so the detector's 2% border-touch filter passes,
    keeps interior angles sane, and applies mild perspective. ``bend`` pulls the
    BR corner inward to simulate a curled/bent corner.
    """
    margin_x, margin_y = 0.08 * CANVAS_W, 0.08 * CANVAS_H
    avail_w = CANVAS_W - 2 * margin_x
    avail_h = CANVAS_H - 2 * margin_y
    # scale the page to ~62% of the available area on the long axis
    long_side = 0.62 * max(avail_w, avail_h)
    pw = long_side if aspect <= 1 else long_side / aspect
    ph = pw * aspect
    pw = min(pw, 0.86 * avail_w)
    ph = min(ph, 0.86 * avail_h)

    cx = CANVAS_W * (0.50 + 0.05 * (rng.random() - 0.5))
    cy = CANVAS_H * (0.50 + 0.05 * (rng.random() - 0.5))
    hx, hy = pw / 2, ph / 2
    tl, tr, br, bl = (cx - hx, cy - hy), (cx + hx, cy - hy), \
        (cx + hx, cy + hy), (cx - hx, cy + hy)

    # mild perspective: shift the top edge inward symmetrically.
    persp = 0.05 * pw
    tl = (tl[0] + persp, tl[1] + 0.02 * ph)
    tr = (tr[0] - persp, tr[1] + 0.02 * ph)
    bl = (bl[0] + persp * 0.6, bl[1] - 0.01 * ph)
    br = (br[0] - persp * 0.6, br[1] - 0.01 * ph)
    # small per-corner jitter for realism.
    j = 0.012 * pw
    pts = [tl, tr, br, bl]
    pts = [(x + rng.uniform(-j, j), y + rng.uniform(-j, j)) for x, y in pts]
    if bend:
        # curl the bottom-right corner up and in (still convex).
        bx, by = pts[2]
        pts[2] = (bx - 0.16 * pw, by - 0.22 * ph)
    return [(x, y) for x, y in pts]


def quad_aspect(pts) -> float:
    tl, tr, br, bl = pts
    w = 0.5 * ((tr[0] - tl[0]) + (br[0] - bl[0]))
    h = 0.5 * ((bl[1] - tl[1]) + (br[1] - tr[1]))
    return h / w if w > 0 else 1.0


# --------------------------------------------------------------------------- #
# Content rendering
# --------------------------------------------------------------------------- #
def make_page(rng, aspect: float, kind: str) -> Image.Image:
    """A synthetic page texture (RGBA) for the given aspect and kind."""
    w = 420
    h = max(1, round(w * aspect))
    img = Image.new("RGBA", (w, h), PAGE_COLOR + (255,))
    d = ImageDraw.Draw(img)

    def lines(y0, y1, x_left, x_right, step, thick, jitter, gray_lo, gray_hi):
        y = y0
        while y < y1:
            x1 = x_right - jitter * rng.random()
            g = rng.randint(gray_lo, gray_hi)
            d.rectangle([x_left, y, x1, y + thick], fill=(g, g, g + 6, 235))
            y += step + step * 0.4 * rng.random()

    if kind == "id":
        d.rectangle([w * 0.06, h * 0.08, w * 0.60, h * 0.22],
                    fill=(40, 44, 60, 255))  # header band
        d.rectangle([w * 0.06, h * 0.30, w * 0.40, h * 0.66],
                    fill=(150, 124, 92, 255))  # photo block
        lines(h * 0.34, h * 0.66, w * 0.46, w * 0.94, h * 0.045,
              max(2, int(h * 0.011)), w * 0.30, 45, 80)
        lines(h * 0.72, h * 0.92, w * 0.06, w * 0.94, h * 0.05,
              max(2, int(h * 0.011)), w * 0.40, 45, 80)
    elif kind == "receipt":
        d.rectangle([w * 0.30, h * 0.015, w * 0.70, h * 0.05],
                    fill=(35, 35, 40, 255))  # logo band
        lines(h * 0.07, h * 0.93, w * 0.10, w * 0.90, h * 0.018,
              max(1, int(h * 0.005)), w * 0.55, 45, 80)
        d.rectangle([w * 0.10, h * 0.80, w * 0.90, h * 0.805],
                    fill=(20, 20, 20, 255))  # total divider
    else:  # doc
        d.rectangle([w * 0.06, h * 0.045, w * 0.62, h * 0.08],
                    fill=(45, 48, 64, 255))  # title
        # Sparse, thin, dark "text" lines on near-white paper -> a realistic
        # mostly-white page (high mean brightness) with ~12% ink coverage.
        lines(h * 0.13, h * 0.92, w * 0.06, w * 0.94, h * 0.032,
              max(2, int(h * 0.0045)), w * 0.42, 38, 70)
        # a couple of "figure" blocks to break up the text.
        if rng.random() < 0.7:
            d.rectangle([w * 0.06, h * 0.40, w * 0.94, h * 0.55],
                        fill=(212, 213, 215, 255))
    return img


def _gradient(w, h, top, bottom) -> Image.Image:
    arr = np.zeros((h, w, 3), dtype=np.uint8)
    ts = np.linspace(0, 1, h)[:, None]
    for c in range(3):
        arr[:, :, c] = (top[c] * (1 - ts) + bottom[c] * ts).astype(np.uint8)
    return Image.fromarray(arr, "RGB").convert("RGBA")


def make_background(rng, style: str) -> Image.Image:
    w, h = CANVAS_W, CANVAS_H
    if style == "plain":
        base = _gradient(w, h, (158, 158, 160), (132, 132, 135))
    elif style == "similar":
        # very close to the page colour -> low contrast (the hard case).
        base = _gradient(w, h, (230, 228, 221), (214, 212, 204))
    else:  # clutter (wooden desk)
        base = _gradient(w, h, (150, 108, 64), (120, 84, 48))
        d = ImageDraw.Draw(base)
        # faux keyboard to one side.
        kx, ky, kw, kh = int(w * 0.04), int(h * 0.62), int(w * 0.30), int(h * 0.20)
        d.rectangle([kx, ky, kx + kw, ky + kh], fill=(28, 28, 30, 255))
        cols, rows = 12, 5
        for r in range(rows):
            for c in range(cols):
                cx = kx + 6 + c * (kw - 12) / cols
                cy = ky + 6 + r * (kh - 12) / rows
                d.rectangle([cx, cy, cx + (kw - 12) / cols - 4,
                             cy + (kh - 12) / rows - 4],
                            fill=(58, 58, 62, 255))
        # notebook sheet poking from under the page.
        d.rectangle([int(w * 0.60), int(h * 0.10), int(w * 0.95), int(h * 0.50)],
                    fill=(238, 238, 234, 255), outline=(180, 180, 178, 255))
        # pen
        d.line([int(w * 0.20), int(h * 0.88), int(w * 0.55), int(h * 0.95)],
               fill=(30, 60, 120, 255), width=7)
    return base


def warp_page_into(page: Image.Image, quad) -> Image.Image:
    """Warp the rectangular page texture into ``quad`` on a canvas-sized RGBA."""
    w, h = page.size
    src = [(0, 0), (w - 1, 0), (w - 1, h - 1), (0, h - 1)]
    coeffs = find_coeffs(src, list(quad))
    warped = page.transform((CANVAS_W, CANVAS_H), Image.PERSPECTIVE, coeffs,
                            resample=Image.BICUBIC, fillcolor=(0, 0, 0, 0))
    # clean alpha: only keep pixels inside the destination quad.
    mask = Image.new("L", (CANVAS_W, CANVAS_H), 0)
    md = ImageDraw.Draw(mask)
    md.polygon([(float(x), float(y)) for x, y in quad], fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(0.8))
    warped.putalpha(ImageChops.multiply(warped.getchannel("A"), mask))
    return warped


def soft_shadow(quad) -> Image.Image:
    sh = Image.new("RGBA", (CANVAS_W, CANVAS_H), (0, 0, 0, 0))
    d = ImageDraw.Draw(sh)
    off = 10
    d.polygon([(x + off, y + off) for x, y in quad], fill=(0, 0, 0, 90))
    return sh.filter(ImageFilter.GaussianBlur(8))


# --------------------------------------------------------------------------- #
# Category assemblers
# --------------------------------------------------------------------------- #
def render_sample(rng, category: str, page_kind: str, bg_style: str) -> Image.Image:
    base = make_background(rng, bg_style)

    if category == "multi_document":
        # a secondary page behind the primary one (not the target).
        asp2 = rng.uniform(0.75, 0.95)
        q2 = make_quad(rng, asp2)
        page2 = make_page(rng, asp2, "doc")
        base = Image.alpha_composite(
            Image.alpha_composite(base, soft_shadow(q2)), warp_page_into(page2, q2))

    aspect = {"id": 0.63, "receipt": 1.85}.get(page_kind, rng.uniform(0.78, 0.95))
    bend = category == "curled_corner"
    quad = make_quad(rng, aspect, bend=bend)
    page = make_page(rng, quad_aspect(quad), page_kind)

    canvas = Image.alpha_composite(Image.alpha_composite(base, soft_shadow(quad)),
                                   warp_page_into(page, quad))

    if category == "occluded_corner":
        # draw an occluder over one corner after the page is placed.
        oc = Image.new("RGBA", (CANVAS_W, CANVAS_H), (0, 0, 0, 0))
        od = ImageDraw.Draw(oc)
        cx, cy = quad[2]  # BR corner
        od.polygon([(cx - 70, cy - 18), (cx + 60, cy - 8),
                    (cx + 40, cy + 70), (cx - 80, cy + 55)],
                   fill=(46, 46, 48, 255))
        canvas = Image.alpha_composite(canvas, oc.filter(ImageFilter.GaussianBlur(1.2)))

    if category == "low_light":
        arr = np.asarray(canvas).astype(np.float32)
        arr = np.clip(arr * 0.34, 0, 255)
        noise = np.random.normal(0, 6, arr.shape)
        arr = np.clip(arr + noise, 0, 255).astype(np.uint8)
        canvas = Image.fromarray(arr, "RGBA")

    return canvas.convert("RGB"), quad


# --------------------------------------------------------------------------- #
# Orchestration
# --------------------------------------------------------------------------- #
def write_synthdocs_txt(path: Path, quad) -> None:
    path.write_text(" ".join(f"{x:.1f},{y:.1f}" for x, y in quad))


def run_converter(stage_dir: Path, out_dir: Path, tag: str) -> None:
    """Invoke the existing converter (NOT reimplemented here)."""
    script = Path(__file__).parent / "synthdocs_to_dokodocs_fixtures.py"
    if not script.exists():
        raise FileNotFoundError(f"converter not found: {script}")
    cmd = [sys.executable, str(script),
           "--input-dir", str(stage_dir),
           "--output-dir", str(out_dir),
           "--tag", tag]
    print(f"  -> convert [{tag}]: {' '.join(cmd)}")
    subprocess.run(cmd, check=True)


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    here = Path(__file__).resolve().parent
    default_out = (here / "../../test/fixtures/detection/synthetic").resolve()
    p.add_argument("--out-dir", type=Path, default=default_out,
                   help="Where to write final PNG + fixture JSON")
    p.add_argument("--per-category", type=int, default=18,
                   help="Samples per category (9 categories -> 162 by default)")
    p.add_argument("--seed", type=int, default=1337)
    p.add_argument("--no-convert", action="store_true",
                   help="Only render images + SynthDocs .txt; skip the converter")
    args = p.parse_args()

    out_dir: Path = args.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    stage_root = here / "_build"
    if stage_root.exists():
        shutil.rmtree(stage_root)

    rng = np.random.default_rng(args.seed)
    py_rng = __import__("random").Random(args.seed)
    total = 0
    for tag, page_kind, bg_style in CATEGORIES:
        stage = stage_root / tag
        stage.mkdir(parents=True, exist_ok=True)
        for i in range(args.per_category):
            img, quad = render_sample(py_rng, tag, page_kind, bg_style)
            name = f"{tag}_{i + 1:04d}"
            # Stage BOTH image + SynthDocs .txt together: the converter pairs an
            # image with its same-basename .txt inside --input-dir.
            img.save(stage / f"{name}.png")
            write_synthdocs_txt(stage / f"{name}.txt", quad)
            total += 1
        if not args.no_convert:
            run_converter(stage, out_dir, tag)
            # Move the rendered PNGs next to their freshly-written JSON.
            for png in stage.glob("*.png"):
                shutil.move(str(png), str(out_dir / png.name))
        else:
            # Keep the .txt + .png so the converter can run later by hand.
            for f in stage.iterdir():
                shutil.copy(str(f), str(out_dir / f.name))

    if not args.no_convert:
        shutil.rmtree(stage_root, ignore_errors=True)

    jsons = list(out_dir.glob("*.json"))
    pngs = list(out_dir.glob("*.png"))
    print(f"\nGenerated {total} samples.")
    print(f"  PNGs : {len(pngs)}  in {out_dir}")
    print(f"  JSON : {len(jsons)} fixtures in {out_dir}")
    if args.no_convert:
        print("Skipped conversion (--no-convert).")
    elif len(jsons) != len(pngs):
        print("WARNING: image/JSON count mismatch — check converter output.",
              file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

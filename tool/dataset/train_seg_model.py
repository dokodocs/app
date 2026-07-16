#!/usr/bin/env python3
"""
Train a small document-segmentation U-Net for DokoDocs.

WHY: the classical OpenCV detector (document_detector_cv.dart) is strong on
full-page documents but weak on small cards/licenses in clutter (its one known
failure mode — see docs/SCANNER_V3_POSTMORTEM.md). An ML mask predicts the
document *region* directly, which is far more robust in clutter. The two are
fused at runtime as a hybrid adjudicator (document_segmenter.dart).

DATA: trained ONLY on the DokoDocs-generated synthetic fixtures
(`test/fixtures/detection/synthetic/`, seed 1337 — 162 composites across 9
categories, Apache-2.0, no real document content). See docs/dataset_notice.md.
Real third-party datasets are license-PENDING and are NOT used. The domain gap
to real photos is mitigated by (a) heavy augmentation and (b) the runtime
hybrid that never lets the ML output regress below the classical detector.

MODEL: a compact U-Net (8/16/32/64/128 filters, 4 levels) — input 256x256x1
grayscale, output 256x256x1 sigmoid document mask. ~hundreds of KB as float32
TFLite; runs in a few ms on-device.

Usage:
    python train_seg_model.py
        [--fixtures ../../test/fixtures/detection/synthetic]
        [--out ../../assets/models/docseg.tflite]
        [--img-size 256] [--epochs 60] [--batch 8] [--seed 1337]
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageOps

# TensorFlow logs are noisy; keep only errors unless TF_CPP_MIN_LOG_LEVEL set.
os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "3")
import tensorflow as tf  # noqa: E402
from tensorflow import keras  # noqa: E402
from tensorflow.keras import layers  # noqa: E402

CANVAS_W, CANVAS_H = 760, 1000  # synthetic fixture native size


# --------------------------------------------------------------------------- #
# Data: build (image, mask) pairs from synthetic fixtures
# --------------------------------------------------------------------------- #
def load_pairs(fixtures_dir: Path, img_size: int):
    """Load every <name>.png + sibling <name>.json into (image, mask) arrays.

    Both image and mask are resized to img_size x img_size (aspect squashed —
    the model learns the mapping; at inference the app resizes identically and
    rescales output quads back to native coords). The mask is the filled GT
    quad polygon (255 foreground).
    """
    images, masks, names, tags = [], [], [], []
    for jp in sorted(fixtures_dir.glob("*.json")):
        fix = json.loads(jp.read_text())
        ip = jp.with_suffix(".png")
        if not ip.exists():
            continue
        corners = fix.get("corners")
        if not corners or len(corners) != 4:
            continue
        img = Image.open(ip).convert("L").resize((img_size, img_size))
        # Scale GT quad from native canvas to the model's working size.
        sx, sy = img_size / CANVAS_W, img_size / CANVAS_H
        quad = [(float(c[0]) * sx, float(c[1]) * sy) for c in corners]
        m = Image.new("L", (img_size, img_size), 0)
        ImageDraw.Draw(m).polygon(quad, fill=255)
        images.append(np.asarray(img, dtype=np.float32) / 255.0)
        masks.append(np.asarray(m, dtype=np.float32) / 255.0)
        names.append(jp.stem)
        tags.append((fix.get("tags") or [None])[-1] or "untagged")
    return images, masks, names, tags


def stratified_split(names, tags, val_frac: float, seed: int):
    """Hold out val_frac per category so the reported IoU is honest across all
    9 categories (not dominated by any one)."""
    rng = np.random.default_rng(seed)
    by_cat: dict[str, list[int]] = {}
    for i, t in enumerate(tags):
        by_cat.setdefault(t, []).append(i)
    val_idx = []
    for cat, idxs in by_cat.items():
        idxs = list(idxs)
        rng.shuffle(idxs)
        n_val = max(1, round(len(idxs) * val_frac))
        val_idx.extend(idxs[:n_val])
    val_set = set(val_idx)
    train = [i for i in range(len(names)) if i not in val_set]
    val = [i for i in range(len(names)) if i in val_set]
    return train, val


# --------------------------------------------------------------------------- #
# Augmentation: applied identically to image + mask (geometric), then
# photometric to image only. Crucial to fight the 162-sample size + the
# synthetic->real domain gap.
# --------------------------------------------------------------------------- #
def augment(img_arr: np.ndarray, mask_arr: np.ndarray, rng, img_size: int):
    """One random augmentation. Returns new (img, mask) float arrays with a
    trailing channel dim. Geometric ops are applied IDENTICALLY to image and
    mask (rotation about centre + flips); photometric ops touch the image only.
    """
    img = Image.fromarray((img_arr * 255).astype(np.uint8), "L")
    mask = Image.fromarray((mask_arr * 255).astype(np.uint8), "L")

    # Geometric (shared) — Image.rotate is correct about the centre. One draw
    # of the angle keeps image and mask perfectly in lockstep.
    angle = rng.uniform(-18, 18)
    img = img.rotate(angle, resample=Image.BILINEAR)
    mask = mask.rotate(angle, resample=Image.NEAREST)
    if rng.random() < 0.5:
        img, mask = ImageOps.mirror(img), ImageOps.mirror(mask)
    if rng.random() < 0.5:
        img, mask = ImageOps.flip(img), ImageOps.flip(mask)
    # Ensure exact working size (rotations keep canvas, flips preserve it).
    if img.size != (img_size, img_size):
        img = img.resize((img_size, img_size), Image.BILINEAR)
        mask = mask.resize((img_size, img_size), Image.NEAREST)

    # Photometric (image only) — widens the synthetic->real gap coverage.
    arr = np.asarray(img, dtype=np.float32) / 255.0
    arr = arr * rng.uniform(0.7, 1.3)
    arr = (arr - 0.5) * rng.uniform(0.75, 1.35) + 0.5 + rng.uniform(-0.1, 0.1)
    arr = np.clip(arr, 0, 1) ** rng.uniform(0.7, 1.4)
    if rng.random() < 0.6:
        arr = arr + rng.normal(0, rng.uniform(0.01, 0.05), arr.shape)
    arr = np.clip(arr, 0, 1)

    img_arr = arr[..., None]
    mask_arr = (np.asarray(mask, dtype=np.float32) / 255.0)[..., None]
    return img_arr, mask_arr


class AugmentedSequence(keras.utils.Sequence):
    """On-the-fly augmented training batches (augmentation seeded per epoch)."""

    def __init__(self, images, masks, batch_size: int, aug_per: int,
                 seed: int, img_size: int):
        self.images = images
        self.masks = masks
        self.batch_size = batch_size
        self.aug_per = aug_per
        self.img_size = img_size
        self.base = list(range(len(images))) * aug_per
        self.rng = np.random.default_rng(seed)

    def __len__(self):
        return int(np.ceil(len(self.base) / self.batch_size))

    def on_epoch_end(self):
        self.rng.shuffle(self.base)

    def __getitem__(self, idx):
        batch_idx = self.base[idx * self.batch_size:(idx + 1) * self.batch_size]
        xs, ys = [], []
        for i in batch_idx:
            x, y = augment(self.images[i], self.masks[i], self.rng, self.img_size)
            xs.append(x)
            ys.append(y)
        return np.stack(xs), np.stack(ys)


# --------------------------------------------------------------------------- #
# Model: compact U-Net
# --------------------------------------------------------------------------- #
def conv_block(x, filters):
    x = layers.Conv2D(filters, 3, padding="same", use_bias=False)(x)
    x = layers.BatchNormalization()(x)
    x = layers.ReLU()(x)
    x = layers.Conv2D(filters, 3, padding="same", use_bias=False)(x)
    x = layers.BatchNormalization()(x)
    x = layers.ReLU()(x)
    return x


def build_unet(img_size: int) -> keras.Model:
    inputs = keras.Input((img_size, img_size, 1))
    c1 = conv_block(inputs, 8); p1 = layers.MaxPool2D()(c1)
    c2 = conv_block(p1, 16); p2 = layers.MaxPool2D()(c2)
    c3 = conv_block(p2, 32); p3 = layers.MaxPool2D()(c3)
    c4 = conv_block(p3, 64); p4 = layers.MaxPool2D()(c4)
    bn = conv_block(p4, 128)
    u4 = layers.Conv2DTranspose(64, 2, strides=2, padding="same")(bn)
    u4 = layers.Concatenate()([u4, c4]); c5 = conv_block(u4, 64)
    u3 = layers.Conv2DTranspose(32, 2, strides=2, padding="same")(c5)
    u3 = layers.Concatenate()([u3, c3]); c6 = conv_block(u3, 32)
    u2 = layers.Conv2DTranspose(16, 2, strides=2, padding="same")(c6)
    u2 = layers.Concatenate()([u2, c2]); c7 = conv_block(u2, 16)
    u1 = layers.Conv2DTranspose(8, 2, strides=2, padding="same")(c7)
    u1 = layers.Concatenate()([u1, c1]); c8 = conv_block(u1, 8)
    out = layers.Conv2D(1, 1, activation="sigmoid")(c8)
    return keras.Model(inputs, out)


def dice_bce_loss(y_true, y_pred):
    bce = keras.losses.binary_crossentropy(y_true, y_pred)
    ytf = tf.cast(y_true, tf.float32)
    inter = tf.reduce_sum(ytf * y_pred)
    denom = tf.reduce_sum(ytf + y_pred) + 1e-6
    dice = 1.0 - 2.0 * inter / denom
    return bce + 0.5 * dice


def iou_metric(y_true, y_pred):
    yt = tf.cast(y_true > 0.5, tf.float32)
    yp = tf.cast(y_pred > 0.5, tf.float32)
    inter = tf.reduce_sum(yt * yp)
    return inter / (tf.reduce_sum(yt + yp) - inter + 1e-6)


# --------------------------------------------------------------------------- #
# Mask -> quad (for an honest end-to-end IoU vs the GT quad, mirroring the
# Flutter harness). Pure numpy.
# --------------------------------------------------------------------------- #
def mask_to_quad(mask01: np.ndarray):
    """Foreground extreme points -> 4-point quad (TL,TR,BR,BL) in mask px.

    Mirrors the Dart `_orderCorners` rule so the validation IoU is faithful to
    what the runtime segmenter reports. Pure numpy (no extra deps).
    """
    ys, xs = np.where(mask01 > 0)
    if len(xs) < 4:
        return None
    pts = np.stack([xs, ys], axis=1).astype(np.float32)
    tl = pts[np.argmin(pts[:, 0] + pts[:, 1])]
    br = pts[np.argmax(pts[:, 0] + pts[:, 1])]
    tr = pts[np.argmin(pts[:, 1] - pts[:, 0])]
    bl = pts[np.argmax(pts[:, 1] - pts[:, 0])]
    return np.array([tl, tr, br, bl], dtype=np.float32)


def quad_iou(a, b):
    """Fast axis-aligned-bbox IoU of two quads (sufficient for ranking here)."""
    def bb(q):
        x0, y0 = q[:, 0].min(), q[:, 1].min()
        x1, y1 = q[:, 0].max(), q[:, 1].max()
        return x0, y0, x1, y1
    ax0, ay0, ax1, ay1 = bb(a)
    bx0, by0, bx1, by1 = bb(b)
    ix0, iy0 = max(ax0, bx0), max(ay0, by0)
    ix1, iy1 = min(ax1, bx1), min(ay1, by1)
    iw, ih = max(0.0, ix1 - ix0), max(0.0, iy1 - iy0)
    inter = iw * ih
    ua = (ax1 - ax0) * (ay1 - ay0) + (bx1 - bx0) * (by1 - by0) - inter
    return float(inter / ua) if ua > 0 else 0.0


# --------------------------------------------------------------------------- #
# Main
# --------------------------------------------------------------------------- #
def main() -> int:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    here = Path(__file__).resolve().parent
    p.add_argument("--fixtures", type=Path,
                   default=(here / "../../test/fixtures/detection/synthetic").resolve())
    p.add_argument("--out", type=Path,
                   default=(here / "../../assets/models/docseg.tflite").resolve())
    p.add_argument("--img-size", type=int, default=256)
    p.add_argument("--epochs", type=int, default=60)
    p.add_argument("--batch", type=int, default=8)
    p.add_argument("--aug-per", type=int, default=12)
    p.add_argument("--val-frac", type=float, default=0.15)
    p.add_argument("--seed", type=int, default=1337)
    args = p.parse_args()

    tf.keras.utils.set_random_seed(args.seed)
    img_size = args.img_size

    print(f"Loading fixtures from {args.fixtures}")
    images, masks, names, tags = load_pairs(args.fixtures, img_size)
    n = len(images)
    if n == 0:
        print("ERROR: no fixtures found. Run generate_synth_fixtures.py first.",
              file=sys.stderr)
        return 1
    print(f"  {n} pairs, {len(set(tags))} categories")

    train_idx, val_idx = stratified_split(names, tags, args.val_frac, args.seed)
    print(f"  split: {len(train_idx)} train / {len(val_idx)} val (per-category)")

    val_x = np.stack([images[i] for i in val_idx])[..., None]
    val_y = np.stack([masks[i] for i in val_idx])[..., None]
    val_tags = [tags[i] for i in val_idx]

    tr_imgs = [images[i] for i in train_idx]
    tr_masks = [masks[i] for i in train_idx]
    train_seq = AugmentedSequence(tr_imgs, tr_masks, args.batch,
                                  args.aug_per, args.seed, img_size)

    model = build_unet(img_size)
    model.compile(optimizer=keras.optimizers.Adam(1e-3),
                  loss=dice_bce_loss, metrics=[iou_metric])
    model.summary(print_fn=lambda s: print(s))

    cbs = [
        keras.callbacks.EarlyStopping(monitor="val_iou_metric", mode="max",
                                      patience=12, restore_best_weights=True),
        keras.callbacks.ReduceLROnPlateau(monitor="val_iou_metric", mode="max",
                                          factor=0.5, patience=5, min_lr=1e-5),
    ]
    model.fit(train_seq, validation_data=(val_x, val_y),
              epochs=args.epochs, callbacks=cbs, verbose=2)

    # Pixel IoU on the held-out split (the model's own metric).
    pred = model.predict(val_x, verbose=0)
    pix_ious = []
    for i in range(len(val_idx)):
        yt = (val_y[i, ..., 0] > 0.5).astype(np.float32)
        yp = (pred[i, ..., 0] > 0.5).astype(np.float32)
        inter = (yt * yp).sum()
        pix_ious.append(inter / (yt.sum() + yp.sum() - inter + 1e-6))
    print(f"\nHeld-out pixel IoU: mean={np.mean(pix_ious):.3f} "
          f"median={np.median(pix_ious):.3f} min={np.min(pix_ious):.3f}")

    # End-to-end quad IoU (mask -> largest contour quad vs GT quad) per category.
    print("\nPer-category quad IoU (mask->quad vs ground truth):")
    print(f"  {'category':<18} {'n':>3} {'meanIoU':>8}")
    by_cat: dict[str, list[float]] = {}
    for i in range(len(val_idx)):
        gt = mask_to_quad(val_y[i, ..., 0])
        pq = mask_to_quad((pred[i, ..., 0] > 0.5).astype(np.uint8))
        iou = quad_iou(gt, pq) if (gt is not None and pq is not None) else 0.0
        by_cat.setdefault(val_tags[i], []).append(iou)
    allv = []
    for cat in sorted(by_cat):
        vs = by_cat[cat]
        allv.extend(vs)
        print(f"  {cat:<18} {len(vs):>3} {np.mean(vs):>8.3f}")
    print(f"  {'ALL':<18} {len(allv):>3} {np.mean(allv):>8.3f}")

    # Export to TFLite (float32 — accurate and fast enough on-device).
    args.out.parent.mkdir(parents=True, exist_ok=True)
    conv = tf.lite.TFLiteConverter.from_keras_model(model)
    conv.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS]
    tflite = conv.convert()
    args.out.write_bytes(tflite)
    print(f"\nWrote {args.out} ({len(tflite) / 1024:.0f} KB)")

    # Metadata sidecar: the inference contract the Flutter segmenter must match.
    meta = {
        "model": "dokodocs-docseg-unet-v1",
        "input": {"shape": [1, img_size, img_size, 1], "dtype": "float32",
                  "range": "0..1", "color": "grayscale"},
        "output": {"shape": [1, img_size, img_size, 1], "dtype": "float32",
                   "range": "0..1", "threshold": 0.5},
        "resize": "bilinear (squash aspect); rescale output quad to native px",
        "trained_on": "synthetic fixtures seed 1337 (Apache-2.0), no real data",
        "heldout_quad_iou": round(float(np.mean(allv)), 3),
    }
    args.out.with_suffix(".tflite.json").write_text(json.dumps(meta, indent=2))
    print(f"Wrote {args.out.with_suffix('.tflite.json')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

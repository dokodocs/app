# Fetching / assembling datasets (maintainer-only)

DokoDocs ships **no** third-party dataset images. The committed benchmark set is
100% synthetic (see `generate_synth_fixtures.py`). The real datasets below are
optional, for **local** benchmarking only, and must be obtained by a maintainer
who accepts each dataset's licence (see `docs/DATASET_NOTICE.md` and
`dataset_inventory.md`).

## Local layout (all gitignored — never committed)

```
test/fixtures/detection/
├── synthetic/        # TRACKED — DokoDocs-generated PNG + fixture JSON
└── raw/              # GITIGNORED — your downloaded dataset frames + derived JSON
    ├── cord/
    ├── docbank/
    ├── smartdoc/      # only after licence verification
    └── ...
```

The detection harness (`test/detection_harness_test.dart`) scans the whole
`test/fixtures/detection/` tree (including `raw/`) for images, pairs each with a
sibling `<name>.json` fixture if present, and reports per-category IoU.

## 1. Synthetic fixtures (the committed set)

```bash
cd tool/dataset
pip install -r requirements.txt
python generate_synth_fixtures.py
```

Deterministic (`--seed`). Reproduces the committed 162 fixtures into
`test/fixtures/detection/synthetic/`. No network, no real data.

## 2. Real datasets — manual steps

Automated download is intentionally **not** provided: several of these require
access requests, click-through licences, or login, and DokoDocs must not be seen
to endorse redistribution. Fetch each manually only after verifying its licence
in `dataset_inventory.md`.

### CORD (receipts) — CC BY 4.0 ✅
- Download from Hugging Face: https://huggingface.co/datasets/naver-clova-ix/cord-v2
- Place receipt images in `test/fixtures/detection/raw/cord/`.
- CORD ships JSON with per-word `quad`s and a receipt `roi` quad. To make
  DokoDocs fixtures, extract the document quad per image (the `roi`, or the
  outer envelope of the word quads) and write a SynthDocs `.txt`
  (`x1,y1 x2,y2 x3,y3 x4,y4`) next to each image, then run:
  ```bash
  python tool/dataset/synthdocs_to_dokodocs_fixtures.py \
      --input-dir test/fixtures/detection/raw/cord \
      --output-dir test/fixtures/detection/raw/cord --tag receipt
  ```

### DocBank — Apache-2.0 ✅
- Download from Hugging Face: https://huggingface.co/datasets/liminghao1630/DocBank
- DocBank gives axis-aligned page bbox over a normalised 0–1000 grid, **not**
  camera-perspective document corners. It is useful for layout/texture, not for
  corner-detection IoU. If you need corner ground truth, generate it with the
  synthetic generator or annotate by hand.

### DTD — research-only ⚠️
- https://www.robots.ox.ac.uk/~vgg/data/dtd/ — research use only; **do not** use
  in any commercial/paid-tier build without written permission. DokoDocs' own
  generator already supplies procedural backgrounds, so DTD is optional.

### SmartDoc / MIDV-500 / UVDoc / Roboflow document-corners / SynthDocs ⏳
- **Licence PENDING.** Do **not** download until a maintainer verifies the
  current licence at the source listed in `dataset_inventory.md`. Once verified,
  place frames under `test/fixtures/detection/raw/<dataset>/` and convert any
  quad annotations with `synthdocs_to_dokodocs_fixtures.py`.

## 3. Auto-label-then-correct workflow (optional)

For datasets that ship **images without corner annotations**, use DokoDocs' own
OpenCV detector to produce initial corner estimates, then hand-correct:

1. Drop images into `test/fixtures/detection/raw/<set>/`.
2. Run the harness once; it writes `docs/detection_results/<name>.trace.json`
   containing the detected quad per image.
3. Promote the corrected quads into `<name>.json` fixtures (SynthDocs `.txt` →
   converter, or write the JSON directly).

This keeps DokoDocs free of any proprietary/trial-licensed annotation SDK.

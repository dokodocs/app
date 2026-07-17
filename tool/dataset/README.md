# `tool/dataset/` — DokoDocs detection dataset & benchmarking tooling

Python tooling that assembles the **synthetic** detection fixtures and
documents the real-world datasets a maintainer may benchmark against locally.
Nothing here is a Flutter/Dart dependency and **nothing here is bundled into a
release APK** (enforced by `verify_no_test_data_in_release.py` + the
`data_leak_check` CI workflow).

## Layout

| File | Purpose |
| --- | --- |
| `generate_synth_fixtures.py` | Renders 100% synthetic composites (no real document data) across the 9 benchmark categories and emits DokoDocs fixture JSON by **invoking** `synthdocs_to_dokodocs_fixtures.py`. |
| `synthdocs_to_dokodocs_fixtures.py` | Pre-existing converter: SynthDocs `x1,y1 x2,y2 x3,y3 x4,y4` annotation → DokoDocs fixture JSON (`{"image","corners","tags"}`). |
| `dataset_inventory.md` | License inventory / manifest of every dataset named in the v2 integration plan, with license + verification status. |
| `fetch_datasets.md` | How a maintainer obtains each real dataset **locally** (manual steps where automated download is impossible, e.g. SmartDoc access request). |
| `verify_no_test_data_in_release.py` | Build guard: fails if any `test/fixtures/detection/` or `tool/dataset/` path would leak into a release build (pubspec assets scan) **or** if a non-synthetic image is tracked in the fixtures dir. |
| `requirements.txt` | Python deps (numpy, Pillow) — tooling only. |

## Generate the fixtures

```bash
cd tool/dataset
pip install -r requirements.txt
python generate_synth_fixtures.py            # writes into test/fixtures/detection/synthetic/
```

Reproducible: pass `--seed`. The generator never downloads anything and never
reads real documents — the "text" is random grey rectangles. The only images it
produces are safe to commit (and are, under `test/fixtures/detection/synthetic/`).

## What gets committed vs. what stays local

- **Committed** (tracked): `test/fixtures/detection/synthetic/*.png` +
  `*.json` (DokoDocs-generated), the scripts here, and `docs/DATASET_NOTICE.md`.
- **Local only** (gitignored): any real dataset frames you download go in
  `test/fixtures/detection/raw/<dataset>/` — gitignored by design — and the
  harness results under `docs/detection_results/`.

See `docs/DATASET_NOTICE.md` for the licence posture and the "not redistributed"
statements for every dataset.

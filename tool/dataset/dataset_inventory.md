# Dataset Licence Inventory (maintainer manifest)

Machine-of-record companion to [`docs/DATASET_NOTICE.md`](../../docs/DATASET_NOTICE.md).
Every dataset in the v2 integration plan is listed here with its licence and
verification status. **Status is only authoritative when `verified` = yes and a
`verified_date` is set**; otherwise the licence must be confirmed at `source`
before any download or use.

| dataset | version | source | license | verified | verified_date | redistributed | local_path |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DokoDocs synthetic fixtures | seed 1337, 162 samples | `tool/dataset/generate_synth_fixtures.py` | Apache-2.0 | yes | 2026-07-15 | yes (committed) | `test/fixtures/detection/synthetic/` |
| CORD | v2 (1000 receipts) | https://github.com/clovaai/cord · https://huggingface.co/datasets/naver-clova-ix/cord-v2 | CC BY 4.0 | yes | 2026-07-15 | no | `test/fixtures/detection/raw/cord/` (local only) |
| DocBank | 500k pages | https://github.com/doc-analysis/DocBank · https://huggingface.co/datasets/liminghao1630/DocBank | Apache-2.0 (authors request no re-distribution) | yes | 2026-07-15 | no | `test/fixtures/detection/raw/docbank/` (local only) |
| DTD | r1.0.1 | https://www.robots.ox.ac.uk/~vgg/data/dtd/ | research-only; commercial needs permission | yes (terms) | 2026-07-15 | no | not used (procedural textures instead) |
| SmartDoc | 2015 challenge | ETS LIV4D · https://github.com/jcisio/SmartDoc-dataset | UNKNOWN | no | — | no | `test/fixtures/detection/raw/smartdoc/` (local only, after verification) |
| MIDV-500 | 2019 | Smart Engines — https://www.smartengines.com/ | UNKNOWN | no | — | no | `test/fixtures/detection/raw/midv500/` (local only, after verification) |
| UVDoc | — | tbd by maintainer | UNKNOWN | no | — | no | `test/fixtures/detection/raw/uvdoc/` (local only, after verification) |
| Roboflow document-corners (brilliantflux) | — | Roboflow Universe (brilliantflux) | UNKNOWN (per-project) | no | — | no | `test/fixtures/detection/raw/roboflow_doc_corners/` (local only, after verification) |
| SynthDocs (tony-xlh) | — | https://github.com/tony-xlh/SynthDocs | UNKNOWN | no | — | no | format only; no data consumed |

## Categories covered by the committed synthetic fixtures
`clean`, `cluttered_desk`, `low_light`, `curled_corner`, `multi_document`,
`id_card`, `receipt`, `similar_color_bg`, `occluded_corner` — 18 samples each
(162 total).

## Verification log
- **2026-07-15** — CORD: CC BY 4.0 confirmed from `clovaai/cord` (`LICENSE-CC-BY`
  + README statement). DocBank: Apache-2.0 confirmed from `doc-analysis/DocBank`
  (`LICENSE` + README *"We update the license to Apache-2.0"*). DTD: research-use
  terms confirmed from the VGG distribution page. SmartDoc / MIDV-500 / UVDoc /
  Roboflow document-corners / SynthDocs: canonical licence pages did not resolve
  to a positively-identifiable licence in this session → left PENDING.

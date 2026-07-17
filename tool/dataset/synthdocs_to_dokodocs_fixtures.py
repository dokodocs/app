#!/usr/bin/env python3
"""
Convert SynthDocs (tony-xlh/SynthDocs) annotations into DokoDocs fixture JSON.

SynthDocs annotation format (one .txt per image, same basename):
    x1,y1 x2,y2 x3,y3 x4,y4

DokoDocs fixture format (test/fixtures/detection/<name>.json):
    {
      "image": "<name>.jpg",
      "corners": [[x1,y1], [x2,y2], [x3,y3], [x4,y4]],
      "tags": ["synthdocs", "<source-tag>"]
    }

Usage:
    python synthdocs_to_dokodocs_fixtures.py \
        --input-dir path/to/synthdocs/output \
        --output-dir path/to/dokodocs/test/fixtures/detection \
        --tag receipt        # optional extra tag, e.g. document type or source

Assumes each image (<name>.jpg/.png) in --input-dir has a matching
<name>.txt annotation file in the same directory (SynthDocs' own output
layout). Images themselves are NOT copied by this script — copy them
separately into the fixtures directory, or point --output-dir at the
same folder as --input-dir if you want annotations alongside images.
"""

import argparse
import json
import sys
from pathlib import Path


def parse_synthdocs_annotation(txt_path: Path):
    """Parse a single SynthDocs annotation line into 4 [x, y] pairs."""
    line = txt_path.read_text().strip()
    if not line:
        raise ValueError(f"Empty annotation file: {txt_path}")

    points = []
    for pair in line.split():
        x_str, y_str = pair.split(",")
        points.append([float(x_str), float(y_str)])

    if len(points) != 4:
        raise ValueError(
            f"Expected 4 corner points in {txt_path}, got {len(points)}: {line}"
        )
    return points


def convert(input_dir: Path, output_dir: Path, extra_tag: str | None):
    output_dir.mkdir(parents=True, exist_ok=True)

    image_exts = {".jpg", ".jpeg", ".png"}
    images = [p for p in input_dir.iterdir() if p.suffix.lower() in image_exts]

    if not images:
        print(f"No images found in {input_dir}", file=sys.stderr)
        return 0

    converted = 0
    skipped = []

    for image_path in sorted(images):
        annotation_path = image_path.with_suffix(".txt")
        if not annotation_path.exists():
            skipped.append(image_path.name)
            continue

        try:
            corners = parse_synthdocs_annotation(annotation_path)
        except ValueError as e:
            print(f"Skipping {image_path.name}: {e}", file=sys.stderr)
            skipped.append(image_path.name)
            continue

        tags = ["synthdocs"]
        if extra_tag:
            tags.append(extra_tag)

        fixture = {
            "image": image_path.name,
            "corners": corners,
            "tags": tags,
        }

        out_path = output_dir / f"{image_path.stem}.json"
        out_path.write_text(json.dumps(fixture, indent=2))
        converted += 1

    print(f"Converted {converted} fixtures to {output_dir}")
    if skipped:
        print(f"Skipped {len(skipped)} images with missing/invalid annotations:", file=sys.stderr)
        for name in skipped:
            print(f"  - {name}", file=sys.stderr)

    return converted


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-dir", required=True, type=Path,
                         help="Directory containing SynthDocs images + .txt annotations")
    parser.add_argument("--output-dir", required=True, type=Path,
                         help="Directory to write DokoDocs fixture .json files "
                              "(e.g. test/fixtures/detection/)")
    parser.add_argument("--tag", default=None,
                         help="Optional extra tag to add to every fixture "
                              "(e.g. 'receipt', 'cluttered_desk')")
    args = parser.parse_args()

    if not args.input_dir.is_dir():
        print(f"Input directory not found: {args.input_dir}", file=sys.stderr)
        sys.exit(1)

    convert(args.input_dir, args.output_dir, args.tag)


if __name__ == "__main__":
    main()
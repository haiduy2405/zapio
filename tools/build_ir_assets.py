#!/usr/bin/env python3
"""Copy selected remotes from a local Flipper-IRDB checkout into assets/ir/.

Usage: python3 tools/build_ir_assets.py /path/to/Flipper-IRDB

Writes flat files assets/ir/<Category>__<Brand>__<file>.ir and
assets/ir/index.json. Source: https://github.com/UberGuidoZ/Flipper-IRDB (CC0-1.0
for contributions after commit 2319685 — see NOTICE.md; licence vetting per file
is a P1 task before store release).
"""
import json
import pathlib
import re
import shutil
import sys

SELECTION = {
    "ACs": ["Hisense", "Midea", "GREE", "Samsung", "Daikin", "LG", "Panasonic"],
    "TVs": ["Samsung", "Sony", "Hisense", "LG"],
    "Fans": ["Senko", "Panasonic"],
}
CATEGORY_NAMES = {"ACs": "AC", "TVs": "TV", "Fans": "Fan"}


def main(src: str) -> None:
    root = pathlib.Path(src)
    out = pathlib.Path(__file__).resolve().parent.parent / "assets" / "ir"
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    index = []
    for cat, brands in SELECTION.items():
        for brand in brands:
            folder = root / cat / brand
            if not folder.is_dir():
                print(f"skip missing {folder}")
                continue
            for f in sorted(folder.rglob("*.ir")):
                text = f.read_text(encoding="utf-8", errors="replace")
                if "name:" not in text:
                    continue
                safe = re.sub(r"[^A-Za-z0-9._-]+", "_", f.name)
                name = f"{cat}__{brand}__{safe}"
                (out / name).write_text(text, encoding="utf-8")
                index.append({
                    "category": CATEGORY_NAMES[cat],
                    "brand": brand.title() if brand.isupper() and len(brand) > 3 else brand,
                    "model": f.stem.replace("_", " "),
                    "asset": f"assets/ir/{name}",
                })
    (out / "index.json").write_text(json.dumps(index, indent=1), encoding="utf-8")
    print(f"{len(index)} remotes written to {out}")


if __name__ == "__main__":
    main(sys.argv[1])

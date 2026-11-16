#!/usr/bin/env python3
"""Build Zapio's bundled IR code DB from flipperdevices/irdb (MIT).

Usage: python3 tools/build_irdb.py /path/to/flipperdevices-irdb

Output: assets/irdb/<Category>.json.gz  (one file per category)
Each remote: {id, brand, model, prov, keys:{STD_KEY: idx}, s:[signals]}
  parsed signal: [name, protocol, address, command]
  raw signal:    [name, frequency, [durations...]]
prov = provenance tag from the file name ("kk", "xm", "mx" or "other");
see NOTICE.md — lets the release build filter by source.
"""
import gzip, json, pathlib, re, sys, hashlib

CATEGORIES = {
    "TVs": "TV", "Fan": "Fan", "Projector": "Projector", "Box": "Box",
    "A_V_receiver": "Audio", "Air_Purifiers": "AirPurifier",
}

def le(s):
    b = [int(x, 16) for x in s.split()]
    v = 0
    for x in reversed(b):
        v = (v << 8) | x
    return v

def parse_ir(text):
    sigs, cur = [], None
    def flush():
        if cur and "name" in cur and "type" in cur:
            try:
                if cur["type"] == "raw":
                    d = [abs(int(x)) for x in cur["data"].split()]
                    if d:
                        sigs.append([cur["name"], int(float(cur.get("frequency", 38000))), d])
                elif cur["type"] == "parsed":
                    sigs.append([cur["name"], cur["protocol"], le(cur["address"]), le(cur["command"])])
            except Exception:
                pass
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#") or ":" not in line:
            continue
        k, v = line.split(":", 1)
        k, v = k.strip(), v.strip()
        if k == "name":
            flush(); cur = {}
        if cur is None:
            continue
        if k == "data" and "data" in cur:
            cur["data"] += " " + v
        else:
            cur[k] = v
    flush()
    return sigs

def prov(name):
    m = re.search(r"_\d+_([a-z]{2})_\d+_", name)
    return m.group(1) if m else "other"

def pretty(brand, folder):
    model = folder[len(brand):].strip("_") if folder.startswith(brand) else folder
    m = re.match(r"^\d+_[a-z]{2}_\d+_\d+(?:_(\d+))?$", model) or re.match(r"^\d+_[a-z]{2}_\d+_(\d+)", model)
    if m:  # DB-style ids like 125_xm_1_131 -> "Code 131"
        return "Code " + (m.group(m.lastindex) if m.lastindex else model.split("_")[-1])
    return model.replace("_", " ") or folder

def main(src):
    root = pathlib.Path(src) / "database" / "categories"
    out = pathlib.Path(__file__).resolve().parent.parent / "assets" / "irdb"
    out.mkdir(parents=True, exist_ok=True)
    for old in out.glob("*.json.gz"):
        old.unlink()
    total = 0
    for cat, label in CATEGORIES.items():
        remotes = []
        for brand_dir in sorted(p for p in (root / cat).iterdir() if p.is_dir() and not p.name.startswith(".")):
            for rdir in sorted(p for p in brand_dir.iterdir() if p.is_dir()):
                irs = list(rdir.glob("*.ir"))
                if not irs:
                    continue
                sigs = parse_ir(irs[0].read_text(encoding="utf-8", errors="replace"))
                if not sigs:
                    continue
                keys = {}
                cfg = rdir / "config.json"
                if cfg.exists():
                    try:
                        km = json.loads(cfg.read_text())["key_map"]
                        names = [s[0] for s in sigs]
                        for std, info in km.items():
                            kn = info.get("key_name")
                            if kn in names:
                                keys[std] = names.index(kn)
                    except Exception:
                        pass
                remotes.append({
                    "id": f"{cat}/{brand_dir.name}/{rdir.name}",
                    "brand": brand_dir.name.replace("_", " "),
                    "model": pretty(brand_dir.name, rdir.name),
                    "prov": prov(rdir.name),
                    "keys": keys,
                    "s": sigs,
                })
        data = json.dumps({"category": label, "remotes": remotes}, separators=(",", ":")).encode()
        (out / f"{label}.json.gz").write_bytes(gzip.compress(data, 9))
        total += len(remotes)
        print(f"{label}: {len(remotes)} remotes, {len(data)//1024} KB raw, "
              f"{(out / f'{label}.json.gz').stat().st_size//1024} KB gz")
    print("total", total)

if __name__ == "__main__":
    main(sys.argv[1])

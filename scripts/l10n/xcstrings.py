#!/usr/bin/env python3
"""String Catalog tools for Pinxel.

merge <catalog.xcstrings> <table.tsv>
    TSV columns: key, it, de, fr, comment (optional). Adds or replaces those
    entries (state "translated"); other entries are kept. Keys are the English
    source strings exactly as written in code (interpolations as %lld / %@).

coverage <derivedDataPath> <repoRoot>
    Reads the *.stringsdata files written by an Xcode build with
    SWIFT_EMIT_LOC_STRINGS=YES and reports, per catalog, keys used in code but
    missing from the catalog and catalog keys no longer used. Exit 1 if any key
    is missing.
"""
import csv
import glob
import json
import os
import sys

LANGS = ["it", "de", "fr"]
CATALOGS = {
    "Pinxel.build": ("App/Pinxel/Localizable.xcstrings", "Localizable"),
    "DocumentModel": ("PinxelKit/Sources/DocumentModel/Localizable.xcstrings", "Localizable"),
    "EditorUI": ("PinxelKit/Sources/EditorUI/Localizable.xcstrings", "Localizable"),
    "AppCore": ("PinxelKit/Sources/AppCore/Localizable.xcstrings", "Localizable"),
}


def load(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def save(path, catalog):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(catalog, f, ensure_ascii=False, indent=2, sort_keys=True, separators=(",", " : "))
        f.write("\n")


def merge(catalog_path, table_path):
    catalog = load(catalog_path)
    strings = catalog.setdefault("strings", {})
    with open(table_path, encoding="utf-8") as f:
        for row in csv.reader(f, delimiter="\t"):
            if not row or row[0].startswith("#"):
                continue
            key, values, comment = row[0], row[1:4], (row[4] if len(row) > 4 else "")
            if len(values) != 3 or not all(values):
                sys.exit(f"incomplete row for {key!r}")
            entry = {"localizations": {lang: {"stringUnit": {"state": "translated", "value": value}}
                                       for lang, value in zip(LANGS, values)}}
            if comment:
                entry["comment"] = comment
            strings[key] = entry
    save(catalog_path, catalog)


def coverage(derived, root):
    used = {name: set() for name in CATALOGS}
    for path in glob.glob(os.path.join(derived, "Build/Intermediates.noindex/**/*.stringsdata"), recursive=True):
        owner = next((name for name in CATALOGS if f"/{name}/" in path or f"/{name}-" in path), None)
        if owner is None:
            continue
        table = CATALOGS[owner][1]
        for entry in load(path).get("tables", {}).get(table, []):
            used[owner].add(entry["key"])
    missing_any = False
    for name, (catalog_path, _) in CATALOGS.items():
        path = os.path.join(root, catalog_path)
        keys = set(load(path).get("strings", {})) if os.path.exists(path) else set()
        missing, unused = sorted(used[name] - keys), sorted(keys - used[name])
        print(f"{name}: {len(used[name])} used, {len(missing)} missing, {len(unused)} unused")
        for key in missing:
            print(f"  missing: {key}")
        for key in unused:
            print(f"  unused:  {key}")
        missing_any = missing_any or bool(missing)
    sys.exit(1 if missing_any else 0)


if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "merge":
        merge(sys.argv[2], sys.argv[3])
    elif len(sys.argv) == 4 and sys.argv[1] == "coverage":
        coverage(sys.argv[2], sys.argv[3])
    else:
        sys.exit(__doc__)

#!/usr/bin/env python3
import json
from pathlib import Path

from csv_to_resource import normalize_address

ROOT = Path(__file__).resolve().parents[1]
DB_PATH = ROOT / "resources" / "data" / "intersections.json"

def main():
    if not DB_PATH.exists():
        print(f"File not found: {DB_PATH}")
        return

    with open(DB_PATH, "r", encoding="utf-8") as f:
        data = json.load(f)

    cleaned_count = 0
    for entry in data:
        original_addr = entry[4]
        cleaned_addr = normalize_address(original_addr)
        if cleaned_addr != original_addr:
            entry[4] = cleaned_addr
            cleaned_count += 1
            print(f"Cleaned: '{original_addr}' -> '{cleaned_addr}'")

    if cleaned_count > 0:
        with open(DB_PATH, "w", encoding="utf-8", newline="\n") as f:
            json.dump(data, f, ensure_ascii=False, separators=(",", ":"))
        print(f"Successfully cleaned {cleaned_count} addresses in intersections.json.")
    else:
        print("No duplicated municipality names found in intersections.json.")

if __name__ == "__main__":
    main()

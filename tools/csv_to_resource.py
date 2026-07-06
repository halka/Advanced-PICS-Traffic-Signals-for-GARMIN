#!/usr/bin/env python3
"""
csv_to_resource.py
全国交差点CSVを Connect IQ JSON リソースに変換する。

使い方:
    python3 tools/csv_to_resource.py [input_csv] [output_json]

出力フォーマット (メモリ効率を優先したフラット配列):
    [[lat, lon, "交差点名称", "ひらがな", "住所"], ...]
"""

import csv
import json
import os
import sys

DEFAULT_INPUT  = os.path.expanduser("~/Downloads/250501-zenkoku-kousaten.csv")
DEFAULT_OUTPUT = os.path.join(
    os.path.dirname(__file__), "..", "resources", "data", "intersections.json"
)

def convert(input_path: str, output_path: str) -> None:
    entries = []
    with open(input_path, encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            try:
                lat = float(row['lat']) if 'lat' in row and row['lat'] else 0.0
                lon = float(row['lon']) if 'lon' in row and row['lon'] else 0.0
            except ValueError:
                continue
            
            name = row.get('intersection', '')
            hira = row.get('hiragana', '')
            addr = row.get('pref', '') + row.get('city', '') + row.get('address', '')
            
            entries.append([lat, lon, name, hira, addr])

    os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)
    with open(output_path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(entries, f, ensure_ascii=False, separators=(",", ":"))

    print(f"変換完了: {len(entries)} 件 -> {output_path}")

if __name__ == "__main__":
    inp = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_INPUT
    out = sys.argv[2] if len(sys.argv) > 2 else DEFAULT_OUTPUT
    convert(inp, out)

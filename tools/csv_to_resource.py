#!/usr/bin/env python3
"""
csv_to_resource.py
全国交差点CSVを Connect IQ JSON リソースに変換する。

使い方:
    python3 tools/csv_to_resource.py [input_csv] [output_json]

デフォルト:
    input : ~/Downloads/250501-zenkoku-kousaten.csv
    output: resources/data/intersections.json

出力フォーマット (メモリ効率を優先したフラット配列):
    [[lat_int, lon_int, "交差点名称"], ...]
    - lat/lon は整数 (度 × 1,000,000)
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
        reader = csv.reader(f)
        for row_num, row in enumerate(reader, start=1):
            # ヘッダー行・短い行はスキップ
            if len(row) < 7:
                continue
            name = row[2].strip()
            lat_str = row[5].strip()
            lon_str = row[6].strip()
            # 数値でない行（ヘッダー等）をスキップ
            try:
                lat_int = round(float(lat_str) * 1_000_000)
                lon_int = round(float(lon_str) * 1_000_000)
            except ValueError:
                continue
            if not name:
                continue
            entries.append([lat_int, lon_int, name])

    os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(entries, f, ensure_ascii=False, separators=(",", ":"))

    print(f"変換完了: {len(entries)} 件 -> {output_path}")

if __name__ == "__main__":
    inp = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_INPUT
    out = sys.argv[2] if len(sys.argv) > 2 else DEFAULT_OUTPUT
    convert(inp, out)

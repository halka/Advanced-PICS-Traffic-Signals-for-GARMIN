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
import re
import sys

DEFAULT_INPUT  = os.path.expanduser("~/Downloads/250501-zenkoku-kousaten.csv")
DEFAULT_OUTPUT = os.path.join(
    os.path.dirname(__file__), "..", "resources", "data", "intersections.json"
)

REQUIRED_COLUMNS = ("pref", "city", "intersection", "hiragana", "address", "lat", "lon")
NUMBER_PREFIX = re.compile(r"^\s*([+-]?\d+(?:\.\d+)?)")

PREFECTURES = [
    "北海道", "青森県", "岩手県", "宮城県", "秋田県", "山形県", "福島県",
    "茨城県", "栃木県", "群馬県", "埼玉県", "千葉県", "東京都", "神奈川県",
    "新潟県", "富山県", "石川県", "福井県", "山梨県", "長野県", "岐阜県",
    "静岡県", "愛知県", "三重県", "滋賀県", "京都府", "大阪府", "兵庫県",
    "奈良県", "和歌山県", "鳥取県", "島根県", "岡山県", "広島県", "山口県",
    "徳島県", "香川県", "愛媛県", "高知県", "福岡県", "佐賀県", "長崎県",
    "熊本県", "大分県", "宮崎県", "鹿児島県", "沖縄県",
]


def normalize_address(addr: str) -> str:
    """Remove repeated prefecture/city prefixes from the NPA CSV address."""
    addr = addr.strip()
    for pref in PREFECTURES:
        if not addr.startswith(pref):
            continue

        remain = addr[len(pref):]
        match = re.match(r"^(.+?[市区町村])", remain)
        if not match:
            continue

        city = match.group(1)
        duplicated = ((pref + city + pref + city), (pref + city + city))
        for prefix in duplicated:
            if addr.startswith(prefix):
                return normalize_address(pref + city + addr[len(prefix):])

    match = re.search(r"([一-龠ぁ-んァ-ンー]+?[市区町村])\1", addr)
    if match:
        dup = match.group(1)
        return normalize_address(addr.replace(dup + dup, dup, 1))

    return addr


def validate_header(fieldnames) -> None:
    missing = [col for col in REQUIRED_COLUMNS if col not in (fieldnames or [])]
    if missing:
        raise ValueError("CSV missing required columns: " + ", ".join(missing))


def parse_number(value: str) -> float:
    match = NUMBER_PREFIX.match(value or "")
    if not match:
        raise ValueError(value)
    return float(match.group(1))


def convert(input_path: str, output_path: str) -> None:
    entries = []
    with open(input_path, encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)
        validate_header(reader.fieldnames)
        for row_num, row in enumerate(reader, start=2):
            try:
                lat = parse_number(row["lat"])
                lon = parse_number(row["lon"])
            except ValueError:
                print(f"skip row {row_num}: invalid lat/lon", file=sys.stderr)
                continue

            name = row.get("intersection", "").strip()
            hira = row.get("hiragana", "").strip()
            addr = normalize_address(
                row.get("pref", "").strip()
                + row.get("city", "").strip()
                + row.get("address", "").strip()
            )
            if not name or not addr:
                print(f"skip row {row_num}: missing name/address", file=sys.stderr)
                continue

            entries.append([lat, lon, name, hira, addr])

    os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)
    with open(output_path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(entries, f, ensure_ascii=False, separators=(",", ":"))

    print(f"変換完了: {len(entries)} 件 -> {output_path}")

if __name__ == "__main__":
    inp = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_INPUT
    out = sys.argv[2] if len(sys.argv) > 2 else DEFAULT_OUTPUT
    convert(inp, out)

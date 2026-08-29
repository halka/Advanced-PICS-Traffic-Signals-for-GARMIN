#!/usr/bin/env python3
"""
csv_to_resource.py
全国交差点CSVを Connect IQ JSON リソースに変換する。

使い方:
    python3 tools/csv_to_resource.py [input_csv] [output_json]

出力フォーマット (メモリ効率を優先したフラット配列):
    [[lat, lon, "交差点名称", "ひらがな", "住所"], ...]
"""

import argparse
import csv
import json
import math
import re
import sys
from pathlib import Path
from typing import Union

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_INPUT = Path.home() / "Downloads" / "250501-zenkoku-kousaten.csv"
DEFAULT_OUTPUT = ROOT / "resources" / "data" / "intersections.json"

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
    number = float(match.group(1))
    if not math.isfinite(number):
        raise ValueError(value)
    return number


def is_valid_coordinate(lat: float, lon: float) -> bool:
    return -90.0 <= lat <= 90.0 and -180.0 <= lon <= 180.0


def convert(input_path: Union[str, Path], output_path: Union[str, Path]) -> int:
    input_path = Path(input_path)
    output_path = Path(output_path)
    entries = []
    with input_path.open(encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)
        validate_header(reader.fieldnames)
        for row_num, row in enumerate(reader, start=2):
            try:
                lat = parse_number(row["lat"])
                lon = parse_number(row["lon"])
            except ValueError:
                print(f"skip row {row_num}: invalid lat/lon", file=sys.stderr)
                continue
            if not is_valid_coordinate(lat, lon):
                print(f"skip row {row_num}: lat/lon out of range", file=sys.stderr)
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

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="utf-8", newline="\n") as f:
        json.dump(entries, f, ensure_ascii=False, separators=(",", ":"))

    print(f"変換完了: {len(entries)} 件 -> {output_path}")
    return len(entries)


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="全国交差点CSVをConnect IQ JSONリソースへ変換します。"
    )
    parser.add_argument("input_csv", nargs="?", type=Path, default=DEFAULT_INPUT)
    parser.add_argument("output_json", nargs="?", type=Path, default=DEFAULT_OUTPUT)
    return parser.parse_args()


def main() -> None:
    args = parse_arguments()
    convert(args.input_csv, args.output_json)


if __name__ == "__main__":
    main()

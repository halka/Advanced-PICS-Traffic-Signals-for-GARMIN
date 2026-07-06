#!/usr/bin/env python3
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DB_PATH = ROOT / "resources" / "data" / "intersections.json"

PREFECTURES = [
    "北海道", "青森県", "岩手県", "宮城県", "秋田県", "山形県", "福島県",
    "茨城県", "栃木県", "群馬県", "埼玉県", "千葉県", "東京都", "神奈川県",
    "新潟県", "富山県", "石川県", "福井県", "山梨県", "長野県", "岐阜県",
    "静岡県", "愛知県", "三重県", "滋賀県", "京都府", "大阪府", "兵庫県",
    "奈良県", "和歌山県", "鳥取県", "島根県", "岡山県", "広島県", "山口県",
    "徳島県", "香川県", "愛媛県", "高知県", "福岡県", "佐賀県", "長崎県",
    "熊本県", "大分県", "宮崎県", "鹿児島県", "沖縄県"
]

def clean_address(addr: str) -> str:
    # 1. プレフィックスの重複を除去する
    # 例: "東京都新宿区東京都新宿区戸山..." -> "東京都新宿区戸山..."
    for pref in PREFECTURES:
        if addr.startswith(pref):
            remain = addr[len(pref):]
            # 市区町村の抽出 (例: 新宿区, 札幌市, 札幌市中央区, 仙台市青葉区, 横浜市中区など)
            # 市、区、町、村で終わる最長の部分をマッチさせる
            match = re.match(r"^([^\u3000-\u303F\u4E00-\u9FFF]+|[一-龠]+?[市区町村])", remain)
            if match:
                city = match.group(1)
                # パターンA: pref + city + pref + city (例: 東京都新宿区東京都新宿区)
                double_pattern_1 = pref + city + pref + city
                if addr.startswith(double_pattern_1):
                    cleaned = pref + city + addr[len(double_pattern_1):]
                    return clean_address(cleaned)
                
                # パターンB: pref + city + city (例: 北海道札幌市札幌市中央区)
                double_pattern_2 = pref + city + city
                if addr.startswith(double_pattern_2):
                    cleaned = pref + city + addr[len(double_pattern_2):]
                    return clean_address(cleaned)

    # 2. 市区町村が連続して並んでいる場合の一般的な重複チェック
    # 例: "札幌市札幌市中央区" -> "札幌市中央区"
    # 例: "横浜市横浜市中区" -> "横浜市中区"
    match = re.search(r"([一-龠]+?[市区町村])\1", addr)
    if match:
        dup = match.group(1)
        cleaned = addr.replace(dup + dup, dup, 1)
        return clean_address(cleaned)
        
    return addr

def main():
    if not DB_PATH.exists():
        print(f"File not found: {DB_PATH}")
        return

    with open(DB_PATH, "r", encoding="utf-8") as f:
        data = json.load(f)

    cleaned_count = 0
    for entry in data:
        original_addr = entry[4]
        cleaned_addr = clean_address(original_addr)
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

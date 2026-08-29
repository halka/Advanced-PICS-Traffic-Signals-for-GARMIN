import csv
import json
import sys
import tempfile
import unittest
from pathlib import Path


TOOLS_DIR = Path(__file__).resolve().parents[1] / "tools"
sys.path.insert(0, str(TOOLS_DIR))

from csv_to_resource import convert, normalize_address, parse_number  # noqa: E402


class CsvToResourceTests(unittest.TestCase):
    def test_normalize_address_removes_repeated_municipality(self):
        self.assertEqual(
            normalize_address("北海道札幌市北海道札幌市中央区北五条"),
            "北海道札幌市中央区北五条",
        )
        self.assertEqual(
            normalize_address("北海道札幌市札幌市中央区北五条"),
            "北海道札幌市中央区北五条",
        )

    def test_parse_number_accepts_csv_suffix(self):
        self.assertEqual(parse_number("43.125 degrees"), 43.125)
        with self.assertRaises(ValueError):
            parse_number("not-a-number")

    def test_convert_skips_invalid_coordinates_and_rows(self):
        fieldnames = [
            "pref",
            "city",
            "intersection",
            "hiragana",
            "address",
            "lat",
            "lon",
        ]
        rows = [
            {
                "pref": "北海道",
                "city": "札幌市",
                "intersection": "テスト交差点",
                "hiragana": "てすとこうさてん",
                "address": "札幌市中央区北一条",
                "lat": "43.0",
                "lon": "141.0",
            },
            {
                "pref": "北海道",
                "city": "札幌市",
                "intersection": "範囲外",
                "hiragana": "はんいがい",
                "address": "札幌市中央区北二条",
                "lat": "91.0",
                "lon": "141.0",
            },
            {
                "pref": "北海道",
                "city": "札幌市",
                "intersection": "",
                "hiragana": "なまえなし",
                "address": "札幌市中央区北三条",
                "lat": "43.1",
                "lon": "141.1",
            },
        ]

        with tempfile.TemporaryDirectory() as temp_dir:
            input_path = Path(temp_dir) / "input.csv"
            output_path = Path(temp_dir) / "output.json"
            with input_path.open("w", encoding="utf-8", newline="") as csv_file:
                writer = csv.DictWriter(csv_file, fieldnames=fieldnames)
                writer.writeheader()
                writer.writerows(rows)

            self.assertEqual(convert(input_path, output_path), 1)
            data = json.loads(output_path.read_text(encoding="utf-8"))

        self.assertEqual(
            data,
            [[43.0, 141.0, "テスト交差点", "てすとこうさてん", "北海道札幌市中央区北一条"]],
        )

    def test_convert_rejects_missing_columns(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            input_path = Path(temp_dir) / "input.csv"
            output_path = Path(temp_dir) / "output.json"
            input_path.write_text("lat,lon\n43,141\n", encoding="utf-8")

            with self.assertRaisesRegex(ValueError, "missing required columns"):
                convert(input_path, output_path)


if __name__ == "__main__":
    unittest.main()

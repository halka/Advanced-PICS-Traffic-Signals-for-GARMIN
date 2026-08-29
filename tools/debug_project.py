#!/usr/bin/env python3
"""
debug_project.py
Advanced PICS for GARMIN: project diagnostics helper.

Usage:
    python3 tools/debug_project.py
    python3 tools/debug_project.py --all
    python3 tools/debug_project.py --manifest --resources --source
"""

import argparse
import json
import os
import re
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
IQ_NAMESPACE = "http://www.garmin.com/xml/connectiq"
SDK_NAME_RE = re.compile(r"connectiq-sdk-(?:mac|win|linux)-([0-9]+(?:\.[0-9]+)*)")


def sdk_roots():
    home = Path.home()
    candidates = [
        home / "Library" / "Application Support" / "Garmin" / "ConnectIQ" / "Sdks",
        home / "AppData" / "Roaming" / "Garmin" / "ConnectIQ" / "Sdks",
        home / "AppData" / "Local" / "Garmin" / "ConnectIQ" / "Sdks",
        home / "Garmin" / "ConnectIQ" / "Sdks",
        home / ".Garmin" / "ConnectIQ" / "Sdks",
    ]
    env_root = os.environ.get("CONNECTIQ_SDK_HOME")
    if env_root:
        candidates.insert(0, Path(env_root))
    return candidates


def parse_manifest(manifest_path: Path):
    if not manifest_path.exists():
        return None

    ns = {"iq": IQ_NAMESPACE}
    tree = ET.parse(manifest_path)
    root = tree.getroot()
    app = root.find("iq:application", ns)
    if app is None:
        app = root.find("application")
    if app is None:
        raise RuntimeError("manifest.xml の application 要素が見つかりませんでした。")

    products = [prod.get("id") for prod in app.findall("iq:products/iq:product", ns)]
    if not products:
        products = [prod.get("id") for prod in app.findall("products/product")]

    permissions = [perm.get("id") for perm in app.findall("iq:permissions/iq:uses-permission", ns)]
    if not permissions:
        permissions = [perm.get("id") for perm in app.findall("permissions/uses-permission")]

    return {
        "path": manifest_path,
        "entry": app.get("entry"),
        "id": app.get("id"),
        "minApiLevel": app.get("minApiLevel"),
        "type": app.get("type"),
        "version": app.get("version"),
        "launcherIcon": app.get("launcherIcon"),
        "products": products,
        "permissions": permissions,
    }


def get_installed_sdk_versions():
    versions = []
    seen = set()
    for root in sdk_roots():
        try:
            exists = root.exists()
        except OSError:
            continue
        if not exists:
            continue
        try:
            children = sorted(root.iterdir())
        except OSError:
            continue
        for item in children:
            try:
                is_dir = item.is_dir()
            except OSError:
                continue
            if not is_dir or item in seen:
                continue
            seen.add(item)
            match = SDK_NAME_RE.search(item.name)
            if match:
                versions.append({"name": item.name, "version": match.group(1), "path": item})
    return sorted(versions, key=lambda item: version_tuple(item["version"]))


def version_tuple(version):
    return tuple(int(part) for part in version.split("."))


def read_intersection_db(db_path: Path):
    if not db_path.exists():
        return None
    try:
        with db_path.open("r", encoding="utf-8") as f:
            entries = json.load(f)
    except Exception as exc:
        raise RuntimeError(f"JSON 読み込みに失敗しました: {exc}")

    return entries


def find_source_patterns(source_dir: Path, patterns):
    matches = []
    for path in source_dir.rglob("*.mc"):
        if path.name == "ApiFlags.mc":
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            text = path.read_text(encoding="utf-8", errors="ignore")
        for lineno, line in enumerate(text.splitlines(), start=1):
            lower = line.lower()
            for label, keyword in patterns.items():
                if keyword in lower:
                    matches.append({"file": path.relative_to(ROOT), "line": lineno, "text": line.strip(), "label": label})
    return matches


def report_manifest():
    manifest_path = ROOT / "manifest.xml"
    info = parse_manifest(manifest_path)
    if info is None:
        print("manifest.xml が見つかりません。")
        return

    print("[manifest.xml]")
    print(f"path: {info['path']}")
    print(f"entry: {info['entry']}")
    print(f"id: {info['id']}")
    print(f"minApiLevel: {info['minApiLevel']}")
    print(f"type: {info['type']}")
    print(f"version: {info['version']}")
    print(f"launcherIcon: {info['launcherIcon']}")
    print(f"products: {', '.join(info['products']) if info['products'] else '(none)'}")
    print(f"permissions: {', '.join(info['permissions']) if info['permissions'] else '(none)'}")

    sdk_versions = get_installed_sdk_versions()
    print()
    if sdk_versions:
        latest = sdk_versions[-1]
        print(f"installed latest SDK: {latest['name']} (version: {latest['version']})")
        if info['minApiLevel']:
            try:
                manifest_ver = version_tuple(info['minApiLevel'])
                latest_ver = version_tuple(latest['version'])
                cmp_text = "<=" if manifest_ver <= latest_ver else ">"
                print(f"manifest minApiLevel {cmp_text} installed latest SDK version")
            except ValueError:
                print("manifest の minApiLevel を解析できませんでした。")
    else:
        print("Connect IQ SDK がインストールされていません。")


def report_resources():
    db_path = ROOT / "resources" / "data" / "intersections.json"
    print("[resources/data/intersections.json]")
    if not db_path.exists():
        print(f"ファイルが存在しません: {db_path}")
        return
    try:
        entries = read_intersection_db(db_path)
    except Exception as exc:
        print(str(exc))
        return

    if not isinstance(entries, list):
        print("JSON のルートが配列ではありません。")
        return

    print(f"entries: {len(entries)}")
    if entries:
        first = entries[0]
        print(f"first entry sample: {first}")
        if isinstance(first, list) and len(first) >= 3:
            print("entry format appears to be [lat, lon, name, hiragana, address].")


def report_source():
    source_dir = ROOT / "source"
    if not source_dir.exists():
        print("source ディレクトリが見つかりません。")
        return

    print("[source scan]")
    patterns = {
        "screenshot": "screenshot",
        "todo": "todo",
        "fixme": "fixme",
        "deprecated": "deprecated",
    }
    matches = find_source_patterns(source_dir, patterns)
    if not matches:
        print("該当するキーワードは見つかりませんでした。")
        return
    for match in matches:
        print(f"{match['file']}:{match['line']} [{match['label']}] {match['text']}")


def report_readme():
    readme_path = ROOT / "README.md"
    if not readme_path.exists():
        print("README.md が見つかりません。")
        return

    print("[README.md]")
    text = readme_path.read_text(encoding="utf-8")
    lines = text.splitlines()
    for i, line in enumerate(lines, 1):
        if "Connect IQ API Level" in line or "Connect IQ SDK" in line:
            print(f"{i}: {line}")


def parse_arguments():
    parser = argparse.ArgumentParser(description="Advanced PICS project diagnostics")
    parser.add_argument("--manifest", action="store_true", help="Check manifest.xml")
    parser.add_argument("--resources", action="store_true", help="Check intersection JSON resources")
    parser.add_argument("--source", action="store_true", help="Scan source files for debug keywords")
    parser.add_argument("--readme", action="store_true", help="Inspect README version references")
    parser.add_argument("--sdk", action="store_true", help="Report installed Connect IQ SDK versions")
    parser.add_argument("--generate-api-flags", action="store_true", help="Write source/ApiFlags.mc from installed SDK inspection")
    parser.add_argument("--all", action="store_true", help="Run all checks")
    return parser.parse_args()


def generate_api_flags():
    """Generate source/ApiFlags.mc with compile-time constants based on installed SDK APIs.

    Strategy: find the latest installed SDK and search its files for the string
    'takeScreenshot'. If found, write ApiFlags.mc with SUPPORTS_SCREENSHOT = true,
    otherwise false. This file allows conditional compilation in Monkey C.
    """
    sdk_versions = get_installed_sdk_versions()
    if not sdk_versions:
        print("Connect IQ SDK が見つからないため ApiFlags.mc は更新しません。")
        return

    supports = False
    latest = sdk_versions[-1]
    sdk_path = latest['path']
    for root, dirs, files in os.walk(sdk_path):
        for fname in files:
            try:
                fpath = os.path.join(root, fname)
                with open(fpath, 'r', encoding='utf-8', errors='ignore') as f:
                    text = f.read()
                    if 'takeScreenshot' in text:
                        supports = True
                        break
            except Exception:
                continue
        if supports:
            break

    out_path = ROOT / 'source' / 'ApiFlags.mc'
    content = ('// Auto-generated by tools/debug_project.py\n'
               "// Do not edit by hand.\n"
               f"const SUPPORTS_SCREENSHOT = {str(supports).lower()};\n")
    out_path.write_text(content, encoding='utf-8')
    print(f"Wrote {out_path} (SUPPORTS_SCREENSHOT={supports})")


def main():
    args = parse_arguments()
    if not any((args.manifest, args.resources, args.source, args.readme, args.sdk, args.generate_api_flags, args.all)):
        args.all = True

    if args.generate_api_flags:
        generate_api_flags()
        print()

    if args.all or args.manifest:
        report_manifest()
        print()
    if args.all or args.resources:
        report_resources()
        print()
    if args.all or args.source:
        report_source()
        print()
    if args.all or args.readme:
        report_readme()
        print()
    if args.all or args.sdk:
        print("[Connect IQ SDK]")
        sdk_versions = get_installed_sdk_versions()
        if sdk_versions:
            for item in sdk_versions:
                print(f"- {item['name']} (version: {item['version']})")
        else:
            print("Connect IQ SDK が見つかりません。")


if __name__ == "__main__":
    main()

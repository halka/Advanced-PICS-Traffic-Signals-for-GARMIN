# Advanced PICS Traffic Signal Viewer for GARMIN GPSMAP H1i Plus

[日本語](#高度化pics-ビューア-for-garmin-gpsmap-h1i-plus) | [English](#english)
## 高度化PICS ビューア for GARMIN GPSMAP H1i Plus

Connect IQ アプリとして実装した、歩行者用信号機 BLE アドバタイズのリアルタイム受信・表示ツールです。スマートフォン不要・単体で高度化PICS信号機のBLEアドバタイズを受信し、交差点の信号状態（赤・青・青点滅）をリアルタイム表示します。

[ble-pics-viewer](https://github.com/yumu19/ble-pics-viewer)（Python版）の機能を GARMIN GPSMAP H1i Plus 上で動作する Connect IQ アプリとして移植したものです。

---

## ファイル構成

```
Advanced-PICS-Traffic-Signals-for-GARMIN/
├── manifest.xml                     ← アプリ定義・権限宣言（BLE + Positioning）
├── monkey.jungle                    ← プロジェクトビルド設定
├── source/
│   ├── PicsBleApp.mc                ← エントリポイント・ライフサイクル管理
│   ├── PicsBleDelegate.mc           ← BLEスキャン・パケット受信
│   ├── PicsData.mc                  ← データモデル・PICSパーサ・交差点DB
│   └── PicsMainView.mc              ← 画面描画（282×470px）
├── resources/
│   ├── data/
│   │   ├── intersections.json       ← 交差点データベース（自動生成）
│   │   └── jsonResources.xml        ← JSONリソース宣言
│   └── strings/
│       └── strings.xml              ← UIラベル文字列（日本語）
└── tools/
    └── csv_to_resource.py           ← CSV → JSON リソース変換スクリプト
```

---

## 技術仕様

### 動作デバイス
- **GARMIN GPSMAP H1i Plus**（メインターゲット）
- GARMIN GPSMAP H1（inReach なし版も対応）

### 必要な Connect IQ API Level
- **API Level 3.2.0 以上**
  - `Toybox.BluetoothLowEnergy`（BLEスキャン機能）API Level 3.1.0〜
  - `ScanResult.getManufacturerSpecificData(companyId)` API Level 3.2.0〜
  - `Toybox.Position`（GPS）API Level 1.0.0〜

### 必要なパーミッション

| パーミッション | 用途 |
|---|---|
| `BluetoothLowEnergy` | PICSのBLEアドバタイズ受信 |
| `Positioning` | GPS座標取得（交差点名の解決に使用） |

### BLEスキャン動作仕様
| 項目 | 内容 |
|---|---|
| 動作モード | セントラル（スキャン専用） |
| フィルタ条件 | メーカーID = `0x01CE`（高度化PICS固有） |
| ペアリング | 不要（アドバタイズ受信のみ） |
| GATT接続 | 行わない |
| API | `getManufacturerSpecificData(companyId)` で `ByteArray` を直接取得（SDK 8.x） |

### PICSパケット解析
BLEアドバタイズのメーカー固有データ（company ID `0x01CE`）の後続バイト列を解析:

| バイト | 内容 |
|---|---|
| [0..1] | ヘッダー（バージョン・フラグ） |
| [2] | メッセージタイプ（0/1/2） |
| [3] | メッセージID |
| [4..5] | 予約 |
| [6..9] | 交差点ID（4バイト hex） |
| [10+i] | 信号状態（タイプ2のみ）上位4bit=残り時間, 下位4bit=状態 |

### 画面レイアウト（282×470px）
```
┌─────────────────────────────┐  ← 上部アクセントライン (シアン)
│     高度化PICS モニタ         │  ← ヘッダー
│  北５条通り札幌駅前交差点      │    交差点名（GPS解決済み）or 16進ID
│       ● スキャン中           │    スキャン状態
├─────────────────────────────┤
│     東西          南北       │
│                              │
│    [● RED]      [● GRN]     │  ← 信号ランプ（Ø88px）
│                              │
│      赤            青        │  ← 状態テキスト
│    残り 5s       残り 3s     │  ← 残り秒数
│  RSSI:-65dBm  RSSI:-65dBm   │
├─────────────────────────────┤
│ デバイス: 35.1234N 139.1234E │  ← GPS情報エリア
│ 交差点:   35.1234N 139.1234E │    デバイス座標・交差点座標
│ 距離: 123m  方位: 45°(NE)   │    距離・方位
├─────────────────────────────┤
│  最終受信: 14:23:05           │  ← フッター
│  受信数: 1234 pkt             │
│  BACK で終了                  │
└─────────────────────────────┘  ← 下部アクセントライン (シアン)
```

---

## ビルド方法

### 前提条件
1. [Garmin Connect IQ SDK](https://developer.garmin.com/connect-iq/sdk/) をインストール
2. Visual Studio Code + [Monkey C 拡張機能](https://marketplace.visualstudio.com/items?itemName=garmin.monkey-c) を導入

### 開発者キーの生成
```bash
openssl genrsa -out developer_key.pem 4096
openssl pkcs8 -topk8 -inform PEM -outform DER -in developer_key.pem -out developer_key.der -nocrypt
```

### 交差点データベースの生成
```bash
# デフォルト: ~/Downloads/250501-zenkoku-kousaten.csv を読み込む
python3 tools/csv_to_resource.py

# パスを明示する場合:
python3 tools/csv_to_resource.py /path/to/input.csv resources/data/intersections.json
```

### ビルド手順
```bash
monkeyc -d gpsmaph1 -f monkey.jungle -o bin/pics-viewer.prg -y developer_key.der
```

### 実機転送（USBマスストレージ）
**USBマスストレージモードにすること**
```bash
cp bin/pics-viewer.prg /GARMIN/APPS/
```

---

## 注意事項・制約

### Connect IQ BLE の制約
- **GATTクライアントのみ**：アドバタイズの送信・GATTサーバーは不可
- **スキャンはフォアグラウンド動作時のみ安定**：バックグラウンドではOSが間引く場合あり
- **ScanResult のフィルタリングはアプリ側で実装**（Connect IQ はUUIDフィルタ非対応）
- **SDK 8.x 対応**：`ScanResult.getManufacturerSpecificData()` はcompany IDを引数で指定し `ByteArray` を直接返す（旧APIは `Dictionary` を返していたが廃止）

### 交差点名称について
PICSのType0パケットに含まれる交差点名称はShift-JISエンコードのため、Connect IQでは直接デコードできません。代わりに、BLEのType1パケット（緯度経度）とバンドルされた全国交差点DBを使ってGPS座標マッチングで名称を解決します。

### 文字列リソース
画面に表示するすべてのUIラベルは `resources/strings/strings.xml` で管理しています。ロケール別のディレクトリ（例：`resources-eng/strings/strings.xml`）を作成することで多言語対応が可能です。

### シミュレーターについて
Connect IQ SDK 8.3.0 のシミュレーターは macOS 26 (Tahoe) 以降で `ant_main` スレッドがクラッシュする既知の問題があります。テストは実機（GPSMAP H1）で行ってください。Garmin が対応 SDK をリリース次第、更新予定です。

### 法令遵守
本アプリが受信するPICSのBLEアドバタイズは公共インフラから不特定多数に向けて送信される公開電波であり、電波法・電気通信事業法・個人情報保護法の「通信の秘密」には該当しません。本アプリは受信専用であり、信号の送信・改変は行いません。

---

## 参考リンク
- [yumu19/ble-pics-viewer (Python版)](https://github.com/yumu19/ble-pics-viewer)
- [Garmin Connect IQ API Docs - BluetoothLowEnergy](https://developer.garmin.com/connect-iq/api-docs/Toybox/BluetoothLowEnergy.html)
- [高度化PICS整備交差点一覧 (e-Gov)](https://data.e-gov.go.jp/data/dataset/npa_20221124_0054/resource/6f7e83e1-be28-4030-961f-3b489c9f6ad8)
- [信号の時刻表をつくる 2025 (デイリーポータルZ)](https://dailyportalz.jp/kiji/shingo-jikokuhyo2025)

---

## English

A Connect IQ application that receives and displays BLE advertisements from Japan's Advanced PICS (Pedestrian Information and Communication System) pedestrian traffic signals in real-time — no smartphone required.

### Features

- Real-time reception of PICS BLE advertisements (company ID `0x01CE`)
- Displays signal state (Red / Green / Blinking Green / Uncontrolled) for East-West and North-South pedestrian channels
- Resolves intersection name from GPS coordinates using a pre-built national intersection database (596 intersections)
- Displays device GPS coordinates, nearest intersection coordinates, and calculated distance + bearing
- Works standalone on the GPSMAP H1i Plus without any companion app

### File Structure

```
Advanced-PICS-Traffic-Signals-for-GARMIN/
├── manifest.xml                     ← App definition, permissions (BLE + Positioning)
├── monkey.jungle                    ← Project build configuration
├── source/
│   ├── PicsBleApp.mc                ← App entry point & lifecycle
│   ├── PicsBleDelegate.mc           ← BLE scanning & packet reception
│   ├── PicsData.mc                  ← Data models, PICS parser, intersection DB
│   └── PicsMainView.mc              ← Screen rendering (282×470 px)
├── resources/
│   ├── data/
│   │   ├── intersections.json       ← Intersection database (auto-generated)
│   │   └── jsonResources.xml        ← JSON resource declaration
│   └── strings/
│       └── strings.xml              ← UI strings (Japanese; add translations here)
└── tools/
    └── csv_to_resource.py           ← CSV → JSON resource converter
```

### Technical Specifications

**Target Devices**
- GARMIN GPSMAP H1i Plus (primary)
- GARMIN GPSMAP H1 (inReach-free variant)

**Required Connect IQ API Level:** 3.2.0+
- `Toybox.BluetoothLowEnergy` (BLE scanning): API Level 3.1.0+
- `ScanResult.getManufacturerSpecificData(companyId)`: API Level 3.2.0+
- `Toybox.Position` (GPS): API Level 1.0.0+

**Required Permissions**

| Permission | Purpose |
|---|---|
| `BluetoothLowEnergy` | Receive PICS BLE advertisements |
| `Positioning` | Read device GPS coordinates for intersection lookup |

**BLE Scanning**

| Item | Details |
|---|---|
| Mode | Central (scan only) |
| Filter | Manufacturer ID = `0x01CE` (PICS-specific) |
| Pairing | Not required (advertisement reception only) |
| GATT connection | Not established |
| API | `ScanResult.getManufacturerSpecificData(companyId)` returns `ByteArray` directly |

**PICS Packet Format** (bytes after company ID `0x01CE`):

| Bytes | Content |
|---|---|
| [0..1] | Header (version / flags) |
| [2] | Message type (0 = identifier, 1 = location, 2 = signal state) |
| [3] | Message ID |
| [4..5] | Reserved |
| [6..9] | Intersection ID (4-byte hex) |
| [10+i] | Signal state (Type 2 only): upper 4 bits = remaining time, lower 4 bits = state |

**Screen Layout (282×470 px)**

```
┌─────────────────────────────┐  ← Cyan accent line
│     高度化PICS モニタ         │  ← Header: App title
│  北５条通り札幌駅前交差点      │         Intersection name (or hex ID)
│       ● スキャン中           │         Scan status
├─────────────────────────────┤
│     東西          南北       │
│                              │
│    [● RED]      [● GRN]     │  ← Signal lamps (Ø88 px)
│                              │
│      赤            青        │  ← State label
│    残り 5s       残り 3s     │  ← Remaining seconds
│  RSSI:-65dBm  RSSI:-65dBm   │
├─────────────────────────────┤
│ デバイス: 35.1234N 139.1234E │  ← GPS info: device coordinates
│ 交差点:   35.1234N 139.1234E │             intersection coordinates
│ 距離: 123m  方位: 45°(NE)   │             distance & bearing
├─────────────────────────────┤
│   最終受信: 14:23:05          │  ← Footer
│   受信数: 1234 pkt            │
│   BACK で終了                 │
└─────────────────────────────┘  ← Cyan accent line
```

### Build Instructions

#### 1. Install Connect IQ SDK
Download from https://developer.garmin.com/connect-iq/sdk/

#### 2. Generate a Developer Key
```bash
openssl genrsa -out developer_key.pem 4096
openssl pkcs8 -topk8 -inform PEM -outform DER \
  -in developer_key.pem -out developer_key.der -nocrypt
```

#### 3. Generate Intersection Database Resource
```bash
# Default: reads ~/Downloads/250501-zenkoku-kousaten.csv
python3 tools/csv_to_resource.py

# Or specify paths explicitly:
python3 tools/csv_to_resource.py /path/to/input.csv resources/data/intersections.json
```

#### 4. Build
```bash
monkeyc -d gpsmaph1 -f monkey.jungle -o bin/pics-viewer.prg -y developer_key.der
```

#### 5. Deploy to Device (USB Mass Storage)
**Ensure USB Mass Storage Mode**
```bash
cp bin/pics-viewer.prg /GARMIN/APPS/
```

### Notes & Limitations

- **BLE**: Central (scan-only) mode. No GATT connection is established.
- **Foreground only**: BLE scanning may be throttled by the OS in background mode.
- **Intersection database**: Built from the [e-Gov national intersection list](https://data.e-gov.go.jp/data/dataset/npa_20221124_0054/resource/6f7e83e1-be28-4030-961f-3b489c9f6ad8) (596 intersections). Re-run `csv_to_resource.py` to update.
- **Shift-JIS**: PICS Type 0 packets carry the intersection name in Shift-JIS encoding, which Connect IQ does not support. Names are resolved via GPS coordinate matching against the bundled database instead.
- **String resources**: All UI labels are defined in `resources/strings/strings.xml`. To add a language translation, create a locale-specific strings file (e.g. `resources-eng/strings/strings.xml`).
- **Connect IQ SDK 8.x**: `ScanResult.getManufacturerSpecificData()` now requires the company ID as an argument and returns a `ByteArray` directly (no longer returns a `Dictionary`). This app targets SDK 8.x behaviour.
- **Simulator**: The Connect IQ SDK 8.3.0 simulator may crash on macOS 26+ (Tahoe) in the `ant_main` thread when loading apps that use BLE. Deploy to actual hardware for testing until Garmin releases a compatible SDK update.
- **Legal compliance**: PICS BLE advertisements are public-infrastructure transmissions broadcast to all. This app is receive-only and does not transmit or modify any signal. Reception is compliant with Japanese radio and telecommunications law.

### References
- [yumu19/ble-pics-viewer (Python version)](https://github.com/yumu19/ble-pics-viewer)
- [Garmin Connect IQ API — BluetoothLowEnergy](https://developer.garmin.com/connect-iq/api-docs/Toybox/BluetoothLowEnergy.html)
- [Advanced PICS intersection list (e-Gov)](https://data.e-gov.go.jp/data/dataset/npa_20221124_0054/resource/6f7e83e1-be28-4030-961f-3b489c9f6ad8)
- [信号の時刻表をつくる 2025 (デイリーポータルZ)](https://dailyportalz.jp/kiji/shingo-jikokuhyo2025)

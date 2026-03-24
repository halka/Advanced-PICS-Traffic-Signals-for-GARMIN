# 高度化PICS ビューア for GARMIN GPSMAP H1i Plus

Connect IQ アプリとして実装した、歩行者用信号機 BLE アドバタイズのリアルタイム受信・表示ツールです。

---

## 概要

[ble-pics-viewer](https://github.com/yumu19/ble-pics-viewer)（Python版）の機能を GARMIN GPSMAP H1i Plus 上で動作する Connect IQ アプリとして移植したものです。

スマートフォン不要・単体で高度化PICS信号機のBLEアドバタイズを受信し、交差点の信号状態（赤・青・青点滅）をリアルタイム表示します。

---

## ファイル構成

```
pics-viewer-ciq/
├── manifest.xml                     ← アプリ定義・権限宣言
├── source/
│   ├── PicsBleApp.mc                ← エントリポイント・ライフサイクル管理
│   ├── PicsBleDelegate.mc           ← BLEスキャン・パケット受信
│   ├── PicsData.mc                  ← データモデル・PICSパーサ
│   └── PicsMainView.mc              ← 画面描画（282×470px）
└── resources/
    └── strings/
        └── strings.xml              ← 文字列リソース
```

---

## 技術仕様

### 動作デバイス
- **GARMIN GPSMAP H1i Plus**（メインターゲット）
- GARMIN GPSMAP H1（inReach なし版も対応）

### 必要な Connect IQ API Level
- **API Level 3.2.0 以上**
  - `Toybox.BluetoothLowEnergy`（BLEスキャン機能）API Level 3.1.0〜
  - `ScanResult.getManufacturerSpecificData()` API Level 3.2.0〜

### BLEスキャン動作仕様
| 項目 | 内容 |
|---|---|
| 動作モード | セントラル（スキャン専用） |
| フィルタ条件 | メーカーID = `0x01CE`（高度化PICS固有） |
| ペアリング | 不要（アドバタイズ受信のみ） |
| GATT接続 | 行わない |

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
│  高度化PICS モニタ            │  ← ヘッダー
│  交差点: DEADBEEF            │
│  ● スキャン中                │
├─────────────────────────────┤
│     東西         南北        │
│                              │
│    [●RED]       [●GRN]      │  ← 信号ランプ（Ø88px）
│                              │
│     赤            青         │  ← 状態テキスト
│   残り 5s        残り 3s     │  ← 残り秒数
│  RSSI:-65dBm   RSSI:-65dBm   │
├─────────────────────────────┤
│  最終受信: 14:23:05           │  ← フッター
│  受信数: 1234 pkt             │
│  BACK で終了                  │
└─────────────────────────────┘  ← 下部アクセントライン (シアン)
```

---
## ビルドの前に
### 1. Connect IQ SDK をインストール
####    https://developer.garmin.com/connect-iq/sdk/

### 2. 開発者キー生成
openssl genrsa -out developer_key.pem 4096
openssl pkcs8 -topk8 -inform PEM -outform DER \
  -in developer_key.pem -out developer_key.der -nocrypt

### 3. ビルド
monkeyc -d gpsmap_h1 -f monkey.jungle \
  -o bin/pics-viewer.prg -y developer_key.der

# 4. 実機転送（USBマスストレージ）
cp bin/pics-viewer.prg /GARMIN/APPS/

## ビルド方法

### 前提条件
1. [Garmin Connect IQ SDK](https://developer.garmin.com/connect-iq/sdk/) をインストール
2. Visual Studio Code + [Monkey C 拡張機能](https://marketplace.visualstudio.com/items?itemName=garmin.monkey-c) を導入

### ビルド手順

```bash
# SDK のシミュレータで動作確認
monkeyc -d gpsmap_h1 -f monkey.jungle -o bin/pics-viewer.prg -y developer_key.der

# 実機に転送（USB接続後）
monkeyc -d gpsmap_h1 -f monkey.jungle -o bin/pics-viewer.prg -y developer_key.der
# .prg ファイルを /GARMIN/APPS/ にコピー
```

### monkey.jungle（プロジェクト定義ファイル）
```
project.manifest = manifest.xml
base.sourcePath = source
base.resourcePath = resources
```

### 開発者キーの生成
```bash
openssl genrsa -out developer_key.pem 4096
openssl pkcs8 -topk8 -inform PEM -outform DER -in developer_key.pem -out developer_key.der -nocrypt
```

---

## 注意事項・制約

### Connect IQ BLE の制約
- **GATTクライアントのみ**：アドバタイズの送信・GATTサーバーは不可
- **スキャンはフォアグラウンド動作時のみ安定**：バックグラウンドではOSが間引く場合あり
- **ScanResult のフィルタリングはアプリ側で実装**（Connect IQ はUUIDフィルタ非対応）

### 位置情報（Type1）について
PICSのType1パケット（緯度経度）は受信・解析しますが、現バージョンでは画面表示の実装は省略しています。`_delegate.lastLocFrame` に格納されているため、Map API との連携で地図上への表示が可能です。

### 法令遵守
本アプリが受信するPICSのBLEアドバタイズは公共インフラから不特定多数に向けて送信される公開電波であり、電波法・電気通信事業法・個人情報保護法の「通信の秘密」には該当しません。本アプリは受信専用であり、信号の送信・改変は行いません。

---

## 参考リンク
- [yumu19/ble-pics-viewer (Python版)](https://github.com/yumu19/ble-pics-viewer)
- [Garmin Connect IQ API Docs - BluetoothLowEnergy](https://developer.garmin.com/connect-iq/api-docs/Toybox/BluetoothLowEnergy.html)
- [高度化PICS整備交差点一覧 (e-Gov)](https://data.e-gov.go.jp/data/dataset/npa_20221124_0054/resource/6f7e83e1-be28-4030-961f-3b489c9f6ad8)
- [信号の時刻表をつくる 2025 (デイリーポータルZ)](https://dailyportalz.jp/kiji/shingo-jikokuhyo2025)

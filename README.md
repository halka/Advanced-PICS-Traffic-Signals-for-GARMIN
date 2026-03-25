# Advanced PICS Traffic Signal Viewer for GARMIN GPSMAP H1i Plus
## 高度化PICS ビューア for GARMIN GPSMAP H1i Plus

A Connect IQ application that receives and displays BLE advertisements from Japan's Advanced PICS (Pedestrian Information and Communication System) pedestrian traffic signals in real-time — no smartphone required.

### Features

- Real-time reception of PICS BLE advertisements (company ID `0x01CE`)
- Displays signal state (Red / Green / Blinking Green / Uncontrolled) for East-West and North-South pedestrian channels
- Resolves intersection name from GPS coordinates using a pre-built national intersection database (596 intersections)
- Displays device GPS coordinates, nearest intersection coordinates, and calculated distance + bearing
- Works standalone on the GPSMAP H1i Plus without any companion app
- Menu button: intersection list (nearest 30, sorted by distance) with full detail view (lat/lon, distance, bearing)
- Screenshot capture on device via menu
- SD Card logging: Record raw BLE payloads and packet data directly to the device's internal storage

### File Structure

```
Advanced-PICS-Traffic-Signals-for-GARMIN/
├── manifest.xml                     ← App definition, permissions (BLE + Positioning)
├── monkey.jungle                    ← Project build configuration
├── source/
│   ├── PicsBleApp.mc                ← App entry point, lifecycle, menu handling
│   ├── PicsBleDelegate.mc           ← BLE scanning & packet reception
│   ├── PicsData.mc                  ← Data models, PICS parser, intersection DB
│   ├── PicsMainView.mc              ← Screen rendering (282×470 px)
│   └── PicsIntersectionListView.mc  ← Intersection list & detail views
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
│     高度化PICS モニタ          │  ← Header: App title
│  北５条通り札幌駅前交差点         │         Intersection name (or hex ID)
│       ● スキャン中             │         Scan status
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

### SD Card Logging (Debug)

The app automatically logs every received PICS packet (including millisecond precision timestamps and raw HEX payloads). However, Garmin OS discards these logs unless you manually create a text file to capture them:
1. Connect your Garmin device via USB.
2. In the `GARMIN/APPS/LOGS/` directory, create an empty text file named **exactly** the same as your app executable but with a `.txt` extension (e.g. `pics-viewer.txt`).
3. Launch the app. All BLE traffic logs will be continuously appended to that text file.

### Notes & Limitations

- **BLE**: Central (scan-only) mode. No GATT connection is established.
- **Widget type**: The app runs as a Connect IQ widget, accessible via the PAGE button on the device. BLE scanning runs continuously while the widget is active.
- **Widget vs watch-app**: As a `widget`, the app is launched directly from the widget glance view (PAGE button) rather than navigating to Main Menu → Connect IQ → Apps.
- **Intersection database**: Built from the [e-Gov national intersection list](https://data.e-gov.go.jp/data/dataset/npa_20221124_0054/resource/6f7e83e1-be28-4030-961f-3b489c9f6ad8) (596 intersections). Re-run `csv_to_resource.py` to update.
- **Identification of traffic signs**: Need to dump network telemetry of NIPPON SIGNAL's App. [ref.](https://qiita.com/kitazaki/items/ef2d8710d1656705f307)
- **String resources**: All UI labels are defined in `resources/strings/strings.xml`. To add a language translation, create a locale-specific strings file (e.g. `resources-eng/strings/strings.xml`).
- **Connect IQ SDK 8.x**: `ScanResult.getManufacturerSpecificData()` now requires the company ID as an argument and returns a `ByteArray` directly (no longer returns a `Dictionary`). This app targets SDK 8.x behaviour.
- **Simulator**: The Connect IQ SDK 8.3.0 simulator may crash on macOS 26+ (Tahoe) in the `ant_main` thread when loading apps that use BLE. Deploy to actual hardware for testing until Garmin releases a compatible SDK update.
- **Legal compliance**: PICS BLE advertisements are public-infrastructure transmissions broadcast to all. This app is receive-only and does not transmit or modify any signal. Reception is compliant with Japanese radio and telecommunications law.

### Acknowledgments
This project is deeply inspired by and based on the work of [yumu19/ble-pics-viewer](https://github.com/yumu19/ble-pics-viewer) (Python version). We express our sincere gratitude to the original author for making their packet analysis and implementation public, which made this Garmin port possible.

### References
- [yumu19/ble-pics-viewer (Python version)](https://github.com/yumu19/ble-pics-viewer)
- [Garmin Connect IQ API — BluetoothLowEnergy](https://developer.garmin.com/connect-iq/api-docs/Toybox/BluetoothLowEnergy.html)
- [Advanced PICS intersection list (e-Gov)](https://data.e-gov.go.jp/data/dataset/npa_20221124_0054/resource/6f7e83e1-be28-4030-961f-3b489c9f6ad8)
- [信号の時刻表をつくる 2025 (デイリーポータルZ)](https://dailyportalz.jp/kiji/shingo-jikokuhyo2025)
- [信GO!アプリの解析 (私の自由研究 2025) #Android - Qiita](https://qiita.com/kitazaki/items/ef2d8710d1656705f307)

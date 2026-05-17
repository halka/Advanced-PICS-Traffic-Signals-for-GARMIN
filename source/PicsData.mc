// =============================================================
// PicsData.mc  ―  高度化PICS データモデル
// GPSMAP H1i Plus / Connect IQ SDK 9.1.0
// =============================================================

import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

// ---- 信号状態定数 ----
const SIGNAL_NO_SIGNAL  = 0;    // 信号なし（無線区間外）
const SIGNAL_RED        = 1;    // 赤
const SIGNAL_BLINK_GREEN = 2;   // 青点滅
const SIGNAL_GREEN      = 3;    // 青
const SIGNAL_NONE       = 4;    // 制御外

// ---- メーカーID (0x01CE) ----
const PICS_MANUFACTURER_ID = 0x01CE;

// ---- 歩行者信号チャンネル数（PICS仕様: 最大6系統、将来拡張・複数対応のため16に拡張） ----
const PICS_SIGNAL_COUNT = 16;

// ---- メッセージタイプ ----
const PICS_MSG_TYPE_IDENTIFIER = 0;  // 交差点識別子
const PICS_MSG_TYPE_LOCATION   = 1;  // 位置情報
const PICS_MSG_TYPE_SIGNAL     = 2;  // 信号状態

//! @brief 1つの歩行者信号チャンネルの状態
class PicsSignal {
    //! 信号状態 (SIGNAL_* 定数)
    var state   as Lang.Number = SIGNAL_NO_SIGNAL;
    //! 残り表示値（PICS の s 値）。不明な場合は -1
    var remaining as Lang.Number = -1;

    function initialize(state_ as Lang.Number, remaining_ as Lang.Number) {
        state = state_;
        remaining = remaining_;
    }

    //! 表示用ラベル（Rez.Strings の ResourceId）を返す
    function stateLabel() as Lang.ResourceId {
        switch (state) {
            case SIGNAL_RED:         return Rez.Strings.Red;
            case SIGNAL_BLINK_GREEN: return Rez.Strings.BlinkGreen;
            case SIGNAL_GREEN:       return Rez.Strings.Green;
            case SIGNAL_NONE:        return Rez.Strings.ControlOut;
            default:                 return Rez.Strings.NoSignal;
        }
    }
}

//! @brief PICS アドバタイズ1パケット分の解析結果
class PicsFrame {
    var msgType        as Lang.Number = -1;
    var msgId          as Lang.Number = -1;
    var intersectionId as Lang.String = "--------";
    var transmitterId  as Lang.String = "--------";

    // Type 1 (位置情報)
    var latitude       as Lang.Float = 0.0f;
    var longitude      as Lang.Float = 0.0f;

    // Type 1 (位置情報) から引いた交差点名称（未解決の場合は空文字）
    var intersectionName as Lang.String = "";

    // Type 2 (信号状態)  ―  PICS_SIGNAL_COUNT 個
    var signals        as Lang.Array = new PicsSignal[PICS_SIGNAL_COUNT];

    // メタ
    var rssi           as Lang.Number = 0;
    var timestamp      as Lang.Long = 0l;   // millis since epoch

    function initialize() {
        for (var i = 0; i < PICS_SIGNAL_COUNT; i++) {
            signals[i] = new PicsSignal(SIGNAL_NO_SIGNAL, -1);
        }
    }
}

//! @brief BLE ByteArray から PicsFrame を生成するパーサ
//!
//! @note  Bleak / Connect IQ どちらも companyId 以降のペイロードを返す。
//!        PICS ペイロード構造（companyId 除く）:
//!          [0]    : バージョン / 予約
//!          [1]    : フラグ
//!          [2]    : メッセージタイプ (0/1/2)
//!          [3]    : メッセージ ID
//!          [4..5] : 予約
//!          [6..9] : 交差点ID (4バイト big-endian hex)
//!          [10..] : タイプ依存ペイロード
class PicsParser {

    static function parse(data as Lang.ByteArray, rssi as Lang.Number) as PicsFrame or Null {
        if (data == null || data.size() < 4) {
            return null;
        }

        var frame = new PicsFrame();
        frame.rssi      = rssi;
        frame.timestamp = System.getTimer().toLong();
        frame.msgType   = data[2];
        frame.msgId     = data[3];

        // 交差点ID
        if (data.size() >= 10) {
            var idStr = "";
            for (var i = 6; i < 10; i++) {
                idStr += data[i].format("%02X");
            }
            frame.intersectionId = idStr;
            frame.transmitterId = idStr;
        }

        // タイプ別ペイロード解析
        switch (frame.msgType) {

            case PICS_MSG_TYPE_IDENTIFIER:
                // [10..23]: 交差点名称 (ASCII / Shift-JIS, null padded)
                // ※ Connect IQ は Shift-JIS 非対応のため ASCII 部のみ採用
                break;

            case PICS_MSG_TYPE_LOCATION:
                if (data.size() >= 18) {
                    // big-endian signed 32-bit  ÷ 1,000,000 → 度
                    var lat = ((data[10] << 24) | (data[11] << 16)
                             | (data[12] << 8)  |  data[13]);
                    var lon = ((data[14] << 24) | (data[15] << 16)
                             | (data[16] << 8)  |  data[17]);
                    frame.latitude  = (lat / 1000000.0f);
                    frame.longitude = (lon / 1000000.0f);
                }
                break;

            case PICS_MSG_TYPE_SIGNAL:
                for (var i = 0; i < PICS_SIGNAL_COUNT; i++) {
                    var idx = 10 + i;
                    if (idx >= data.size()) { break; }
                    var b = data[idx];
                    var rem   = (b >> 4) & 0x0F;
                    var state = b & 0x0F;
                    frame.signals[i] = new PicsSignal(
                        state,
                        (rem >= 8) ? -1 : (rem + 1)
                    );
                }
                break;

            default:
                // 未定義タイプ → フレームは返すが signals は未更新
                break;
        }

        return frame;
    }
}

//! @brief 全国交差点DBを保持し、GPS座標から最近傍の交差点名を返す
//!
//! resources/data/intersections.json を Rez.JsonData 経由で読み込む。
//! データ形式: [[lat_int, lon_int, "名称"], ...]  (lat/lon は度 × 1,000,000)
class PicsIntersectionDB {

    private var _entries as Lang.Array or Null = null;

    function initialize() {
        var json = WatchUi.loadResource(Rez.JsonData.intersections) as Lang.Array or Null;
        if (json != null) {
            _entries = json;
        }
    }

    //! GPS座標 (度) から最近傍の交差点名を返す。未解決時は空文字。
    function findNearest(lat as Lang.Float, lon as Lang.Float) as Lang.String {
        var entry = findNearestEntry(lat, lon);
        return (entry != null) ? (entry[2] as Lang.String) : "";
    }

    //! 全エントリを返す
    function getAllEntries() as Lang.Array or Null {
        return _entries;
    }

    //! GPS座標 (度) から最近傍エントリを返す。
    //! エントリが空の場合は null を返す。
    function findNearestEntry(lat as Lang.Float, lon as Lang.Float) as Lang.Array or Null {
        if (_entries == null || (_entries as Lang.Array).size() == 0) {
            return null;
        }
        var entries  = _entries as Lang.Array;
        var bestEntry = null;
        var bestDist = 9.9e9f;
        for (var i = 0; i < entries.size(); i++) {
            var e    = entries[i] as Lang.Array;
            var eLat = e[0].toFloat();
            var eLon = e[1].toFloat();
            var dLat = lat - eLat;
            var dLon = lon - eLon;
            var dist = dLat * dLat + dLon * dLon;
            if (dist < bestDist) {
                bestDist = dist;
                bestEntry = e;
            }
        }
        return bestEntry;
    }

    //! 上位 limit 件の近い交差点を取得する (O(N) 挿入ソート)
    //! 戻り値: [ { "entry": dict, "dist": float, "brg": float }, ... ]
    function getTopN(lat as Lang.Float, lon as Lang.Float, limit as Lang.Number) as Lang.Array {
        var top = [] as Lang.Array;
        if (_entries == null || (_entries as Lang.Array).size() == 0) {
            return top;
        }
        var entries = _entries as Lang.Array;
        for (var i = 0; i < entries.size(); i++) {
            var e = entries[i] as Lang.Array;
            var eLat = e[0].toFloat();
            var eLon = e[1].toFloat();

            var dLat = lat - eLat;
            var dLon = lon - eLon;
            var rank = dLat * dLat + dLon * dLon;
            
            var item = {
                "entry" => e,
                "rank"  => rank
            };

            var inserted = false;
            for (var j = 0; j < top.size(); j++) {
                if (rank < (top[j] as Lang.Dictionary)["rank"] as Lang.Float) {
                    var newTop = [] as Lang.Array;
                    for(var k=0; k<j; k++) { newTop.add(top[k]); }
                    newTop.add(item);
                    for(var k=j; k<top.size() && newTop.size() < limit; k++) { newTop.add(top[k]); }
                    top = newTop;
                    inserted = true;
                    break;
                }
            }
            if (!inserted && top.size() < limit) {
                top.add(item);
            }
        }

        var result = [] as Lang.Array;
        for (var i = 0; i < top.size(); i++) {
            var rankedItem = top[i] as Lang.Dictionary;
            var rankedEntry = rankedItem["entry"] as Lang.Array;
            var db = calcDistBrg(lat, lon,
                                 rankedEntry[0].toFloat(),
                                 rankedEntry[1].toFloat());
            result.add({
                "entry" => rankedEntry,
                "dist"  => db[0] as Lang.Float,
                "brg"   => db[1] as Lang.Float
            });
        }
        return result;
    }
}

//! 2点間の距離(m)と方位(度)を計算する [Haversine + atan2]
//! @return [dist_m as Float, bearing_deg as Float]
function calcDistBrg(lat1 as Lang.Float, lon1 as Lang.Float,
                     lat2 as Lang.Float, lon2 as Lang.Float) as Lang.Array {
    var R    = 6371000.0f;
    var toR  = Math.PI.toFloat() / 180.0f;
    var phi1 = lat1 * toR;
    var phi2 = lat2 * toR;
    var dPhi = (lat2 - lat1) * toR;
    var dLam = (lon2 - lon1) * toR;
    var sh   = Math.sin(dPhi / 2.0f);
    var sl   = Math.sin(dLam / 2.0f);
    var a    = sh * sh + Math.cos(phi1) * Math.cos(phi2) * sl * sl;
    if (a > 1.0f) { a = 1.0f; } else if (a < 0.0f) { a = 0.0f; }
    var dist = (R * 2.0f * Math.atan2(Math.sqrt(a), Math.sqrt(1.0f - a))).toFloat();
    var vy   = (Math.sin(dLam) * Math.cos(phi2)).toFloat();
    var vx   = (Math.cos(phi1) * Math.sin(phi2)
              - Math.sin(phi1) * Math.cos(phi2) * Math.cos(dLam)).toFloat();
    var brg  = Math.toDegrees(Math.atan2(vy, vx)).toFloat();
    brg += 360.0f;
    if (brg >= 360.0f) { brg -= 360.0f; }
    return [dist, brg] as Lang.Array;
}

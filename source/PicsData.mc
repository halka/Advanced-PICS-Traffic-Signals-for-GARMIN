// =============================================================
// PicsData.mc  ―  高度化PICS データモデル
// GPSMAP H1i Plus / Connect IQ 3.2.0+
// =============================================================

import Toybox.Lang;
import Toybox.Time;

// ---- 信号状態定数 ----
const SIGNAL_NO_SIGNAL  = 0;    // 信号なし（無線区間外）
const SIGNAL_RED        = 1;    // 赤
const SIGNAL_BLINK_GREEN = 2;   // 青点滅
const SIGNAL_GREEN      = 3;    // 青
const SIGNAL_NONE       = 4;    // 制御外

// ---- メーカーID (0x01CE) ----
const PICS_MANUFACTURER_ID = 0x01CE;

// ---- 歩行者信号チャンネル数（PICS仕様: 最大6系統） ----
const PICS_SIGNAL_COUNT = 6;

// ---- メッセージタイプ ----
const PICS_MSG_TYPE_IDENTIFIER = 0;  // 交差点識別子
const PICS_MSG_TYPE_LOCATION   = 1;  // 位置情報
const PICS_MSG_TYPE_SIGNAL     = 2;  // 信号状態

//! @brief 1つの歩行者信号チャンネルの状態
class PicsSignal {
    //! 信号状態 (SIGNAL_* 定数)
    var state   as Lang.Number = SIGNAL_NO_SIGNAL;
    //! 残り時間（秒）。不明な場合は -1
    var remaining as Lang.Number = -1;

    function initialize(state_ as Lang.Number, remaining_ as Lang.Number) {
        state = state_;
        remaining = remaining_;
    }

    //! 表示用ラベル文字列を返す
    function stateLabel() as Lang.String {
        switch (state) {
            case SIGNAL_RED:         return "赤";
            case SIGNAL_BLINK_GREEN: return "青点滅";
            case SIGNAL_GREEN:       return "青";
            case SIGNAL_NONE:        return "制御外";
            default:                 return "---";
        }
    }
}

//! @brief PICS アドバタイズ1パケット分の解析結果
class PicsFrame {
    var msgType        as Lang.Number = -1;
    var msgId          as Lang.Number = -1;
    var intersectionId as Lang.String = "--------";

    // Type 1 (位置情報)
    var latitude       as Lang.Float = 0.0f;
    var longitude      as Lang.Float = 0.0f;

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

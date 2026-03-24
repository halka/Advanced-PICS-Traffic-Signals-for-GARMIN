// =============================================================
// PicsBleDelegate.mc  ―  BLE スキャン + PICS パケット解析
// GPSMAP H1i Plus / Connect IQ 3.2.0+
// =============================================================

import Toybox.BluetoothLowEnergy;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;

//! @brief PICS アドバタイズを受信したときに呼ばれるコールバック型
typedef PicsCallback as Method(frame as PicsFrame, msgType as Lang.Number) as Void;

//! @brief BleDelegate の実装
//!
//!  * PICS_MANUFACTURER_ID (0x01CE) 以外のパケットは即棄却
//!  * Type 2 (信号状態) が届いたら lastSignalFrame を更新し、UI へ通知
//!  * Type 0 / Type 1 は受信ごとに交差点名・位置を更新（サイレント）
class PicsBleDelegate extends BluetoothLowEnergy.BleDelegate {

    //! 直近の信号状態フレーム（Type 2）
    var lastSignalFrame  as PicsFrame or Null = null;
    //! 直近の識別子フレーム（Type 0）
    var lastIdFrame      as PicsFrame or Null = null;
    //! 直近の位置フレーム（Type 1）
    var lastLocFrame     as PicsFrame or Null = null;

    //! 受信パケット総数（デバッグ用）
    var rxCount          as Lang.Long = 0l;

    //! GPS座標から解決された最新の交差点名称（未解決時は空文字）
    var currentIntersectionName as Lang.String = "";
    //! 最近傍交差点の緯度・経度（未解決時は 0.0）
    var currentIntersectionLat  as Lang.Float  = 0.0f;
    var currentIntersectionLon  as Lang.Float  = 0.0f;

    //! UI 更新コールバック
    private var _callback       as PicsCallback or Null = null;
    //! 交差点DB（GPS座標 → 名称ルックアップ）
    private var _intersectionDb as PicsIntersectionDB or Null = null;

    function initialize(callback as PicsCallback or Null) {
        BleDelegate.initialize();
        _callback = callback;
        _intersectionDb = new PicsIntersectionDB();
    }

    //! BLE スキャン結果コールバック（Connect IQ が自動的に呼ぶ）
    function onScanResults(scanResults as BluetoothLowEnergy.Iterator) as Void {
        var result = scanResults.next();
        while (result != null) {
            processScanResult(result as BluetoothLowEnergy.ScanResult);
            result = scanResults.next();
        }
    }

    //! 1件の ScanResult を処理する
    private function processScanResult(result as BluetoothLowEnergy.ScanResult) as Void {
        // メーカー固有データを取得（company ID を指定して ByteArray を直接取得）
        var payload = result.getManufacturerSpecificData(PICS_MANUFACTURER_ID);
        if (payload == null) { return; }

        rxCount++;

        var frame = PicsParser.parse(payload, result.getRssi());
        if (frame == null) { return; }

        // ---- ログ出力用タイムスタンプ生成 (yyyy-MM-dd HH:mm:ss.SSS) ----
        var info = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var ms   = System.getTimer() % 1000;
        var timeStr = info.year.format("%04d") + "-" +
                      info.month.format("%02d") + "-" +
                      info.day.format("%02d") + " " +
                      info.hour.format("%02d") + ":" +
                      info.min.format("%02d") + ":" +
                      info.sec.format("%02d") + "." +
                      ms.format("%03d");

        // ---- 受信したHEXダンプを生成 ----
        var hexStr = "";
        for (var i = 0; i < payload.size(); i++) {
            hexStr += (payload[i] & 0xFF).format("%02X");
        }

        var logPrefix = timeStr + " [PICS]" + " RSSI:" + frame.rssi + " Type:" + frame.msgType + " ID:" + frame.intersectionId + " HEX:" + hexStr;

        // タイプ別にキャッシュを更新 & ログ出力
        switch (frame.msgType) {
            case PICS_MSG_TYPE_IDENTIFIER:
                System.println(logPrefix);
                lastIdFrame = frame;
                break;
            case PICS_MSG_TYPE_LOCATION:
                System.println(logPrefix + " Lat:" + frame.latitude.format("%.6f") + " Lon:" + frame.longitude.format("%.6f"));
                lastLocFrame = frame;
                if (_intersectionDb != null) {
                    var entry = (_intersectionDb as PicsIntersectionDB)
                        .findNearestEntry(frame.latitude, frame.longitude);
                    if (entry != null) {
                        currentIntersectionLat  = entry[0] as Lang.Float;
                        currentIntersectionLon  = entry[1] as Lang.Float;
                        currentIntersectionName = entry[2] as Lang.String;
                    }
                }
                break;
            case PICS_MSG_TYPE_SIGNAL:
                var sigStr = "";
                for (var i = 0; i < 6; i++) {
                    var s = frame.signals[i] as PicsSignal;
                    sigStr += "[" + s.state + "," + s.remaining + "]";
                }
                System.println(logPrefix + " Sig:" + sigStr);
                
                lastSignalFrame = frame;
                // UI 通知は Type 2 のときのみ
                if (_callback != null) {
                    _callback.invoke(frame, PICS_MSG_TYPE_SIGNAL);
                }
                break;
        }
    }

    //! 交差点 ID を返す（Type 0/2 いずれかから取得）
    function getIntersectionId() as Lang.String {
        if (lastSignalFrame != null) {
            return lastSignalFrame.intersectionId;
        }
        if (lastIdFrame != null) {
            return lastIdFrame.intersectionId;
        }
        return "--------";
    }

    //! 位置情報が利用可能か
    function hasLocation() as Lang.Boolean {
        return lastLocFrame != null;
    }

    //! 使用する BLE 接続なし（スキャンのみ）なので接続コールバックは空実装
    function onConnectedStateChanged(
        device as BluetoothLowEnergy.Device,
        state  as BluetoothLowEnergy.ConnectionState
    ) as Void {
        // PICS はスキャン受信専用。接続は行わない。
    }
}

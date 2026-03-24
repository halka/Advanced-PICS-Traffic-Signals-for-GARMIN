// =============================================================
// PicsBleDelegate.mc  ―  BLE スキャン + PICS パケット解析
// GPSMAP H1i Plus / Connect IQ 3.2.0+
// =============================================================

import Toybox.BluetoothLowEnergy;
import Toybox.Lang;
import Toybox.System;

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
        // メーカー固有データを取得（Dictionary<Number, ByteArray>）
        var mfgData = result.getManufacturerSpecificData();
        if (mfgData == null) { return; }

        // PICS の company ID が含まれているか確認
        if (!mfgData.hasKey(PICS_MANUFACTURER_ID)) { return; }

        var payload = mfgData[PICS_MANUFACTURER_ID] as Lang.ByteArray;
        if (payload == null) { return; }

        rxCount++;

        var frame = PicsParser.parse(payload, result.getRssi());
        if (frame == null) { return; }

        // タイプ別にキャッシュを更新
        switch (frame.msgType) {
            case PICS_MSG_TYPE_IDENTIFIER:
                lastIdFrame = frame;
                break;
            case PICS_MSG_TYPE_LOCATION:
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

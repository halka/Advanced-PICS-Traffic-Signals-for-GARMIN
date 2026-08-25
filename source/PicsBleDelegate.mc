// =============================================================
// PicsBleDelegate.mc  ―  BLE スキャン + PICS パケット解析
// GPSMAP H1i Plus / Connect IQ SDK 9.1.0
// =============================================================

import Toybox.BluetoothLowEnergy;
import Toybox.Lang;
import Toybox.Position;
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
    //! Type1/識別子側から取得した発信器ID（BLEデバイス名）
    var currentTransmitterId as Lang.String = "";
    //! 最近傍交差点の緯度・経度（未解決時は 0.0）
    var currentIntersectionLat  as Lang.Float  = 0.0f;
    var currentIntersectionLon  as Lang.Float  = 0.0f;

    //! UI 更新コールバック
    private var _callback       as PicsCallback or Null = null;
    //! 交差点DB（GPS座標 → 名称ルックアップ）
    private var _intersectionDb as PicsIntersectionDB or Null = null;
    //! Type 1 から得た位置情報を交差点IDごとに保持する
    private var _locationByIntersection as Lang.Dictionary = {};
    //! 古いType 1を別時点の信号へ関連付けないための有効期間
    private const LOCATION_CACHE_TTL_MS = 15000;
    private const MAX_LOCATION_CACHE_ENTRIES = 16;

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
        var payload = result.getManufacturerSpecificData(PICS_MANUFACTURER_ID) as Toybox.Lang.ByteArray or Null;
        if (payload == null) { return; }

        rxCount++;

        var frame = PicsParser.parse(payload, result.getRssi());
        if (frame == null) { return; }
        var deviceName = result.getDeviceName();
        if (deviceName != null && (deviceName as Lang.String).length() > 0) {
            frame.transmitterId = deviceName as Lang.String;
        }

        // Gregorianの秒とSystem.getTimer()は同期していないため、疑似ミリ秒に連結しない。
        // Tickは同一秒内の受信順を追跡するための単調増加値として別フィールドに出す。
        var info = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var receiveTick = System.getTimer();
        var timeStr = info.year.format("%04d") + "-" +
                      info.month.format("%02d") + "-" +
                      info.day.format("%02d") + " " +
                      info.hour.format("%02d") + ":" +
                      info.min.format("%02d") + ":" +
                      info.sec.format("%02d");

        // ---- 受信したHEXダンプを生成 ----
        var hexStr = "";
        for (var i = 0; i < payload.size(); i++) {
            hexStr += (payload[i] & 0xFF).format("%02X");
        }

        var logPrefix = timeStr + " [PICS]" + " Tick:" + receiveTick +
                        " RSSI:" + frame.rssi + " Type:" + frame.msgType +
                        " ID:" + frame.intersectionId + " HEX:" + hexStr;

        // タイプ別にキャッシュを更新 & ログ出力
        switch (frame.msgType) {
            case PICS_MSG_TYPE_IDENTIFIER:
                System.println(logPrefix);
                lastIdFrame = frame;
                break;
            case PICS_MSG_TYPE_LOCATION:
                System.println(logPrefix + " Lat:" + frame.latitude.format("%.6f") + " Lon:" + frame.longitude.format("%.6f"));
                lastLocFrame = frame;
                cacheLocation(frame, receiveTick);
                break;
            case PICS_MSG_TYPE_SIGNAL:
                var sigStr = "";
                for (var i = 0; i < 6; i++) {
                    var s = frame.signals[i] as PicsSignal;
                    sigStr += "[" + s.state + "," + s.remaining + "]";
                }
                System.println(logPrefix + " Sig:" + sigStr);
                
                lastSignalFrame = frame;
                if (!applyCachedLocation(frame, receiveTick)) {
                    clearCurrentIntersection();
                    resolveNearestFromDeviceLocation();
                }
                // UI 通知は Type 2 のときのみ
                if (_callback != null) {
                    _callback.invoke(frame, PICS_MSG_TYPE_SIGNAL);
                }
                break;
        }
    }

    //! Type 1を同じ交差点IDのType 2だけに関連付ける
    private function cacheLocation(frame as PicsFrame, receiveTick as Lang.Number) as Void {
        if (_intersectionDb == null) { return; }

        var entry = (_intersectionDb as PicsIntersectionDB)
            .findNearestEntry(frame.latitude, frame.longitude);
        if (entry == null) { return; }

        evictOldestLocationIfFull(frame.intersectionId);
        _locationByIntersection[frame.intersectionId] = {
            "name" => entry[2] as Lang.String,
            "lat" => entry[0].toFloat(),
            "lon" => entry[1].toFloat(),
            "transmitter" => frame.transmitterId,
            "tick" => receiveTick
        };
    }

    private function evictOldestLocationIfFull(incomingId as Lang.String) as Void {
        if (_locationByIntersection.hasKey(incomingId) ||
            _locationByIntersection.size() < MAX_LOCATION_CACHE_ENTRIES) {
            return;
        }

        var keys = _locationByIntersection.keys();
        var oldestKey = null;
        var oldestTick = 0x7FFFFFFF;
        for (var i = 0; i < keys.size(); i++) {
            var key = keys[i];
            var value = _locationByIntersection[key] as Lang.Dictionary;
            var tick = value["tick"] as Lang.Number;
            if (tick < oldestTick) {
                oldestTick = tick;
                oldestKey = key;
            }
        }
        if (oldestKey != null) {
            _locationByIntersection.remove(oldestKey);
        }
    }

    private function applyCachedLocation(frame as PicsFrame,
                                         receiveTick as Lang.Number) as Lang.Boolean {
        if (!_locationByIntersection.hasKey(frame.intersectionId)) {
            return false;
        }

        var cached = _locationByIntersection[frame.intersectionId] as Lang.Dictionary;
        var cachedTick = cached["tick"] as Lang.Number;
        var age = receiveTick - cachedTick;
        if (age < 0 || age > LOCATION_CACHE_TTL_MS) {
            return false;
        }

        currentIntersectionName = cached["name"] as Lang.String;
        currentIntersectionLat = cached["lat"] as Lang.Float;
        currentIntersectionLon = cached["lon"] as Lang.Float;
        currentTransmitterId = cached["transmitter"] as Lang.String;
        if (currentTransmitterId.length() > 0 &&
            frame.transmitterId.equals(frame.intersectionId)) {
            frame.transmitterId = currentTransmitterId;
        }
        return true;
    }

    private function clearCurrentIntersection() as Void {
        currentIntersectionName = "";
        currentIntersectionLat = 0.0f;
        currentIntersectionLon = 0.0f;
        currentTransmitterId = "";
    }

    //! Type1 位置情報が来ないビーコンでも、現在地から最近傍交差点名を補完する
    private function resolveNearestFromDeviceLocation() as Void {
        if (_intersectionDb == null || currentIntersectionName.length() > 0) {
            return;
        }

        var posInfo = Position.getInfo();
        if (posInfo == null || posInfo.position == null) {
            return;
        }

        var coords = (posInfo.position as Position.Location).toDegrees();
        var entry = (_intersectionDb as PicsIntersectionDB)
            .findNearestEntry(coords[0].toFloat(), coords[1].toFloat());
        if (entry != null) {
            currentIntersectionLat  = entry[0].toFloat();
            currentIntersectionLon  = entry[1].toFloat();
            currentIntersectionName = entry[2] as Lang.String;
        }
    }

    //! 交差点 DB を返す
    function getIntersectionDb() as PicsIntersectionDB or Null {
        return _intersectionDb;
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

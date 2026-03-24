// =============================================================
// PicsBleApp.mc  ―  アプリケーション エントリポイント
// GPSMAP H1i Plus / Connect IQ 3.2.0+
// =============================================================

import Toybox.Application;
import Toybox.BluetoothLowEnergy;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;
import Toybox.System;

//! @brief アプリ本体
//!
//!  起動フロー:
//!    onStart()
//!      → BleDelegate 登録
//!      → SCAN_STATE_SCANNING 開始
//!      → 500ms タイマー開始（点滅アニメ用）
//!      → PicsMainView を push
class PicsBleApp extends Application.AppBase {

    private var _delegate as PicsBleDelegate or Null = null;
    private var _view     as PicsMainView    or Null = null;
    private var _timer    as Timer.Timer     or Null = null;

    function initialize() {
        AppBase.initialize();
    }

    //! アプリが初期化されたタイミング（最初のビューを返す）
    function getInitialView() {
        _view = new PicsMainView();
        return [_view, new PicsInputDelegate(_view)];
    }

    //! フォアグラウンド起動時
    function onStart(state as Lang.Dictionary or Null) as Void {
        startBleScanning();
        startBlinkTimer();
    }

    //! バックグラウンド / 終了時
    function onStop(state as Lang.Dictionary or Null) as Void {
        stopBlinkTimer();
        stopBleScanning();
    }

    // ----------------------------------------------------------
    //  BLE スキャン制御
    // ----------------------------------------------------------

    private function startBleScanning() as Void {
        // コールバック: Type2 受信時に View を更新
        _delegate = new PicsBleDelegate(method(:onPicsSignal));
        BluetoothLowEnergy.setDelegate(_delegate);
        BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_SCANNING);

        if (_view != null) {
            _view.setScanningState(true);
        }
    }

    private function stopBleScanning() as Void {
        BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
        if (_view != null) {
            _view.setScanningState(false);
        }
    }

    //! BleDelegate からの Type2 コールバック
    function onPicsSignal(frame as PicsFrame, msgType as Lang.Number) as Void {
        if (_view == null || _delegate == null) { return; }
        if (msgType == PICS_MSG_TYPE_SIGNAL) {
            _view.updateSignal(frame, _delegate.rxCount,
                _delegate.currentIntersectionName,
                _delegate.currentIntersectionLat,
                _delegate.currentIntersectionLon);
        }
    }

    // ----------------------------------------------------------
    //  500ms タイマー（青点滅アニメーション用）
    // ----------------------------------------------------------

    private function startBlinkTimer() as Void {
        _timer = new Timer.Timer();
        _timer.start(method(:onBlinkTick), 500, true);
    }

    private function stopBlinkTimer() as Void {
        if (_timer != null) {
            _timer.stop();
            _timer = null;
        }
    }

    function onBlinkTick() as Void {
        if (_view != null) {
            _view.toggleBlinkPhase();
        }
    }
}

// ----------------------------------------------------------
//  キー入力デリゲート
// ----------------------------------------------------------

//! @brief BACK キーでアプリ終了
class PicsInputDelegate extends WatchUi.BehaviorDelegate {
    private var _view as PicsMainView;

    function initialize(view as PicsMainView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onBack() as Lang.Boolean {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }

    //! ENTER キーでスキャン ON/OFF トグル（将来拡張用）
    function onSelect() as Lang.Boolean {
        return false;
    }
}

//! Connect IQ が呼び出すアプリケーションファクトリ
function getApp() as PicsBleApp {
    return Application.getApp() as PicsBleApp;
}

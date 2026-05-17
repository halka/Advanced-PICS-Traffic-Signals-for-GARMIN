// =============================================================
// PicsBleApp.mc  ―  アプリケーション エントリポイント
// GPSMAP H1i Plus / Connect IQ SDK 9.1.0
// =============================================================

import Toybox.Application;
import Toybox.BluetoothLowEnergy;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.Timer;
import Toybox.WatchUi;
import Toybox.System;

//! @brief アプリ本体
//!
//!  起動フロー:
//!    onStart()
//!      → BleDelegate 登録
//!      → SCAN_STATE_SCANNING 開始
//!      → 100ms タイマー開始（リアルタイム表示更新 + 点滅アニメ用）
//!      → PicsMainView を push
class PicsBleApp extends Application.AppBase {

    private var _delegate as PicsBleDelegate or Null = null;
    private var _view     as PicsMainView    or Null = null;
    private var _timer    as Timer.Timer     or Null = null;
    private var _timerTickCount as Lang.Number = 0;
    private var _bleScanningStarted as Lang.Boolean = false;

    // シミュレータ確認時だけ true にする。実機では BLE を起動する。
    private const EMULATOR_UI_ONLY = false;
    private const UI_POLL_INTERVAL_MS = 100;
    private const BLINK_INTERVAL_TICKS = 5; // 100ms × 5 = 500ms

    function initialize() {
        AppBase.initialize();
    }

    //! アプリが初期化されたタイミング（最初のビューを返す）
    function getInitialView() {
        _view = new PicsMainView();
        if (EMULATOR_UI_ONLY) {
            startEmulatorUiOnlyMode();
        }
        return [_view, new PicsInputDelegate(_view as PicsMainView)];
    }

    //! フォアグラウンド起動時
    function onStart(state as Lang.Dictionary or Null) as Void {
        if (EMULATOR_UI_ONLY) {
            startEmulatorUiOnlyMode();
        } else {
            startBleScanning();
        }
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
        _bleScanningStarted = true;

        if (_view != null) {
            _view.setScanningState(true);
        }
    }

    private function stopBleScanning() as Void {
        if (!_bleScanningStarted) { return; }
        BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
        _bleScanningStarted = false;
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
    //  シミュレータ確認モード
    // ----------------------------------------------------------

    private function startEmulatorUiOnlyMode() as Void {
        if (_view == null) { return; }

        var frame = new PicsFrame();
        frame.msgType = PICS_MSG_TYPE_SIGNAL;
        frame.msgId = 1;
        frame.intersectionId = "SIM00001";
        frame.rssi = -62;
        frame.timestamp = System.getTimer().toLong();
        frame.signals[0] = new PicsSignal(SIGNAL_RED, 7);
        frame.signals[1] = new PicsSignal(SIGNAL_GREEN, 12);
        frame.signals[2] = new PicsSignal(SIGNAL_NO_SIGNAL, -1);
        frame.signals[3] = new PicsSignal(SIGNAL_RED, 3);
        frame.signals[4] = new PicsSignal(SIGNAL_BLINK_GREEN, 5);
        frame.signals[5] = new PicsSignal(SIGNAL_NONE, -1);

        _view.setScanningState(false);
        _view.updateSignal(frame, 1l, "エミュレータ確認", 35.6812f, 139.7671f);
    }

    // ----------------------------------------------------------
    //  100ms タイマー（リアルタイム表示更新 + 青点滅アニメーション用）
    // ----------------------------------------------------------

    private function startBlinkTimer() as Void {
        _timer = new Timer.Timer();
        _timerTickCount = 0;
        _timer.start(method(:onUiPollTick), UI_POLL_INTERVAL_MS, true);
    }

    private function stopBlinkTimer() as Void {
        if (_timer != null) {
            _timer.stop();
            _timer = null;
        }
    }

    function onUiPollTick() as Void {
        if (_view == null) { return; }

        _timerTickCount++;
        if (_timerTickCount >= BLINK_INTERVAL_TICKS) {
            _timerTickCount = 0;
            _view.toggleBlinkPhase();
        } else {
            _view.refreshRealtime();
        }
    }

    // ----------------------------------------------------------
    //  メインメニュー（MENUボタン）は廃止
    // ----------------------------------------------------------
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

    function onNextPage() as Lang.Boolean {
        _view.scrollDown();
        return true;
    }

    function onPreviousPage() as Lang.Boolean {
        _view.scrollUp();
        return true;
    }

    //! MENUキー → 何もしない
    function onMenu() as Lang.Boolean {
        return true;
    }

    //! ENTER キーでスキャン ON/OFF トグル（将来拡張用）
    function onSelect() as Lang.Boolean {
        return false;
    }
}

// 不要なメニューデリゲートを削除

//! Connect IQ が呼び出すアプリケーションファクトリ
function getApp() as PicsBleApp {
    return Application.getApp() as PicsBleApp;
}

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
    private var _emulatorModeActive as Lang.Boolean = false;
    private var _emulatorFrame as PicsFrame or Null = null;
    private var _emulatorTickCounter as Lang.Number = 0;

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
        if (_delegate != null) {
            _view.setDb(_delegate.getIntersectionDb());
            _view.setScanningState(_bleScanningStarted);
        }
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
            _view.setDb(_delegate.getIntersectionDb());
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

        _emulatorModeActive = true;
        _emulatorTickCounter = 0;
        _view.setEmulatorMode(true);

        _emulatorFrame = new PicsFrame();
        var frame = _emulatorFrame as PicsFrame;
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

        var dummyDb = new PicsIntersectionDB();
        _view.setDb(dummyDb);
        _view.setScanningState(false);
        _view.updateSignal(frame, 1l, "北５条通り札幌駅前交差点", 43.066768f, 141.350582f);
    }

    function isEmulatorModeActive() as Lang.Boolean {
        return _emulatorModeActive;
    }

    function toggleEmulatorMode() as Void {
        if (!_emulatorModeActive) {
            stopBleScanning();
            startEmulatorUiOnlyMode();
        } else {
            _emulatorModeActive = false;
            _emulatorFrame = null;
            _emulatorTickCounter = 0;
            if (_view != null) {
                _view.setEmulatorMode(false);
                var db = (_delegate != null) ? _delegate.getIntersectionDb() : new PicsIntersectionDB();
                _view.setDb(db);
                _view.setScanningState(true);
            }
            startBleScanning();
        }
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

        if (_emulatorModeActive && _emulatorFrame != null) {
            _emulatorTickCounter++;
            if (_emulatorTickCounter >= 10) { // 100ms * 10 = 1秒
                _emulatorTickCounter = 0;
                var frame = _emulatorFrame as PicsFrame;
                for (var i = 0; i < 6; i++) {
                    var s = frame.signals[i] as PicsSignal;
                    if (s.remaining > 0) {
                        s.remaining--;
                    } else if (s.remaining == 0) {
                        // ダミー信号の状態変化をアニメーション
                        if (s.state == SIGNAL_RED) {
                            s.state = SIGNAL_GREEN;
                            s.remaining = 15;
                        } else if (s.state == SIGNAL_GREEN) {
                            s.state = SIGNAL_BLINK_GREEN;
                            s.remaining = 5;
                        } else if (s.state == SIGNAL_BLINK_GREEN) {
                            s.state = SIGNAL_RED;
                            s.remaining = 10;
                        }
                    }
                }
                _view.updateSignal(frame, 1l, "北５条通り札幌駅前交差点", 43.066768f, 141.350582f);
            }
        }
    }

    // ----------------------------------------------------------
    //  メインメニュー（MENUボタン）は廃止
    // ----------------------------------------------------------
}

// ----------------------------------------------------------
//  キー入力デリゲート
// ----------------------------------------------------------

//! @brief BACK キーでアプリ終了、またはシミュレータモードから通常モードへ復帰
class PicsInputDelegate extends WatchUi.BehaviorDelegate {
    private var _view as PicsMainView;

    function initialize(view as PicsMainView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onBack() as Lang.Boolean {
        var app = Application.getApp() as PicsBleApp;
        if (app.isEmulatorModeActive()) {
            app.toggleEmulatorMode();
            return true;
        }
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

    function onKey(keyEvent as WatchUi.KeyEvent) as Lang.Boolean {
        var key = keyEvent.getKey();
        if (key == WatchUi.KEY_MENU) {
            var app = Application.getApp() as PicsBleApp;
            app.toggleEmulatorMode();
            return true;
        } else if (key == WatchUi.KEY_DOWN) {
            _view.scrollDown();
            return true;
        } else if (key == WatchUi.KEY_UP) {
            _view.scrollUp();
            return true;
        }
        return false;
    }

    function onSwipe(swipeEvent as WatchUi.SwipeEvent) as Lang.Boolean {
        var dir = swipeEvent.getDirection();
        if (dir == WatchUi.SWIPE_UP) {
            _view.scrollDown();
            return true;
        } else if (dir == WatchUi.SWIPE_DOWN) {
            _view.scrollUp();
            return true;
        }
        return false;
    }

    //! MENUキーでシミュレータ確認モードをトグル
    function onMenu() as Lang.Boolean {
        var app = Application.getApp() as PicsBleApp;
        app.toggleEmulatorMode();
        return true;
    }

    //! ENTER キーでスキャン ON/OFF トグル（将来拡張用）
    function onSelect() as Lang.Boolean {
        var app = Application.getApp() as PicsBleApp;
        app.toggleEmulatorMode();
        return true;
    }
}

// 不要なメニューデリゲートを削除

//! Connect IQ が呼び出すアプリケーションファクトリ
function getApp() as PicsBleApp {
    return Application.getApp() as PicsBleApp;
}

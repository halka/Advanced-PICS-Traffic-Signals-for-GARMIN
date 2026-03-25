// =============================================================
// PicsBleApp.mc  ―  アプリケーション エントリポイント
// GPSMAP H1i Plus / Connect IQ 3.2.0+
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

    // ----------------------------------------------------------
    //  メインメニュー（MENUボタン）
    // ----------------------------------------------------------

    //! MENUボタン押下 → アクションメニューを表示
    function showMainMenu() as Void {
        var menu = new WatchUi.Menu2({:title => "メニュー"});
        menu.addItem(new WatchUi.MenuItem("交差点一覧", null, 0, {}));
        menu.addItem(new WatchUi.MenuItem("スクリーンショット", null, 1, {}));
        WatchUi.pushView(menu, new PicsMainMenuDelegate(self), WatchUi.SLIDE_UP);
    }

    //! スクリーンショットを撮る（API 4.x 以降対応デバイスのみ）
    function takeScreenshot() as Void {
        if (System has :screenshot) {
            System.screenshot();
        }
    }

    //! 交差点一覧を表示（現在地から近い順に最大30件）
    function showIntersectionList() as Void {
        if (_delegate == null) { return; }
        var db = (_delegate as PicsBleDelegate).getIntersectionDb();
        if (db == null) { return; }

        var allEntries = db.getAllEntries();
        if (allEntries == null) { return; }
        var entries = allEntries as Lang.Array;
        var n = entries.size();
        if (n == 0) { return; }

        // 現在地取得
        var devLat = 0.0f as Lang.Float;
        var devLon = 0.0f as Lang.Float;
        var hasFix = false;
        var posInfo = Position.getInfo();
        if (posInfo != null && posInfo.position != null) {
            var coords = (posInfo.position as Position.Location).toDegrees();
            devLat = coords[0].toFloat();
            devLon = coords[1].toFloat();
            hasFix = true;
        }

        // Partial selection sort: O(n × MAX_ITEMS)
        // 二乗距離でソート（trig不要）→ 上位30件のみ実際の距離・方位を計算
        var MAX_ITEMS = 30;
        var usedArr = new [n];  // null = 未使用
        var sorted  = [] as Lang.Array;
        var menu    = new WatchUi.Menu2({:title => "交差点一覧 (近い順)"});
        var cards   = ["N","NE","E","SE","S","SW","W","NW"] as Array<String>;

        for (var round = 0; round < MAX_ITEMS; round++) {
            var bestSq  = 9.9e9f as Lang.Float;
            var bestIdx = -1;
            for (var i = 0; i < n; i++) {
                if (usedArr[i] != null) { continue; }
                var e    = entries[i] as Lang.Array;
                var eLat = (e[0] as Lang.Number) / 1000000.0f;
                var eLon = (e[1] as Lang.Number) / 1000000.0f;
                var dLat = hasFix ? (devLat - eLat) : 0.0f;
                var dLon = hasFix ? (devLon - eLon) : 0.0f;
                var sq   = dLat * dLat + dLon * dLon;
                if (sq < bestSq) { bestSq = sq; bestIdx = i; }
            }
            if (bestIdx < 0) { break; }
            usedArr[bestIdx] = true;

            var e    = entries[bestIdx] as Lang.Array;
            var eLat = (e[0] as Lang.Number) / 1000000.0f;
            var eLon = (e[1] as Lang.Number) / 1000000.0f;
            var name = e[2] as Lang.String;
            var dist = 0.0f as Lang.Float;
            var brg  = 0.0f as Lang.Float;

            if (hasFix) {
                var db2 = calcDistBrg(devLat, devLon, eLat, eLon);
                dist = db2[0] as Lang.Float;
                brg  = db2[1] as Lang.Float;
            }

            var itemIdx = sorted.size();
            sorted.add([eLat, eLon, name, dist, brg]);

            var cidx = ((brg + 22.5f) / 45.0f).toNumber() % 8;
            var sub  = hasFix
                ? (dist.format("%.0f") + "m " + cards[cidx])
                : "--";
            menu.addItem(new WatchUi.MenuItem(name, sub, itemIdx, {}));
        }

        WatchUi.pushView(menu,
                         new PicsIntersectionListDelegate(devLat, devLon, sorted),
                         WatchUi.SLIDE_UP);
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

    //! MENUキー → アクションメニューを表示
    function onMenu() as Lang.Boolean {
        (Application.getApp() as PicsBleApp).showMainMenu();
        return true;
    }

    //! ENTER キーでスキャン ON/OFF トグル（将来拡張用）
    function onSelect() as Lang.Boolean {
        return false;
    }
}

// ----------------------------------------------------------
//  メインメニューデリゲート
// ----------------------------------------------------------

//! @brief MENUボタンで表示するアクションメニューのデリゲート
class PicsMainMenuDelegate extends WatchUi.Menu2InputDelegate {

    private var _app as PicsBleApp;

    function initialize(app as PicsBleApp) {
        Menu2InputDelegate.initialize();
        _app = app;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        var id = item.getId();
        if (!(id instanceof Lang.Number)) { return; }
        if ((id as Lang.Number) == 0) {
            _app.showIntersectionList();
        } else if ((id as Lang.Number) == 1) {
            _app.takeScreenshot();
        }
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

//! Connect IQ が呼び出すアプリケーションファクトリ
function getApp() as PicsBleApp {
    return Application.getApp() as PicsBleApp;
}

// =============================================================
// PicsIntersectionListView.mc  ―  交差点一覧 / 詳細ビュー
// GPSMAP H1i Plus / Connect IQ 3.2.0+
// =============================================================

import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// ----------------------------------------------------------
//  交差点詳細ビュー
// ----------------------------------------------------------

//! @brief 選択した交差点のすべての情報を表示するビュー
class PicsIntersectionDetailView extends WatchUi.View {

    private var _name   as Lang.String;
    private var _lat    as Lang.Float;
    private var _lon    as Lang.Float;
    private var _devLat as Lang.Float;
    private var _devLon as Lang.Float;
    private var _dist   as Lang.Float;
    private var _brg    as Lang.Float;

    private const SW = 282;
    private const SH = 470;
    private const C_BG     = 0xFFFFFF;
    private const C_ACCENT = 0x0055AA;
    private const C_TEXT   = 0x000000;
    private const C_SUB    = 0x555555;
    private const C_LINE   = 0xCCCCCC;
    private const C_PANEL  = 0xF5F5F5;

    function initialize(name   as Lang.String,
                        lat    as Lang.Float, lon    as Lang.Float,
                        devLat as Lang.Float, devLon as Lang.Float,
                        dist   as Lang.Float, brg    as Lang.Float) {
        View.initialize();
        _name   = name;
        _lat    = lat;    _lon    = lon;
        _devLat = devLat; _devLon = devLon;
        _dist   = dist;   _brg    = brg;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(C_BG, C_BG);
        dc.clear();

        var CX    = SW / 2;
        var cards = ["N","NE","E","SE","S","SW","W","NW"] as Array<String>;
        var cidx  = ((_brg + 22.5f) / 45.0f).toNumber() % 8;

        // ヘッダー
        dc.setColor(C_ACCENT, C_ACCENT);
        dc.fillRectangle(0, 0, SW, 3);
        dc.setColor(C_PANEL, C_PANEL);
        dc.fillRectangle(0, 3, SW, 52);
        dc.setColor(C_ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(CX, 6, Graphics.FONT_TINY, "交差点詳細", Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(C_TEXT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(CX, 26, Graphics.FONT_SMALL, _name, Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(C_LINE, C_LINE);
        dc.fillRectangle(0, 56, SW, 1);

        // 行レイアウト
        var y = 62;
        var rowH = 20;
        var gap  = 6;

        // 交差点の緯度経度
        dc.setColor(C_SUB, Graphics.COLOR_TRANSPARENT);
        dc.drawText(8, y, Graphics.FONT_TINY, "交差点の緯度経度", Graphics.TEXT_JUSTIFY_LEFT);
        y += rowH;
        dc.setColor(C_TEXT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(8, y, Graphics.FONT_TINY,
                    _lat.abs().format("%.6f") + (_lat >= 0.0f ? "°N" : "°S"),
                    Graphics.TEXT_JUSTIFY_LEFT);
        y += rowH;
        dc.drawText(8, y, Graphics.FONT_TINY,
                    _lon.abs().format("%.6f") + (_lon >= 0.0f ? "°E" : "°W"),
                    Graphics.TEXT_JUSTIFY_LEFT);
        y += rowH + gap;
        dc.setColor(C_LINE, C_LINE);
        dc.fillRectangle(0, y, SW, 1);
        y += gap;

        // 現在地の緯度経度
        dc.setColor(C_SUB, Graphics.COLOR_TRANSPARENT);
        dc.drawText(8, y, Graphics.FONT_TINY, "現在地の緯度経度", Graphics.TEXT_JUSTIFY_LEFT);
        y += rowH;
        dc.setColor(C_TEXT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(8, y, Graphics.FONT_TINY,
                    _devLat.abs().format("%.6f") + (_devLat >= 0.0f ? "°N" : "°S"),
                    Graphics.TEXT_JUSTIFY_LEFT);
        y += rowH;
        dc.drawText(8, y, Graphics.FONT_TINY,
                    _devLon.abs().format("%.6f") + (_devLon >= 0.0f ? "°E" : "°W"),
                    Graphics.TEXT_JUSTIFY_LEFT);
        y += rowH + gap;
        dc.setColor(C_LINE, C_LINE);
        dc.fillRectangle(0, y, SW, 1);
        y += gap;

        // 距離
        dc.setColor(C_SUB, Graphics.COLOR_TRANSPARENT);
        dc.drawText(8, y, Graphics.FONT_TINY, "距離", Graphics.TEXT_JUSTIFY_LEFT);
        y += rowH;
        dc.setColor(C_ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(8, y, Graphics.FONT_MEDIUM,
                    _dist.format("%.0f") + " m",
                    Graphics.TEXT_JUSTIFY_LEFT);
        y += 36 + gap;
        dc.setColor(C_LINE, C_LINE);
        dc.fillRectangle(0, y, SW, 1);
        y += gap;

        // 方位
        dc.setColor(C_SUB, Graphics.COLOR_TRANSPARENT);
        dc.drawText(8, y, Graphics.FONT_TINY, "方位", Graphics.TEXT_JUSTIFY_LEFT);
        y += rowH;
        dc.setColor(C_ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(8, y, Graphics.FONT_MEDIUM,
                    _brg.format("%.1f") + "° (" + cards[cidx] + ")",
                    Graphics.TEXT_JUSTIFY_LEFT);

        // フッター
        dc.setColor(C_LINE, C_LINE);
        dc.fillRectangle(0, SH - 26, SW, 1);
        dc.setColor(C_SUB, Graphics.COLOR_TRANSPARENT);
        dc.drawText(CX, SH - 22, Graphics.FONT_TINY, "BACK で戻る", Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(C_ACCENT, C_ACCENT);
        dc.fillRectangle(0, SH - 3, SW, 3);
    }
}

//! @brief 詳細ビューのキー入力デリゲート
class PicsIntersectionDetailDelegate extends WatchUi.BehaviorDelegate {
    function initialize() { BehaviorDelegate.initialize(); }
    function onBack() as Lang.Boolean {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}

// ----------------------------------------------------------
//  交差点一覧デリゲート
// ----------------------------------------------------------

//! @brief Menu2 の交差点一覧でアイテムを選択したときのデリゲート
//!
//! sorted は [[eLat, eLon, name, dist, brg], ...] の配列
class PicsIntersectionListDelegate extends WatchUi.Menu2InputDelegate {

    private var _devLat as Lang.Float;
    private var _devLon as Lang.Float;
    private var _sorted as Lang.Array;

    function initialize(devLat as Lang.Float, devLon as Lang.Float,
                        sorted as Lang.Array) {
        Menu2InputDelegate.initialize();
        _devLat = devLat;
        _devLon = devLon;
        _sorted = sorted;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (!(id instanceof Lang.Number)) { return; }
        var idx = id as Lang.Number;
        if (idx < 0 || idx >= _sorted.size()) { return; }
        var e = _sorted[idx] as Lang.Array;
        WatchUi.pushView(
            new PicsIntersectionDetailView(
                e[2] as Lang.String,
                e[0] as Lang.Float, e[1] as Lang.Float,
                _devLat, _devLon,
                e[3] as Lang.Float, e[4] as Lang.Float
            ),
            new PicsIntersectionDetailDelegate(),
            WatchUi.SLIDE_LEFT
        );
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}

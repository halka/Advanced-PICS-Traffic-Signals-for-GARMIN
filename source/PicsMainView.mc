// =============================================================
// PicsMainView.mc  ―  メイン表示ビュー
// GPSMAP H1i Plus 画面: 282 × 470 px (portrait)
// =============================================================

import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Position;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;
import Toybox.System;

class PicsMainView extends WatchUi.View {

    // ---- カラーパレット ----
    private const COLOR_BG         = 0xFFFFFF; // White
    private const COLOR_PANEL      = 0xF4F7FA; // Cool gray
    private const COLOR_LIVE       = 0xE8F2FA; // Live signal panel
    private const COLOR_BORDER     = 0xD7DEE8; // Soft border
    private const COLOR_ACCENT     = 0x0055AA; // Blue
    private const COLOR_TEXT_MAIN  = 0x102A43; // Navy
    private const COLOR_TEXT_SUB   = 0x52606D; // Slate
    private const COLOR_TEXT_MUTED = 0x829AB1; // Muted slate

    private const COLOR_RED        = 0xE12D39; // Red
    private const COLOR_GREEN      = 0x18A558; // Green
    private const COLOR_BLINK_G    = 0x18A558; // Blinking green
    private const COLOR_NONE       = 0xBCCCDC; // Gray

    // ---- ステート ----
    private var _lastFrame         as PicsFrame or Null = null;
    private var _rxCount           as Lang.Long = 0l;
    private var _lastReceivedTime  as Lang.String = "";
    private var _lastReceivedSysTime as Lang.Number = 0;
    private var _scanning          as Lang.Boolean = false;
    private var _blinkPhase       as Lang.Boolean = false;
    private var _intersectionName as Lang.String = "";
    private var _intersectionLat  as Lang.Float = 0.0f;
    private var _intersectionLon  as Lang.Float = 0.0f;
    
    // GPS & リスト
    private var _db as PicsIntersectionDB or Null = null;
    private var _topIntersections as Lang.Array or Null = null;
    private var _lastCalcLat as Lang.Float = 0.0f;
    private var _lastCalcLon as Lang.Float = 0.0f;
    private var _currentRowOffset as Lang.Number = 0;
    private var _needsListUpdate as Lang.Boolean = true;

    function initialize() {
        View.initialize();
    }

    function onLayout(dc as Graphics.Dc) as Void {
    }

    private var _emulatorModeActive as Lang.Boolean = false;

    function setDb(db as PicsIntersectionDB or Null) as Void {
        _db = db;
        _needsListUpdate = true;
    }

    function setEmulatorMode(active as Lang.Boolean) as Void {
        _emulatorModeActive = active;
        _needsListUpdate = true;
        _currentRowOffset = 0;
        if (active) {
            _topIntersections = null;
        }
        WatchUi.requestUpdate();
    }

    function updateSignal(frame as PicsFrame, rxCount as Lang.Long,
                          intersectionName as Lang.String,
                          intersectionLat as Lang.Float,
                          intersectionLon as Lang.Float) as Void {
        _lastFrame        = frame;
        _rxCount          = rxCount;
        _scanning         = true;
        var now = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        _lastReceivedTime = pad4(now.year) + "-"
                          + pad2(now.month) + "-"
                          + pad2(now.day) + " "
                          + pad2(now.hour) + ":"
                          + pad2(now.min)  + ":"
                          + pad2(now.sec);
        _lastReceivedSysTime = System.getTimer();
        _intersectionName = intersectionName;
        _intersectionLat = intersectionLat;
        _intersectionLon = intersectionLon;
        WatchUi.requestUpdate();
    }

    function setScanningState(scanning as Lang.Boolean) as Void {
        _scanning = scanning;
        WatchUi.requestUpdate();
    }

    function toggleBlinkPhase() as Void {
        _blinkPhase = !_blinkPhase;
        if (_scanning || _lastFrame != null) { WatchUi.requestUpdate(); }
    }

    function scrollDown() as Void {
        _currentRowOffset += 1;
        WatchUi.requestUpdate();
    }

    function scrollUp() as Void {
        _currentRowOffset -= 1;
        if (_currentRowOffset < 0) { _currentRowOffset = 0; }
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var screenW = dc.getWidth();
        var screenH = dc.getHeight();

        dc.setColor(COLOR_BG, COLOR_BG);
        dc.clear();

        // 1. 位置情報の取得とリストの更新
        var devLat = 0.0f;
        var devLon = 0.0f;
        var hasFix = false;
        var posInfo = null;
        if (!_emulatorModeActive) {
            posInfo = Position.getInfo();
            if (posInfo != null && posInfo.position != null) {
                var coords = (posInfo.position as Position.Location).toDegrees();
                devLat = coords[0].toFloat();
                devLon = coords[1].toFloat();
                hasFix = true;
            }
        } else {
            hasFix = true;
        }

        if (!_emulatorModeActive && !hasFix) {
            _topIntersections = null;
        } else if (!_emulatorModeActive && _db != null) {
            var moved = _needsListUpdate;
            _needsListUpdate = false;
            if (_topIntersections == null) {
                moved = true;
            } else {
                var d = calcDistBrg(devLat, devLon, _lastCalcLat, _lastCalcLon)[0] as Lang.Float;
                if (d > 10.0f) { // 10m以上移動したら再計算
                    moved = true;
                }
            }
            if (moved) {
                _topIntersections = (_db as PicsIntersectionDB).getTopN(devLat, devLon, 15);
                _lastCalcLat = devLat;
                _lastCalcLon = devLon;
            }
        }

        // 描画
        drawHeader(dc, screenW, devLat, devLon, hasFix);
        drawCards(dc, screenW, screenH, devLat, devLon, hasFix);
    }

    private function drawHeader(dc as Graphics.Dc, screenW as Lang.Number,
                                devLat as Lang.Float, devLon as Lang.Float,
                                hasFix as Lang.Boolean) as Void {
        dc.setColor(COLOR_PANEL, COLOR_PANEL);
        dc.fillRectangle(0, 0, screenW, 64);
        dc.setColor(COLOR_ACCENT, COLOR_ACCENT);
        dc.fillRectangle(0, 0, screenW, 3);
        
        var statusLabel = Rez.Strings.StoppedIndicator;
        var statusColor = COLOR_NONE;
        var receiving = _scanning || _lastFrame != null;
        if (receiving) {
            var nowTimer = System.getTimer();
            if (_lastReceivedSysTime > 0 && (nowTimer - _lastReceivedSysTime) > 5000) {
                statusColor = COLOR_RED;
                statusLabel = Rez.Strings.LostIndicator;
            } else {
                statusColor = COLOR_GREEN;
                statusLabel = Rez.Strings.ScanningIndicator;
            }
        }

        dc.setColor(COLOR_TEXT_MAIN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(10, 8, Graphics.FONT_SMALL, "PICS", Graphics.TEXT_JUSTIFY_LEFT);

        dc.setColor(statusColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(screenW - 10, 10, Graphics.FONT_XTINY,
                    WatchUi.loadResource(statusLabel) as Lang.String,
                    Graphics.TEXT_JUSTIFY_RIGHT);

        var timeStr = WatchUi.loadResource(Rez.Strings.WaitingDots) as Lang.String;
        if (_lastReceivedTime.length() > 0) {
            timeStr = _lastReceivedTime;
        }

        dc.setColor(COLOR_TEXT_SUB, Graphics.COLOR_TRANSPARENT);
        dc.drawText(10, 30, Graphics.FONT_XTINY,
                    timeStr,
                    Graphics.TEXT_JUSTIFY_LEFT);

        dc.drawText(screenW - 10, 30, Graphics.FONT_XTINY,
                    _rxCount.toString() + " pkt",
                    Graphics.TEXT_JUSTIFY_RIGHT);

        dc.setColor(COLOR_TEXT_MUTED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(10, 47, Graphics.FONT_XTINY,
                    formatDevicePosition(devLat, devLon, hasFix),
                    Graphics.TEXT_JUSTIFY_LEFT);

        dc.setColor(COLOR_BORDER, COLOR_BORDER);
        dc.fillRectangle(0, 63, screenW, 1);
    }

    private function formatDevicePosition(devLat as Lang.Float, devLon as Lang.Float,
                                          hasFix as Lang.Boolean) as Lang.String {
        if (!hasFix) {
            return "Pos: --,--";
        }
        return "Pos: " + devLat.format("%.4f") + "," + devLon.format("%.4f");
    }

    private function pad2(value) as Lang.String {
        var str = value.toString();
        if (str.length() < 2) {
            return "0" + str;
        }
        return str;
    }

    private function pad4(value) as Lang.String {
        var str = value.toString();
        while (str.length() < 4) {
            str = "0" + str;
        }
        return str;
    }

    private function drawCards(dc as Graphics.Dc, screenW as Lang.Number, screenH as Lang.Number,
                               devLat as Lang.Float, devLon as Lang.Float,
                               hasFix as Lang.Boolean) as Void {
        var cardsData = [] as Lang.Array;

        var activeSigs = [] as Lang.Array;
        var featuredItem = null;
        if (_lastFrame != null) {
            var frame = _lastFrame as PicsFrame;
            var nowTimer = System.getTimer();
            if (_lastReceivedSysTime > 0 && (nowTimer - _lastReceivedSysTime) <= 5000) {
                for (var i = 0; i < PICS_SIGNAL_COUNT; i++) {
                    var s = frame.signals[i] as PicsSignal;
                    if (s.state != SIGNAL_NO_SIGNAL) {
                        activeSigs.add(s);
                    }
                }
            }
        }

        if (_emulatorModeActive && _lastFrame != null) {
            featuredItem = createEmulatorCard(devLat, devLon);
            cardsData.add(featuredItem);
        } else if (_topIntersections != null && (_topIntersections as Lang.Array).size() > 0) {
            var arr = _topIntersections as Lang.Array;
            for (var i = 0; i < arr.size(); i++) {
                var item = arr[i] as Lang.Dictionary;
                var entry = item["entry"] as Lang.Array;
                var name = entry[2] as Lang.String;

                var sigs = [] as Lang.Array;
                if (name.equals(_intersectionName) && activeSigs.size() > 0) {
                    sigs = activeSigs;
                }

                var cardItem = {
                    "name" => name,
                    "addr" => entry[4] as Lang.String,
                    "dist" => item["dist"] as Lang.Float,
                    "brg"  => item["brg"] as Lang.Float,
                    "signals" => sigs
                };
                cardsData.add(cardItem);
            }
        }

        if (featuredItem == null && activeSigs.size() > 0 && _lastFrame != null) {
            featuredItem = createLiveCard(_lastFrame as PicsFrame, activeSigs,
                                          devLat, devLon, hasFix);
        }

        if (cardsData.size() == 0 && featuredItem == null) {
            dc.setColor(COLOR_ACCENT, Graphics.COLOR_TRANSPARENT);
            dc.drawText(screenW/2, 112, Graphics.FONT_MEDIUM,
                        emptyStateText(hasFix),
                        Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }

        var y = 72;
        if (featuredItem != null) {
            drawLiveCard(dc, 8, y, screenW - 16, 112, featuredItem as Lang.Dictionary);
            y += 120;
        }

        if (cardsData.size() == 0) {
            dc.setColor(COLOR_TEXT_SUB, Graphics.COLOR_TRANSPARENT);
            dc.drawText(screenW/2, y + 18, Graphics.FONT_SMALL,
                        emptyStateText(hasFix),
                        Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }

        var listTop = y + 22;
        drawNearbyHeading(dc, 10, y, screenW - 20, cardsData.size());

        var maxOffset = cardsData.size() - 1;
        if (_currentRowOffset > maxOffset) { _currentRowOffset = maxOffset; }

        dc.setClip(0, listTop, screenW, screenH - listTop);
        var rowY = listTop - (_currentRowOffset * 54);
        for (var i = 0; i < cardsData.size(); i++) {
            if (rowY + 50 >= listTop && rowY < screenH) {
                drawNearbyRow(dc, 8, rowY, screenW - 16,
                              cardsData[i] as Lang.Dictionary);
            }
            rowY += 54;
        }
        dc.clearClip();
    }

    private function createEmulatorCard(devLat as Lang.Float, devLon as Lang.Float) as Lang.Dictionary {
        var frame = _lastFrame as PicsFrame;
        var sigs = [] as Lang.Array;
        for (var i = 0; i < PICS_SIGNAL_COUNT; i++) {
            var s = frame.signals[i] as PicsSignal;
            if (s.state != SIGNAL_NO_SIGNAL) {
                sigs.add(s);
            }
        }
        var db = calcDistBrg(devLat, devLon, frame.latitude, frame.longitude);
        return {
            "name" => _intersectionName,
            "addr" => "シミュレーションモード",
            "dist" => db[0] as Lang.Float,
            "brg"  => db[1] as Lang.Float,
            "hasDistance" => true,
            "tx"   => frame.transmitterId,
            "rssi" => frame.rssi,
            "signals" => sigs
        };
    }

    private function createLiveCard(frame as PicsFrame, sigs as Lang.Array,
                                    devLat as Lang.Float, devLon as Lang.Float,
                                    hasFix as Lang.Boolean) as Lang.Dictionary {
        var name = _intersectionName;
        if (name.length() == 0) {
            name = frame.intersectionId;
        }

        var dist = 0.0f;
        var brg = 0.0f;
        var hasDistance = hasFix && _intersectionName.length() > 0 &&
                          isValidCoordinate(_intersectionLat, _intersectionLon);
        if (hasDistance) {
            var db = calcDistBrg(devLat, devLon, _intersectionLat, _intersectionLon);
            dist = db[0] as Lang.Float;
            brg = db[1] as Lang.Float;
        }

        return {
            "name" => name,
            "dist" => dist,
            "brg"  => brg,
            "hasDistance" => hasDistance,
            "tx"   => frame.transmitterId,
            "rssi" => frame.rssi,
            "signals" => sigs
        };
    }

    private function drawLiveCard(dc as Graphics.Dc, x as Lang.Number, y as Lang.Number,
                                  w as Lang.Number, h as Lang.Number,
                                  item as Lang.Dictionary) as Void {
        dc.setColor(COLOR_LIVE, COLOR_LIVE);
        dc.fillRectangle(x, y, w, h);
        dc.setColor(COLOR_ACCENT, COLOR_ACCENT);
        dc.fillRectangle(x, y, 4, h);
        dc.setColor(COLOR_BORDER, COLOR_BORDER);
        dc.drawRectangle(x, y, w, h);

        var name = item["name"] as Lang.String;
        var dist = item["dist"] as Lang.Float;
        var brg = item["brg"] as Lang.Float;
        var hasDistance = item["hasDistance"] as Lang.Boolean;
        var rssi = item["rssi"];
        var sigs = item["signals"] as Lang.Array;
        var tx = item["tx"] as Lang.String;

        dc.setColor(COLOR_ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + 14, y + 8, Graphics.FONT_XTINY, "LIVE SIGNAL",
                    Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(COLOR_TEXT_MUTED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + w - 12, y + 8, Graphics.FONT_XTINY,
                    (rssi != null) ? (rssi.toString() + " dBm") : "-- dBm",
                    Graphics.TEXT_JUSTIFY_RIGHT);

        dc.setColor(COLOR_TEXT_MAIN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + 14, y + 25, Graphics.FONT_SMALL,
                    shortText(name, 21), Graphics.TEXT_JUSTIFY_LEFT);

        if (shouldShowTx(tx) && !tx.equals(name)) {
            dc.setColor(COLOR_TEXT_MUTED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x + 14, y + 45, Graphics.FONT_XTINY,
                        "TX " + shortText(tx, 18), Graphics.TEXT_JUSTIFY_LEFT);
        }

        var signalX = x + 18;
        var maxSignals = sigs.size();
        if (maxSignals > 6) { maxSignals = 6; }
        for (var i = 0; i < maxSignals; i++) {
            var s = sigs[i] as PicsSignal;
            drawCompactSignal(dc, signalX + (i * 38), y + 72, s.state, s.remaining);
        }
        if (sigs.size() > 6) {
            dc.setColor(COLOR_TEXT_MUTED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(signalX + 6 * 38 - 4, y + 68, Graphics.FONT_XTINY,
                        "+" + (sigs.size() - 6).toString(), Graphics.TEXT_JUSTIFY_LEFT);
        }

        dc.setColor(COLOR_ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + w - 12, y + 91, Graphics.FONT_XTINY,
                    hasDistance ? (formatDistance(dist) + "  " + formatBearing(brg)) : "--",
                    Graphics.TEXT_JUSTIFY_RIGHT);
    }

    private function drawCompactSignal(dc as Graphics.Dc, x as Lang.Number, y as Lang.Number,
                                       state as Lang.Number, remaining as Lang.Number) as Void {
        var color = signalColor(state);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y, 11);
        dc.setColor(COLOR_TEXT_SUB, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(x, y, 11);

        var remainingStr = "--";
        if (state != SIGNAL_NO_SIGNAL && remaining >= 0) {
            remainingStr = remaining.toString();
        }
        dc.setColor(COLOR_TEXT_MAIN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, Graphics.FONT_XTINY, remainingStr,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function drawNearbyHeading(dc as Graphics.Dc, x as Lang.Number, y as Lang.Number,
                                       w as Lang.Number, count as Lang.Number) as Void {
        dc.setColor(COLOR_TEXT_SUB, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, Graphics.FONT_XTINY, "NEARBY SIGNALS",
                    Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(COLOR_TEXT_MUTED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + w, y, Graphics.FONT_XTINY, count.toString(),
                    Graphics.TEXT_JUSTIFY_RIGHT);
        dc.setColor(COLOR_BORDER, COLOR_BORDER);
        dc.drawLine(x, y + 17, x + w, y + 17);
    }

    private function drawNearbyRow(dc as Graphics.Dc, x as Lang.Number, y as Lang.Number,
                                   w as Lang.Number, item as Lang.Dictionary) as Void {
        var name = item["name"] as Lang.String;
        var addr = item["addr"] as Lang.String;
        var dist = item["dist"] as Lang.Float;
        var brg = item["brg"] as Lang.Float;
        var sigs = item["signals"] as Lang.Array;

        dc.setColor(COLOR_PANEL, COLOR_PANEL);
        dc.fillRectangle(x, y, w, 50);
        dc.setColor(COLOR_BORDER, COLOR_BORDER);
        dc.drawRectangle(x, y, w, 50);

        if (sigs.size() > 0) {
            dc.setColor(COLOR_ACCENT, COLOR_ACCENT);
            dc.fillRectangle(x, y, 3, 50);
        }

        dc.setColor(COLOR_TEXT_MAIN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + 12, y + 6, Graphics.FONT_SMALL,
                    shortText(name, 18), Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(COLOR_TEXT_SUB, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + 12, y + 27, Graphics.FONT_XTINY,
                    shortText(addr, 23), Graphics.TEXT_JUSTIFY_LEFT);

        dc.setColor(COLOR_ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + w - 12, y + 6, Graphics.FONT_SMALL,
                    formatDistance(dist), Graphics.TEXT_JUSTIFY_RIGHT);
        dc.setColor(COLOR_TEXT_SUB, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + w - 12, y + 27, Graphics.FONT_XTINY,
                    formatBearing(brg), Graphics.TEXT_JUSTIFY_RIGHT);
    }

    private function signalColor(state as Lang.Number) as Lang.Number {
        if (state == SIGNAL_RED) { return COLOR_RED; }
        if (state == SIGNAL_GREEN) { return COLOR_GREEN; }
        if (state == SIGNAL_BLINK_GREEN) {
            return _blinkPhase ? COLOR_BLINK_G : COLOR_NONE;
        }
        return COLOR_NONE;
    }

    private function formatDistance(dist as Lang.Float) as Lang.String {
        if (dist < 1000.0f) {
            return dist.format("%.0f") + "m";
        }
        return (dist / 1000.0f).format("%.1f") + "km";
    }

    private function formatBearing(brg as Lang.Float) as Lang.String {
        var directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"] as Array<String>;
        var index = ((brg + 22.5f) / 45.0f).toNumber() % 8;
        return brg.format("%.0f") + "° " + directions[index];
    }

    private function emptyStateText(hasFix as Lang.Boolean) as Lang.String {
        if (hasFix) {
            return WatchUi.loadResource(Rez.Strings.NoNearbyIntersections) as Lang.String;
        }
        return WatchUi.loadResource(Rez.Strings.WaitingForPosition) as Lang.String;
    }

    private function shortText(text as Lang.String, maxChars as Lang.Number) as Lang.String {
        if (text.length() <= maxChars) { return text; }
        if (maxChars <= 3) { return text.substring(0, maxChars); }
        return text.substring(0, maxChars - 3) + "...";
    }

    private function shouldShowTx(tx as Lang.String) as Lang.Boolean {
        return tx.length() > 0 && !tx.equals("--") && !tx.equals("--------");
    }

}

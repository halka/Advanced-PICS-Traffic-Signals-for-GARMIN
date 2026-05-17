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
    private const COLOR_PANEL      = 0xF0F0F0; // Light Gray
    private const COLOR_BORDER     = 0xCCCCCC; // Gray
    private const COLOR_ACCENT     = 0x0055AA; // Blue
    private const COLOR_TEXT_MAIN  = 0x000000; // Black
    private const COLOR_TEXT_SUB   = 0x333333; // Dark Gray

    private const COLOR_RED        = 0xFF0000; // Bright Red
    private const COLOR_GREEN      = 0x00CC00; // Bright Green
    private const COLOR_BLINK_G    = 0x00CC00; // Blinking Green
    private const COLOR_NONE       = 0xAAAAAA; // Gray

    // ---- ステート ----
    private var _lastFrame         as PicsFrame or Null = null;
    private var _rxCount           as Lang.Long = 0l;
    private var _lastReceivedTime  as Lang.String = "";
    private var _lastReceivedClock as Lang.String = "";
    private var _lastReceivedSysTime as Lang.Number = 0;
    private var _scanning          as Lang.Boolean = false;
    private var _blinkPhase       as Lang.Boolean = false;
    private var _intersectionName as Lang.String = "";
    
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
    }

    function setEmulatorMode(active as Lang.Boolean) as Void {
        _emulatorModeActive = active;
        _needsListUpdate = true;
        WatchUi.requestUpdate();
    }

    function updateSignal(frame as PicsFrame, rxCount as Lang.Long,
                          intersectionName as Lang.String,
                          intersectionLat  as Lang.Float,
                          intersectionLon  as Lang.Float) as Void {
        _lastFrame        = frame;
        _rxCount          = rxCount;
        _scanning         = true;
        var now = Gregorian.info(Time.now(), Time.FORMAT_LONG);
        _lastReceivedTime = now.year.format("%04d") + "-"
                          + now.month.format("%02d") + "-"
                          + now.day.format("%02d") + " "
                          + now.hour.format("%02d") + ":"
                          + now.min.format("%02d")  + ":"
                          + now.sec.format("%02d");
        _lastReceivedClock = now.hour.format("%02d") + ":"
                           + now.min.format("%02d")  + ":"
                           + now.sec.format("%02d");
        _lastReceivedSysTime = System.getTimer();
        _intersectionName = intersectionName;
        _needsListUpdate = true;
        WatchUi.requestUpdate();
    }

    function setScanningState(scanning as Lang.Boolean) as Void {
        _scanning = scanning;
        WatchUi.requestUpdate();
    }

    function toggleBlinkPhase() as Void {
        _blinkPhase = !_blinkPhase;
        if (_lastFrame != null) { WatchUi.requestUpdate(); }
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

    function refreshRealtime() as Void {
        if (_scanning || _lastFrame != null) { WatchUi.requestUpdate(); }
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var screenW = dc.getWidth();
        var screenH = dc.getHeight();

        dc.setColor(COLOR_BG, COLOR_BG);
        dc.clear();

        // 1. 位置情報の取得とリストの更新
        var devLat = 43.066768f;
        var devLon = 141.350582f;
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

        if (_db != null) {
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
        drawCards(dc, screenW, screenH, devLat, devLon);
    }

    private function drawHeader(dc as Graphics.Dc, screenW as Lang.Number,
                                devLat as Lang.Float, devLon as Lang.Float,
                                hasFix as Lang.Boolean) as Void {
        dc.setColor(COLOR_PANEL, COLOR_PANEL);
        dc.fillRectangle(0, 0, screenW, 62);
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

        dc.setColor(statusColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(screenW - 8, 8, Graphics.FONT_SMALL,
                    WatchUi.loadResource(statusLabel) as Lang.String,
                    Graphics.TEXT_JUSTIFY_RIGHT);

        var timeStr = WatchUi.loadResource(Rez.Strings.WaitingDots) as Lang.String;
        if (_lastReceivedClock.length() > 0) {
            timeStr = _lastReceivedClock;
        }

        dc.setColor(COLOR_TEXT_SUB, Graphics.COLOR_TRANSPARENT);
        dc.drawText(8, 8, Graphics.FONT_XTINY,
                    timeStr + " " + _rxCount.toString() + " pkt",
                    Graphics.TEXT_JUSTIFY_LEFT);

        var posStr = "-,-";
        if (hasFix) {
            posStr = devLat.format("%.4f") + "," + devLon.format("%.4f");
        }
        dc.drawText(8, 30, Graphics.FONT_XTINY, posStr, Graphics.TEXT_JUSTIFY_LEFT);

        dc.setColor(COLOR_BORDER, COLOR_BORDER);
        dc.fillRectangle(0, 62, screenW, 2);
    }

    private function drawCards(dc as Graphics.Dc, screenW as Lang.Number, screenH as Lang.Number,
                               devLat as Lang.Float, devLon as Lang.Float) as Void {
        var cardsData = [] as Lang.Array;
        
        var activeIntersectionId = null;
        var activeTransmitterId = "--";
        var activeSigs = [] as Lang.Array;
        var frameRssi = null;
        if (_lastFrame != null) {
            var frame = _lastFrame as PicsFrame;
            var nowTimer = System.getTimer();
            if (_lastReceivedSysTime > 0 && (nowTimer - _lastReceivedSysTime) <= 5000) {
                activeIntersectionId = frame.intersectionId;
                activeTransmitterId = frame.transmitterId;
                frameRssi = frame.rssi;
                for (var i = 0; i < PICS_SIGNAL_COUNT; i++) {
                    var s = frame.signals[i] as PicsSignal;
                    if (s.state != SIGNAL_NO_SIGNAL) {
                        activeSigs.add(s);
                    }
                }
            }
        }

        if (_topIntersections != null && (_topIntersections as Lang.Array).size() > 0) {
            var arr = _topIntersections as Lang.Array;
            for (var i = 0; i < arr.size(); i++) {
                var item = arr[i] as Lang.Dictionary;
                var entry = item["entry"] as Lang.Array;
                var name = entry[2] as Lang.String;
                
                var sigs = [] as Lang.Array;
                var isBleActive = false;
                var rssiVal = null;
                
                if (activeIntersectionId != null && name.equals(_intersectionName) && activeSigs.size() > 0) {
                    sigs = activeSigs;
                    isBleActive = true;
                    rssiVal = frameRssi;
                }
                
                var cardItem = {
                    "name" => name,
                    "hira" => entry[3] as Lang.String,
                    "addr" => entry[4] as Lang.String,
                    "lat"  => entry[0].toFloat(),
                    "lon"  => entry[1].toFloat(),
                    "dist" => item["dist"] as Lang.Float,
                    "brg"  => item["brg"] as Lang.Float,
                    "id"   => isBleActive ? activeIntersectionId : "--",
                    "tx"   => isBleActive ? activeTransmitterId : "--",
                    "rssi" => rssiVal,
                    "signals" => sigs
                };
                cardsData.add(cardItem);
            }
        }

        if (cardsData.size() == 0 && _emulatorModeActive && _lastFrame != null) {
            cardsData.add(createEmulatorCard(devLat, devLon));
        }

        if (cardsData.size() == 0) {
            dc.setColor(COLOR_ACCENT, Graphics.COLOR_TRANSPARENT);
            dc.drawText(screenW/2, 100, Graphics.FONT_MEDIUM, "検索対象が近くにありません", Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }

        var maxOffset = cardsData.size() - 1;
        if (maxOffset < 0) { maxOffset = 0; }
        if (_currentRowOffset > maxOffset) { _currentRowOffset = maxOffset; }

        var gap = 8;
        var y = 68;

        dc.setClip(0, 64, screenW, screenH - 67);

        for (var i = _currentRowOffset; i < cardsData.size(); i++) {
            if (y > screenH - 12) { break; }
            var item = cardsData[i] as Lang.Dictionary;
            var sigs = item["signals"] as Lang.Array;
            var cardH = calculateCardHeight(item, sigs);
            
            drawSingleCard(dc, 8, y, screenW - 16, cardH, item);
            y += cardH + gap;
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
            "hira" => "",
            "addr" => "シミュレーションモード",
            "lat"  => frame.latitude,
            "lon"  => frame.longitude,
            "dist" => db[0] as Lang.Float,
            "brg"  => db[1] as Lang.Float,
            "id"   => frame.intersectionId,
            "tx"   => frame.transmitterId,
            "rssi" => frame.rssi,
            "signals" => sigs
        };
    }

    private function calculateCardHeight(item as Lang.Dictionary, sigs as Lang.Array) as Lang.Number {
        var name = item["name"] as Lang.String;
        var addr = item["addr"] as Lang.String;
        
        var wrappedName = wrapName(name);
        var wrappedAddr = wrapAddress(addr);
        var tx = item["tx"] as Lang.String;
        var txH = shouldShowTx(tx) ? 18 : 0;
        
        var staticH = 8 + (24 * wrappedName.size()) + txH
                    + (18 * wrappedAddr.size())
                    + 18 + 6;
        
        var numSigs = sigs.size();
        if (numSigs == 0) {
            numSigs = 1;
        }
        
        return staticH + numSigs * 52 + 6;
    }

    private function drawSingleCard(dc as Graphics.Dc, x as Lang.Number, y as Lang.Number, w as Lang.Number, h as Lang.Number, item as Lang.Dictionary) as Void {
        dc.setColor(COLOR_PANEL, COLOR_PANEL);
        dc.fillRectangle(x, y, w, h);
        dc.setColor(COLOR_BORDER, COLOR_BORDER);
        dc.drawRectangle(x, y, w, h);

        var name = item["name"] as Lang.String;
        var addr = item["addr"] as Lang.String;
        var latVal = item["lat"] as Lang.Float;
        var lonVal = item["lon"] as Lang.Float;
        var dist = item["dist"] as Lang.Float;
        var brg = item["brg"] as Lang.Float;
        var tx = item["tx"] as Lang.String;
        var rssi = item["rssi"];
        var sigs = item["signals"] as Lang.Array;

        var padX = 14;
        var textX = x + padX;
        var cy = y + 8;

        // 1. 交差点名
        dc.setColor(COLOR_TEXT_MAIN, Graphics.COLOR_TRANSPARENT);
        var wrappedName = wrapName(name);
        for (var i = 0; i < wrappedName.size(); i++) {
            dc.drawText(textX, cy, Graphics.FONT_SMALL, wrappedName[i] as Lang.String, Graphics.TEXT_JUSTIFY_LEFT);
            cy += 24;
        }

        if (shouldShowTx(tx)) {
            dc.setColor(COLOR_ACCENT, Graphics.COLOR_TRANSPARENT);
            dc.drawText(textX, cy, Graphics.FONT_XTINY, "ID: " + tx, Graphics.TEXT_JUSTIFY_LEFT);
            cy += 18;
        }

        // 2. 所在地（小さい文字、折り返し）
        dc.setColor(COLOR_TEXT_SUB, Graphics.COLOR_TRANSPARENT);
        var wrappedAddr = wrapAddress(addr);
        for (var i = 0; i < wrappedAddr.size(); i++) {
            dc.drawText(textX, cy, Graphics.FONT_XTINY, wrappedAddr[i] as Lang.String, Graphics.TEXT_JUSTIFY_LEFT);
            cy += 18;
        }

        // 4. 信号機の緯度経度（小さい文字）
        var latStr = latVal.format("%.4f");
        var lonStr = lonVal.format("%.4f");
        dc.setColor(COLOR_TEXT_SUB, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + w / 2, cy, Graphics.FONT_XTINY, "Lat: " + latStr + " Lon: " + lonStr, Graphics.TEXT_JUSTIFY_CENTER);
        cy += 18;

        // 5. 信号機表示ブロック（繰り返す）
        var sy = cy + 4;
        var numSigs = sigs.size();
        
        if (numSigs > 0) {
            for (var i = 0; i < numSigs; i++) {
                var s = sigs[i] as PicsSignal;
                if (i > 0) {
                    dc.setColor(COLOR_BORDER, COLOR_BORDER);
                    dc.drawLine(x + 12, sy, x + w - 12, sy);
                }
                drawSignalBlock(dc, x, sy, w, s.state, s.remaining, rssi, dist, brg);
                sy += 52;
            }
        } else {
            drawSignalBlock(dc, x, sy, w, SIGNAL_NO_SIGNAL, -1, null, dist, brg);
        }
    }

    private function drawSignalBlock(dc as Graphics.Dc, x as Lang.Number, sy as Lang.Number, w as Lang.Number, 
                                     state as Lang.Number, remaining as Lang.Number, rssi as Lang.Number or Null, 
                                     dist as Lang.Float, brg as Lang.Float) as Void {
        var color = COLOR_NONE;
        if (state == SIGNAL_RED) { color = COLOR_RED; }
        else if (state == SIGNAL_GREEN) { color = COLOR_GREEN; }
        else if (state == SIGNAL_BLINK_GREEN) { color = _blinkPhase ? COLOR_BLINK_G : COLOR_NONE; }
        
        // 信号の丸
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x + 38, sy + 25, 18);
        dc.setColor(COLOR_TEXT_SUB, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(x + 38, sy + 25, 18);

        var remainingStr = "--";
        if (state != SIGNAL_NO_SIGNAL && remaining >= 0) {
            remainingStr = remaining.toString();
        }
        dc.setColor(COLOR_TEXT_MAIN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + 84, sy + 25, Graphics.FONT_LARGE, remainingStr,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(COLOR_TEXT_SUB, Graphics.COLOR_TRANSPARENT);
        var dbmStr = (rssi != null) ? (rssi.toString() + " dBm") : "-- dBm";
        dc.drawText(x + w - 12, sy + 6, Graphics.FONT_TINY, dbmStr, Graphics.TEXT_JUSTIFY_RIGHT);

        var cards = ["N","NE","E","SE","S","SW","W","NW"] as Array<String>;
        var cidx  = ((brg + 22.5f) / 45.0f).toNumber() % 8;
        var distBrgStr = dist.format("%.0f") + "m  " + brg.format("%.0f") + " (" + cards[cidx] + ")";

        dc.setColor(COLOR_ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + w - 12, sy + 30, Graphics.FONT_TINY, distBrgStr, Graphics.TEXT_JUSTIFY_RIGHT);
    }

    private function shouldShowTx(tx as Lang.String) as Lang.Boolean {
        return tx.length() > 0 && !tx.equals("--") && !tx.equals("--------");
    }

    private function wrapName(text as Lang.String) as Lang.Array {
        var len = text.length();
        if (len <= 12) {
            return wrapText(text, 12);
        }
        if (len <= 18) {
            return wrapText(text, ((len + 1) / 2).toNumber());
        }
        if (len <= 27) {
            return wrapText(text, ((len + 2) / 3).toNumber());
        }
        return wrapText(text, 10);
    }

    private function wrapAddress(text as Lang.String) as Lang.Array {
        var len = text.length();
        var lineCount = 1;
        if (len > 54) {
            lineCount = 4;
        } else if (len > 36) {
            lineCount = 3;
        } else if (len > 18) {
            lineCount = 2;
        }
        return wrapText(text, ((len + lineCount - 1) / lineCount).toNumber());
    }

    private function wrapText(text as Lang.String, maxChars as Lang.Number) as Lang.Array {
        var lines = [] as Lang.Array;
        var len = text.length();
        var i = 0;
        while (i < len) {
            var end = i + maxChars;
            if (end > len) { end = len; }
            lines.add(text.substring(i, end));
            i += maxChars;
        }
        return lines;
    }
}

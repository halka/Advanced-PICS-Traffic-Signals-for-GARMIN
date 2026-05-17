// =============================================================
// PicsMainView.mc  ―  メイン表示ビュー
// GPSMAP H1i Plus 画面: 282 × 470 px (portrait)
// =============================================================

import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
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
    private const COLOR_BLINK_G    = 0xDDDD00; // Yellow
    private const COLOR_NONE       = 0xAAAAAA; // Gray

    // ---- ステート ----
    private var _lastFrame         as PicsFrame or Null = null;
    private var _rxCount           as Lang.Long = 0l;
    private var _lastReceivedTime  as Lang.String = "";
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
        var now = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        _lastReceivedTime = now.hour.format("%02d") + ":"
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

    //! 距離計算ヘルパー（移動量チェック用）
    private function distance(lat1 as Lang.Float, lon1 as Lang.Float, lat2 as Lang.Float, lon2 as Lang.Float) as Lang.Float {
        var R = 6371000.0f;
        var toR = Math.PI.toFloat() / 180.0f;
        var dLat = (lat2 - lat1) * toR;
        var dLon = (lon2 - lon1) * toR;
        var a = Math.sin(dLat/2.0f)*Math.sin(dLat/2.0f) + Math.cos(lat1*toR)*Math.cos(lat2*toR)*Math.sin(dLon/2.0f)*Math.sin(dLon/2.0f);
        return R * 2.0f * Math.atan2(Math.sqrt(a), Math.sqrt(1.0f - a)).toFloat();
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
                var d = distance(devLat, devLon, _lastCalcLat, _lastCalcLon);
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
        drawHeader(dc, screenW);
        drawCards(dc, screenW, devLat, devLon);
        drawFooter(dc, screenW, screenH, posInfo);
    }

    private function drawHeader(dc as Graphics.Dc, screenW as Lang.Number) as Void {
        dc.setColor(COLOR_PANEL, COLOR_PANEL);
        dc.fillRectangle(0, 0, screenW, 40);
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
        dc.drawText(8, 10, Graphics.FONT_MEDIUM, "PICS", Graphics.TEXT_JUSTIFY_LEFT);

        dc.setColor(statusColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(screenW - 8, 10, Graphics.FONT_MEDIUM,
                    WatchUi.loadResource(statusLabel) as Lang.String,
                    Graphics.TEXT_JUSTIFY_RIGHT);

        dc.setColor(COLOR_BORDER, COLOR_BORDER);
        dc.fillRectangle(0, 40, screenW, 2);
    }

    private function drawCards(dc as Graphics.Dc, screenW as Lang.Number, devLat as Lang.Float, devLon as Lang.Float) as Void {
        var cardsData = [] as Lang.Array;
        
        var activeIntersectionId = null;
        var activeSigs = [] as Lang.Array;
        var frameRssi = null;
        if (_lastFrame != null) {
            var frame = _lastFrame as PicsFrame;
            var nowTimer = System.getTimer();
            if (_lastReceivedSysTime > 0 && (nowTimer - _lastReceivedSysTime) <= 5000) {
                activeIntersectionId = frame.intersectionId;
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
                    "rssi" => rssiVal,
                    "signals" => sigs
                };
                cardsData.add(cardItem);
            }
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
        var y = 46;

        dc.setClip(0, 42, screenW, 350);

        for (var i = _currentRowOffset; i < cardsData.size(); i++) {
            if (y > 380) { break; }
            var item = cardsData[i] as Lang.Dictionary;
            var sigs = item["signals"] as Lang.Array;
            var cardH = calculateCardHeight(item, sigs);
            
            drawSingleCard(dc, 8, y, screenW - 16, cardH, item);
            y += cardH + gap;
        }

        dc.clearClip();
    }

    private function calculateCardHeight(item as Lang.Dictionary, sigs as Lang.Array) as Lang.Number {
        var addr = item["addr"] as Lang.String;
        var hira = item["hira"] as Lang.String;
        
        var wrappedAddr = wrapText(addr, 14);
        var wrappedHira = wrapText(hira, 18);
        
        var staticH = 6 + 28 + (20 * wrappedAddr.size()) + (16 * wrappedHira.size()) + 18 + 4;
        
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
        var hira = item["hira"] as Lang.String;
        var addr = item["addr"] as Lang.String;
        var latVal = item["lat"] as Lang.Float;
        var lonVal = item["lon"] as Lang.Float;
        var dist = item["dist"] as Lang.Float;
        var brg = item["brg"] as Lang.Float;
        var id = item["id"] as Lang.String;
        var rssi = item["rssi"];
        var sigs = item["signals"] as Lang.Array;

        var cy = y + 6;

        // 1. 交差点名（大きな文字）
        dc.setColor(COLOR_TEXT_MAIN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + 8, cy, Graphics.FONT_MEDIUM, name, Graphics.TEXT_JUSTIFY_LEFT);
        cy += 28;

        // 2. 所在地（中くらいの文字、折り返し）
        dc.setColor(COLOR_TEXT_SUB, Graphics.COLOR_TRANSPARENT);
        var wrappedAddr = wrapText(addr, 14);
        for (var i = 0; i < wrappedAddr.size(); i++) {
            dc.drawText(x + 8, cy, Graphics.FONT_SMALL, wrappedAddr[i] as Lang.String, Graphics.TEXT_JUSTIFY_LEFT);
            cy += 20;
        }

        // 3. よみがな（小さい文字、折り返し）
        dc.setColor(COLOR_TEXT_SUB, Graphics.COLOR_TRANSPARENT);
        var wrappedHira = wrapText(hira, 18);
        for (var i = 0; i < wrappedHira.size(); i++) {
            dc.drawText(x + 8, cy, Graphics.FONT_TINY, wrappedHira[i] as Lang.String, Graphics.TEXT_JUSTIFY_LEFT);
            cy += 16;
        }

        // 4. 信号機の緯度経度（小さい文字）
        var latStr = latVal.format("%.4f");
        var lonStr = lonVal.format("%.4f");
        dc.setColor(COLOR_TEXT_SUB, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + 8, cy, Graphics.FONT_TINY, "Lat: " + latStr + " Lon: " + lonStr, Graphics.TEXT_JUSTIFY_LEFT);
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
        
        // 信号の丸（大きな丸、左寄せ）：大きさ・Y軸中心位置を数字に合わせる
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x + 20, sy + 16, 16);

        // カウント（大きな文字、中央寄せ）：大きさ・Y軸中心位置を丸に合わせる
        dc.setColor(COLOR_TEXT_MAIN, Graphics.COLOR_TRANSPARENT);
        var countStr = "--";
        if (state != SIGNAL_NO_SIGNAL && remaining >= 0) {
            countStr = remaining.toString();
        }
        dc.drawText(x + w / 2, sy + 16, Graphics.FONT_LARGE, countStr, 
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // 電波の強さ（小さな文字、右寄せ）：Y軸中心位置を揃える
        dc.setColor(COLOR_TEXT_SUB, Graphics.COLOR_TRANSPARENT);
        var dbmStr = (rssi != null) ? (rssi.toString() + " dBm") : "-- dBm";
        dc.drawText(x + w - 12, sy + 16, Graphics.FONT_TINY, dbmStr, 
                    Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);

        var cards = ["N","NE","E","SE","S","SW","W","NW"] as Array<String>;
        var cidx  = ((brg + 22.5f) / 45.0f).toNumber() % 8;
        var distBrgStr = dist.format("%.0f") + "m  " + brg.format("%.0f") + " (" + cards[cidx] + ")";

        dc.setColor(COLOR_ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + w / 2, sy + 32, Graphics.FONT_SMALL, distBrgStr, Graphics.TEXT_JUSTIFY_CENTER);
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
    private function drawFooter(dc as Graphics.Dc, screenW as Lang.Number, screenH as Lang.Number, posInfo as Position.Info or Null) as Void {
        var CX = screenW / 2;

        dc.setColor(COLOR_BORDER, COLOR_BORDER);
        dc.fillRectangle(0, 396, screenW, 2);

        dc.setColor(COLOR_PANEL, COLOR_PANEL);
        dc.fillRectangle(0, 398, screenW, screenH - 398);

        var timeStr = WatchUi.loadResource(Rez.Strings.WaitingDots) as Lang.String;
        if (_lastReceivedTime.length() > 0) {
            timeStr = _lastReceivedTime;
        }

        // 1行目: 受信時刻 と パケット数
        dc.setColor(COLOR_TEXT_MAIN, Graphics.COLOR_TRANSPARENT);
        var info1 = timeStr + "    " + _rxCount.toString() + " pkt";
        dc.drawText(CX, 400, Graphics.FONT_TINY, info1, Graphics.TEXT_JUSTIFY_CENTER);

        // 2行目: 緯度・経度
        var latStr = "--";
        var lonStr = "--";
        var altStr = "--";
        var spdStr = "--";

        if (_emulatorModeActive) {
            latStr = "43.0668";
            lonStr = "141.3506";
            altStr = "18m";
            spdStr = "0.0km/h";
        } else if (posInfo != null) {
            var info = posInfo as Position.Info;
            if (info.position != null) {
                var coords = (info.position as Position.Location).toDegrees();
                latStr = coords[0].format("%.4f");
                lonStr = coords[1].format("%.4f");
            }
            if (info.altitude != null) {
                altStr = info.altitude.format("%.0f") + "m";
            }
            if (info.speed != null) {
                var spdKmH = info.speed * 3.6f;
                spdStr = spdKmH.format("%.1f") + "km/h";
            }
        }

        dc.setColor(COLOR_TEXT_SUB, Graphics.COLOR_TRANSPARENT);
        dc.drawText(CX, 420, Graphics.FONT_TINY, "Lat:" + latStr + " Lon:" + lonStr, Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(CX, 440, Graphics.FONT_TINY, "Alt:" + altStr + " Spd:" + spdStr,
                    Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(COLOR_ACCENT, COLOR_ACCENT);
        dc.fillRectangle(0, screenH - 3, screenW, 3);
    }
}

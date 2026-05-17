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

//! @brief 信号インジケータ1つ分の描画パラメータ
class SignalIndicator {
    var x     as Lang.Number;
    var y     as Lang.Number;
    var label as Lang.String;

    function initialize(x_ as Lang.Number, y_ as Lang.Number, label_ as Lang.String) {
        x = x_;
        y = y_;
        label = label_;
    }
}

class PicsMainView extends WatchUi.View {

    // ---- 表示チャンネル設定（動的リストになったため廃止） ----

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
    private var _intersectionLat  as Lang.Float  = 0.0f;
    private var _intersectionLon  as Lang.Float  = 0.0f;
    private var _currentRowOffset as Lang.Number = 0;

    function initialize() {
        View.initialize();
    }

    function onLayout(dc as Graphics.Dc) as Void {
    }

    //! 外部から呼ばれる：信号状態を更新して再描画を要求
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
        _intersectionLat  = intersectionLat;
        _intersectionLon  = intersectionLon;
        WatchUi.requestUpdate();
    }

    //! スキャン状態を反映
    function setScanningState(scanning as Lang.Boolean) as Void {
        _scanning = scanning;
        WatchUi.requestUpdate();
    }

    //! 点滅フェーズを外部タイマーから更新（500ms 間隔想定）
    function toggleBlinkPhase() as Void {
        _blinkPhase = !_blinkPhase;
        if (_lastFrame != null) { WatchUi.requestUpdate(); }
    }

    //! 下にスクロール
    function scrollDown() as Void {
        _currentRowOffset += 2;
        WatchUi.requestUpdate();
    }

    //! 上にスクロール
    function scrollUp() as Void {
        _currentRowOffset -= 2;
        if (_currentRowOffset < 0) { _currentRowOffset = 0; }
        WatchUi.requestUpdate();
    }

    //! 受信時刻やGPSなど時間依存表示を短周期で更新
    function refreshRealtime() as Void {
        if (_scanning || _lastFrame != null) { WatchUi.requestUpdate(); }
    }

    //! 画面全体を描画する
    function onUpdate(dc as Graphics.Dc) as Void {
        var screenW = dc.getWidth();
        var screenH = dc.getHeight();

        dc.setColor(COLOR_BG, COLOR_BG);
        dc.clear();

        drawHeader(dc, screenW);
        drawSignalPanels(dc, screenW);
        drawGpsInfo(dc, screenW);
        drawFooter(dc, screenW, screenH);
    }

    // ----------------------------------------------------------
    //  ヘッダー部  Y: 0 ～ 76
    // ----------------------------------------------------------
    private function drawHeader(dc as Graphics.Dc, screenW as Lang.Number) as Void {
        var CX = screenW / 2;

        dc.setColor(COLOR_PANEL, COLOR_PANEL);
        dc.fillRectangle(0, 0, screenW, 76);

        dc.setColor(COLOR_ACCENT, COLOR_ACCENT);
        dc.fillRectangle(0, 0, screenW, 3);

        // 交差点名称
        var nameFont = Graphics.FONT_MEDIUM;
        var nameStr  = "";
        if (_intersectionName.length() > 0) {
            nameStr  = _intersectionName;
            nameFont = Graphics.FONT_SMALL;
        } else {
            var intersectionId = (_lastFrame != null)
                ? _lastFrame.intersectionId
                : "--------";
            nameStr = WatchUi.loadResource(Rez.Strings.IntersectionPrefix) + intersectionId;
        }
        dc.setColor(COLOR_TEXT_MAIN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(CX, 16, nameFont, nameStr, Graphics.TEXT_JUSTIFY_CENTER);

        // スキャン状態
        var receiving = _scanning || _lastFrame != null;
        var statusColor = COLOR_NONE;
        var statusLabel = Rez.Strings.StoppedIndicator;

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
        dc.drawText(CX, 55, Graphics.FONT_TINY,
                    WatchUi.loadResource(statusLabel) as Lang.String,
                    Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(COLOR_BORDER, COLOR_BORDER);
        dc.fillRectangle(0, 76, screenW, 2);
    }

    // ----------------------------------------------------------
    //  信号パネル  Y: 80 ～ 330
    // ----------------------------------------------------------
    private function drawSignalPanels(dc as Graphics.Dc, screenW as Lang.Number) as Void {
        var validSignals = [] as Lang.Array;
        if (_lastFrame != null) {
            var sigs = _lastFrame.signals as Lang.Array;
            for (var i = 0; i < sigs.size(); i++) {
                var sig = sigs[i] as PicsSignal;
                if (sig.state != SIGNAL_NO_SIGNAL) {
                    validSignals.add(sig);
                }
            }
        }

        var numPanels = validSignals.size();
        var maxRow = (numPanels > 0) ? ((numPanels - 1) / 2) : 0;
        
        var maxOffset = maxRow - 2; 
        if (maxOffset < 0) { maxOffset = 0; }
        if (_currentRowOffset > maxOffset) { _currentRowOffset = maxOffset; }
        if (_currentRowOffset < 0) { _currentRowOffset = 0; }

        var panelW = (screenW - 24) / 2;
        var panelH = 78;
        var gapX   = 8;
        var gapY   = 8;
        var startX = 8;
        var startY = 80 - (_currentRowOffset * (panelH + gapY));

        dc.setClip(0, 78, screenW, 256);

        for (var c = 0; c < numPanels; c++) {
            var col = c % 2;
            var row = c / 2;
            var px  = startX + col * (panelW + gapX);
            var py  = startY + row * (panelH + gapY);

            if (py + panelH < 78 || py > 334) {
                continue;
            }

            var signal = validSignals[c] as PicsSignal;
            drawSinglePanel(dc, px, py, panelW, panelH, c, signal);
        }

        dc.clearClip();
    }

    //! 1チャンネル分のパネルを描画
    private function drawSinglePanel(
        dc     as Graphics.Dc,
        x      as Lang.Number,
        y      as Lang.Number,
        w      as Lang.Number,
        h      as Lang.Number,
        channel as Lang.Number,
        signal as PicsSignal or Null
    ) as Void {
        dc.setColor(COLOR_PANEL, COLOR_PANEL);
        dc.fillRectangle(x, y, w, h);
        dc.setColor(COLOR_BORDER, COLOR_BORDER);
        dc.drawRectangle(x, y, w, h);

        dc.setColor(COLOR_ACCENT, Graphics.COLOR_TRANSPARENT);
        var txId = "--------";
        if (_lastFrame != null) {
            txId = _lastFrame.transmitterId;
        }
        dc.drawText(x + 6, y + 4, Graphics.FONT_TINY,
                    txId,
                    Graphics.TEXT_JUSTIFY_LEFT);

        if (signal != null && _lastFrame != null) {
            dc.setColor(COLOR_TEXT_SUB, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x + w - 6, y + h - 18, Graphics.FONT_TINY,
                        _lastFrame.rssi.toString() + "dBm",
                        Graphics.TEXT_JUSTIFY_RIGHT);
        }

        var lampR  = 16;
        var lampCY = y + 42;
        var lampCX = x + 28;

        var sigColor  = COLOR_NONE;
        var remText   = "" as Lang.String;

        if (signal != null) {
            remText   = (signal.remaining > 0)
                ? signal.remaining.toString()
                : "";

            switch (signal.state) {
                case SIGNAL_RED:
                    sigColor = COLOR_RED;
                    break;
                case SIGNAL_GREEN:
                    sigColor = COLOR_GREEN;
                    break;
                case SIGNAL_BLINK_GREEN:
                    sigColor = _blinkPhase ? COLOR_BLINK_G : COLOR_NONE;
                    break;
                case SIGNAL_NONE:
                    sigColor = COLOR_NONE;
                    break;
                default:
                    sigColor = COLOR_NONE;
                    break;
            }
        }

        if (signal != null && signal.state != SIGNAL_NO_SIGNAL) {
            dc.setColor(sigColor & 0x3F3F3F, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(lampCX, lampCY, lampR + 3);
        }

        dc.setColor(sigColor, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(lampCX, lampCY, lampR);

        if (remText.length() > 0) {
            dc.setColor(COLOR_TEXT_SUB, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x + 52, y + 40, Graphics.FONT_TINY,
                        WatchUi.loadResource(Rez.Strings.RemainingPrefix) + remText,
                        Graphics.TEXT_JUSTIFY_LEFT);
        }
    }

    // ----------------------------------------------------------
    //  GPS 情報  Y: 334 ～ 378
    // ----------------------------------------------------------
    private function drawGpsInfo(dc as Graphics.Dc, screenW as Lang.Number) as Void {
        var CX = screenW / 2;

        var devLat = 0.0f;
        var devLon = 0.0f;
        var hasFix = false;
        var posInfo = Position.getInfo();
        if (posInfo != null && posInfo.position != null) {
            var coords = (posInfo.position as Position.Location).toDegrees();
            devLat = coords[0].toFloat();
            devLon = coords[1].toFloat();
            hasFix = true;
        }

        var hasInt = (_intersectionName.length() > 0);

        // デバイス座標
        var devLatStr = hasFix ? (devLat.abs().format("%.4f") + (devLat >= 0.0f ? "N" : "S")) : "--";
        var devLonStr = hasFix ? (devLon.abs().format("%.4f") + (devLon >= 0.0f ? "E" : "W")) : "--";
        dc.setColor(COLOR_TEXT_SUB, Graphics.COLOR_TRANSPARENT);
        dc.drawText(CX, 332, Graphics.FONT_TINY,
                    WatchUi.loadResource(Rez.Strings.DevicePrefix) + devLatStr + " " + devLonStr,
                    Graphics.TEXT_JUSTIFY_CENTER);

        // 交差点座標
        var intLatStr = hasInt ? (_intersectionLat.abs().format("%.4f") + (_intersectionLat >= 0.0f ? "N" : "S")) : "--";
        var intLonStr = hasInt ? (_intersectionLon.abs().format("%.4f") + (_intersectionLon >= 0.0f ? "E" : "W")) : "--";
        dc.setColor(COLOR_TEXT_SUB, Graphics.COLOR_TRANSPARENT);
        dc.drawText(CX, 348, Graphics.FONT_TINY,
                    WatchUi.loadResource(Rez.Strings.IntersectionCoordPrefix) + intLatStr + " " + intLonStr,
                    Graphics.TEXT_JUSTIFY_CENTER);

        // 距離・方位
        var distBrgStr = "--";
        if (hasFix && hasInt) {
            var R    = 6371000.0f;
            var phi1 = devLat * (Math.PI / 180.0f);
            var phi2 = _intersectionLat * (Math.PI / 180.0f);
            var dPhi = (_intersectionLat - devLat) * (Math.PI / 180.0f);
            var dLam = (_intersectionLon - devLon) * (Math.PI / 180.0f);
            var sinH = Math.sin(dPhi / 2.0f);
            var sinL = Math.sin(dLam / 2.0f);
            var a    = sinH * sinH + Math.cos(phi1) * Math.cos(phi2) * sinL * sinL;
            var dist = R * 2.0f * Math.atan2(Math.sqrt(a), Math.sqrt(1.0f - a));

            var vy   = Math.sin(dLam) * Math.cos(phi2);
            var vx   = Math.cos(phi1) * Math.sin(phi2)
                     - Math.sin(phi1) * Math.cos(phi2) * Math.cos(dLam);
            var brg  = Math.toDegrees(Math.atan2(vy, vx)).toFloat();
            brg = brg + 360.0f;
            if (brg >= 360.0f) { brg = brg - 360.0f; }

            var cards = ["N","NE","E","SE","S","SW","W","NW"] as Array<String>;
            var cidx  = ((brg + 22.5f) / 45.0f).toNumber() % 8;

            distBrgStr = dist.format("%.0f") + "m  " + brg.format("%.0f") + "(" + cards[cidx] + ")";
        }
        dc.setColor(COLOR_ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(CX, 364, Graphics.FONT_TINY,
                    WatchUi.loadResource(Rez.Strings.DistancePrefix) + distBrgStr,
                    Graphics.TEXT_JUSTIFY_CENTER);
    }

    // ----------------------------------------------------------
    //  フッター  Y: 382 ～ 470
    // ----------------------------------------------------------
    private function drawFooter(dc as Graphics.Dc, screenW as Lang.Number, screenH as Lang.Number) as Void {
        var CX = screenW / 2;

        dc.setColor(COLOR_BORDER, COLOR_BORDER);
        dc.fillRectangle(0, 380, screenW, 2);

        dc.setColor(COLOR_PANEL, COLOR_PANEL);
        dc.fillRectangle(0, 382, screenW, screenH - 382);

        // 最終受信時刻
        var timeStr = WatchUi.loadResource(Rez.Strings.WaitingDots) as Lang.String;
        if (_lastReceivedTime.length() > 0) {
            timeStr = _lastReceivedTime;
        }

        dc.setColor(COLOR_TEXT_MAIN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(CX, 388, Graphics.FONT_TINY,
                    WatchUi.loadResource(Rez.Strings.LastReceivedPrefix) + timeStr,
                    Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(COLOR_TEXT_SUB, Graphics.COLOR_TRANSPARENT);
        dc.drawText(CX, 412, Graphics.FONT_TINY,
                    WatchUi.loadResource(Rez.Strings.PacketCountPrefix) + _rxCount.toString() + " pkt",
                    Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(COLOR_TEXT_SUB, Graphics.COLOR_TRANSPARENT);
        dc.drawText(CX, 442, Graphics.FONT_TINY,
                    WatchUi.loadResource(Rez.Strings.BackHint) as Lang.String,
                    Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(COLOR_ACCENT, COLOR_ACCENT);
        dc.fillRectangle(0, screenH - 3, screenW, 3);
    }
}

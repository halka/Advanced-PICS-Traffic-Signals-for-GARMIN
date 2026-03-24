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

    // ---- 画面サイズ定数 (GPSMAP H1i Plus) ----
    private const SCREEN_W = 282;
    private const SCREEN_H = 470;

    // ---- 表示チャンネル設定 ----
    // PICS は最大6系統だが、一般的な交差点は東西(0)/南北(1)の2系統
    // 将来的にスクロールで全6系統を見られるよう配列で管理
    private const DISPLAY_CHANNELS = [0, 1] as Array<Number>;
    private const CHANNEL_LABELS   = ["東西", "南北"] as Array<String>;

    // ---- カラーパレット ----
    private const COLOR_BG         = 0x1A1A2E;  // 深夜ネイビー
    private const COLOR_PANEL      = 0x16213E;  // パネル背景
    private const COLOR_BORDER     = 0x0F3460;  // ボーダー
    private const COLOR_ACCENT     = 0x00D4FF;  // シアンアクセント
    private const COLOR_TEXT_MAIN  = 0xECECEC;  // 本文
    private const COLOR_TEXT_SUB   = 0x7A8BA0;  // サブテキスト

    private const COLOR_RED        = 0xFF2D2D;
    private const COLOR_GREEN      = 0x00E676;
    private const COLOR_BLINK_G    = 0xFFEA00;  // 点滅青 → 黄で表現
    private const COLOR_NONE       = 0x455A64;  // 制御外 → グレー

    // ---- ステート ----
    private var _lastFrame        as PicsFrame or Null = null;
    private var _rxCount          as Lang.Long = 0l;
    private var _scanning         as Lang.Boolean = false;
    private var _blinkPhase       as Lang.Boolean = false;  // 点滅アニメ用
    private var _intersectionName as Lang.String = "";      // GPS解決済み交差点名
    private var _intersectionLat  as Lang.Float  = 0.0f;   // 最近傍交差点の緯度
    private var _intersectionLon  as Lang.Float  = 0.0f;   // 最近傍交差点の経度

    function initialize() {
        View.initialize();
    }

    function onLayout(dc as Graphics.Dc) as Void {
        // レイアウトXMLは使わず、全て onUpdate() でコード描画
    }

    //! 外部から呼ばれる：信号状態を更新して再描画を要求
    function updateSignal(frame as PicsFrame, rxCount as Lang.Long,
                          intersectionName as Lang.String,
                          intersectionLat  as Lang.Float,
                          intersectionLon  as Lang.Float) as Void {
        _lastFrame        = frame;
        _rxCount          = rxCount;
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

    //! 画面全体を描画する
    function onUpdate(dc as Graphics.Dc) as Void {
        // 背景クリア
        dc.setColor(COLOR_BG, COLOR_BG);
        dc.clear();

        drawHeader(dc);
        drawSignalPanels(dc);
        drawGpsInfo(dc);
        drawFooter(dc);
    }

    // ----------------------------------------------------------
    //  ヘッダー部（交差点ID / スキャン状態）
    //  Y: 0 ～ 80
    // ----------------------------------------------------------
    private function drawHeader(dc as Graphics.Dc) as Void {
        var CX = SCREEN_W / 2;

        // 帯背景
        dc.setColor(COLOR_PANEL, COLOR_PANEL);
        dc.fillRectangle(0, 0, SCREEN_W, 72);

        // 上部アクセントライン
        dc.setColor(COLOR_ACCENT, COLOR_ACCENT);
        dc.fillRectangle(0, 0, SCREEN_W, 3);

        // アプリタイトル
        dc.setColor(COLOR_ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(CX, 10, Graphics.FONT_XTINY,
                    "高度化PICS モニタ",
                    Graphics.TEXT_JUSTIFY_CENTER);

        // 交差点名称（GPS解決済みなら名前、未解決なら16進ID）
        var nameStr  = "";
        var nameFont = Graphics.FONT_SMALL;
        if (_intersectionName.length() > 0) {
            nameStr  = _intersectionName;
            nameFont = Graphics.FONT_XTINY;
        } else {
            var intersectionId = (_lastFrame != null)
                ? _lastFrame.intersectionId
                : "--------";
            nameStr  = "交差点: " + intersectionId;
        }
        dc.setColor(COLOR_TEXT_MAIN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(CX, 30, nameFont, nameStr, Graphics.TEXT_JUSTIFY_CENTER);

        // スキャン状態インジケータ
        var statusColor = _scanning ? COLOR_GREEN : COLOR_NONE;
        var statusLabel = _scanning ? "● スキャン中" : "○ 停止中";
        dc.setColor(statusColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(CX, 52, Graphics.FONT_XTINY,
                    statusLabel,
                    Graphics.TEXT_JUSTIFY_CENTER);

        // セパレータ
        dc.setColor(COLOR_BORDER, COLOR_BORDER);
        dc.fillRectangle(0, 72, SCREEN_W, 2);
    }

    // ----------------------------------------------------------
    //  信号パネル（東西 / 南北）
    //  Y: 80 ～ 380
    // ----------------------------------------------------------
    private function drawSignalPanels(dc as Graphics.Dc) as Void {
        var panelW  = (SCREEN_W - 24) / 2;  // 左右余白12px + 中央8px
        var panelH  = 250;
        var panelY  = 80;
        var panelX0 = 8;
        var panelX1 = panelX0 + panelW + 8;

        for (var c = 0; c < DISPLAY_CHANNELS.size(); c++) {
            var ch    = DISPLAY_CHANNELS[c];
            var px    = (c == 0) ? panelX0 : panelX1;
            var label = CHANNEL_LABELS[c];

            var signal = null as PicsSignal or Null;
            if (_lastFrame != null && _lastFrame.msgType == PICS_MSG_TYPE_SIGNAL) {
                signal = _lastFrame.signals[ch] as PicsSignal;
            }

            drawSinglePanel(dc, px, panelY, panelW, panelH, label, signal);
        }
    }

    //! 1チャンネル分のパネルを描画
    private function drawSinglePanel(
        dc       as Graphics.Dc,
        x        as Lang.Number,
        y        as Lang.Number,
        w        as Lang.Number,
        h        as Lang.Number,
        label    as Lang.String,
        signal   as PicsSignal or Null
    ) as Void {
        var cx = x + w / 2;

        // パネル背景（角丸風に4角を暗くして擬似角丸）
        dc.setColor(COLOR_PANEL, COLOR_PANEL);
        dc.fillRectangle(x, y, w, h);
        dc.setColor(COLOR_BORDER, COLOR_BORDER);
        dc.drawRectangle(x, y, w, h);

        // チャンネルラベル
        dc.setColor(COLOR_ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y + 10, Graphics.FONT_SMALL,
                    label,
                    Graphics.TEXT_JUSTIFY_CENTER);

        // ----  信号ランプ  ----
        var lampR = 44;  // 半径
        var lampCY = y + 100;

        var sigColor  = COLOR_NONE;
        var stateText = "---";
        var remText   = "--";

        if (signal != null) {
            stateText = signal.stateLabel();
            remText   = (signal.remaining > 0)
                ? signal.remaining.toString() + "s"
                : "--";

            switch (signal.state) {
                case SIGNAL_RED:
                    sigColor = COLOR_RED;
                    break;
                case SIGNAL_GREEN:
                    sigColor = COLOR_GREEN;
                    break;
                case SIGNAL_BLINK_GREEN:
                    // 点滅はフェーズに応じて緑 / 暗
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

        // 外枠（グロー風 ― 大きいほど外側）
        if (signal != null && signal.state != SIGNAL_NO_SIGNAL) {
            dc.setColor(sigColor & 0x3F3F3F, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(cx, lampCY, lampR + 6);
        }

        // ランプ本体
        dc.setColor(sigColor, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx, lampCY, lampR);

        // ランプ内ハイライト（上部1/3を明るく）
        dc.setColor(0xFFFFFF & 0x303030, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx - 8, lampCY - 10, lampR / 3);

        // 状態テキスト（ランプ下）
        dc.setColor(COLOR_TEXT_MAIN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y + 160, Graphics.FONT_SMALL,
                    stateText,
                    Graphics.TEXT_JUSTIFY_CENTER);

        // 残り時間
        dc.setColor(COLOR_TEXT_SUB, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y + 185, Graphics.FONT_XTINY,
                    "残り " + remText,
                    Graphics.TEXT_JUSTIFY_CENTER);

        // 下部 RSSI（右パネルのみ）
        if (signal != null && _lastFrame != null) {
            var rssiStr = "RSSI: " + _lastFrame.rssi.toString() + " dBm";
            dc.setColor(COLOR_TEXT_SUB, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, y + 210, Graphics.FONT_XTINY,
                        rssiStr,
                        Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    // ----------------------------------------------------------
    //  GPS 情報（デバイス座標 / 交差点座標 / 距離・方位）
    //  Y: 334 ～ 378
    // ----------------------------------------------------------
    private function drawGpsInfo(dc as Graphics.Dc) as Void {
        var CX = SCREEN_W / 2;

        // デバイスの現在GPS座標を取得
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

        var hasInt = (_intersectionName.length() > 0);

        // ---- デバイス座標 ----
        var devLatStr = hasFix ? (devLat.abs().format("%.4f") + (devLat >= 0.0f ? "N" : "S")) : "--";
        var devLonStr = hasFix ? (devLon.abs().format("%.4f") + (devLon >= 0.0f ? "E" : "W")) : "--";
        dc.setColor(COLOR_TEXT_SUB, Graphics.COLOR_TRANSPARENT);
        dc.drawText(CX, 336, Graphics.FONT_XTINY,
                    "デバイス: " + devLatStr + " " + devLonStr,
                    Graphics.TEXT_JUSTIFY_CENTER);

        // ---- 交差点座標 ----
        var intLatStr = hasInt ? (_intersectionLat.abs().format("%.4f") + (_intersectionLat >= 0.0f ? "N" : "S")) : "--";
        var intLonStr = hasInt ? (_intersectionLon.abs().format("%.4f") + (_intersectionLon >= 0.0f ? "E" : "W")) : "--";
        dc.setColor(COLOR_TEXT_SUB, Graphics.COLOR_TRANSPARENT);
        dc.drawText(CX, 352, Graphics.FONT_XTINY,
                    "交差点:   " + intLatStr + " " + intLonStr,
                    Graphics.TEXT_JUSTIFY_CENTER);

        // ---- 距離・方位 ----
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

            var y    = Math.sin(dLam) * Math.cos(phi2);
            var x    = Math.cos(phi1) * Math.sin(phi2)
                     - Math.sin(phi1) * Math.cos(phi2) * Math.cos(dLam);
            var brg  = Math.toDegrees(Math.atan2(y, x));
            brg = ((brg + 360.0f) % 360.0f);

            var cards = ["N","NE","E","SE","S","SW","W","NW"] as Array<String>;
            var cidx  = ((brg + 22.5f) / 45.0f).toNumber() % 8;

            distBrgStr = dist.format("%.0f") + "m  " + brg.format("%.0f") + "°(" + cards[cidx] + ")";
        }
        dc.setColor(COLOR_ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(CX, 368, Graphics.FONT_XTINY,
                    "距離: " + distBrgStr,
                    Graphics.TEXT_JUSTIFY_CENTER);
    }

    // ----------------------------------------------------------
    //  フッター（最終受信時刻 / パケット数 / 操作ヒント）
    //  Y: 385 ～ 470
    // ----------------------------------------------------------
    private function drawFooter(dc as Graphics.Dc) as Void {
        var CX = SCREEN_W / 2;

        // セパレータ
        dc.setColor(COLOR_BORDER, COLOR_BORDER);
        dc.fillRectangle(0, 380, SCREEN_W, 2);

        // フッター背景
        dc.setColor(COLOR_PANEL, COLOR_PANEL);
        dc.fillRectangle(0, 382, SCREEN_W, SCREEN_H - 382);

        // 最終受信時刻
        var timeStr = "受信待ち...";
        if (_lastFrame != null) {
            // System.getTimer() は ms 単位のアップタイム
            // 絶対時刻が必要な場合は Gregorian.info() を使う
            var now  = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
            timeStr  = now.hour.format("%02d") + ":"
                     + now.min.format("%02d")  + ":"
                     + now.sec.format("%02d");
        }

        dc.setColor(COLOR_TEXT_MAIN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(CX, 390, Graphics.FONT_XTINY,
                    "最終受信: " + timeStr,
                    Graphics.TEXT_JUSTIFY_CENTER);

        // パケットカウンタ
        dc.setColor(COLOR_TEXT_SUB, Graphics.COLOR_TRANSPARENT);
        dc.drawText(CX, 412, Graphics.FONT_XTINY,
                    "受信数: " + _rxCount.toString() + " pkt",
                    Graphics.TEXT_JUSTIFY_CENTER);

        // 操作ヒント
        dc.setColor(COLOR_TEXT_SUB, Graphics.COLOR_TRANSPARENT);
        dc.drawText(CX, 440, Graphics.FONT_XTINY,
                    "BACK で終了",
                    Graphics.TEXT_JUSTIFY_CENTER);

        // 下部アクセントライン
        dc.setColor(COLOR_ACCENT, COLOR_ACCENT);
        dc.fillRectangle(0, SCREEN_H - 3, SCREEN_W, 3);
    }
}

// 0-Space shell: the Dome, the ring, the script, thought-speak, the
// launcher (Super+Space) and the level display for volume and brightness.
// Started by the session as: quickshell -p <this file>
//
// Everything here is drawn, so the desktop looks like 0-Space even before
// any art exists. Your own art can replace the Dome: put it in
// ~/.local/share/0space/art/dome.png (or /usr/share/0space/art/dome.png).

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import Quickshell.Services.UPower
import Quickshell.Services.Pipewire

ShellRoot {
    id: root

    // Andalite palette.
    readonly property color skyHigh: "#071226"
    readonly property color skyLow: "#2a1f4a"
    readonly property color horizon: "#7a4a7c"
    readonly property color grassDark: "#0c2a33"
    readonly property color grassLight: "#14454d"
    readonly property color furBlue: "#6aa2d8"
    readonly property color furTan: "#d8c29a"
    readonly property color treePink: "#d46fa0"
    readonly property color treeRed: "#b8434f"
    readonly property color treeBlue: "#4c7fd0"
    readonly property color glass: "#9fd4ff"
    readonly property string userArt: Quickshell.env("HOME") + "/.local/share/0space/art/dome.png"
    readonly property string systemArt: Quickshell.env("ZEROSPACE_DOME") || "/usr/share/0space/art/dome.png"

    readonly property color hull: "#0b1630"
    readonly property color lineColour: "#24365a"

    // ------------------------------------------------------------ the script
    // The Andalite script is a real font (art/0space-script.ttf, built by
    // tools/make-script-font.py): write English in it and it comes out alien.
    readonly property string scriptFont: "0-Space Script"

    component Script: Text {
        property real glyph: 10           // height of the letter body, in pixels
        property color ink: root.furTan
        color: ink
        font.family: root.scriptFont
        font.pixelSize: Math.round(glyph / 0.54)
        renderType: Text.NativeRendering
    }

    // One line, Andalite then English: <script>/English
    component Translated: Row {
        id: tr
        property string text: ""
        property string scriptText: text   // the Andalite half; shorter for long lines
        property real glyph: 8
        property color scriptInk: root.glass
        property color ink: root.furTan
        property int size: 13
        property real letterSpacing: 0
        property bool upper: false
        property string before: ""
        property string after: ""
        property bool outlined: false
        property real maxWidth: 0          // 0: as wide as it needs; else the English is cut with …
        spacing: 0
        TranslatedPlain { id: trBefore; row: tr; text: tr.before; visible: text !== "" }
        Script {
            id: trScript
            text: tr.scriptText.toLowerCase()
            glyph: tr.glyph
            ink: tr.scriptInk
            style: tr.outlined ? Text.Outline : Text.Normal
            styleColor: root.skyHigh
            anchors.verticalCenter: parent.verticalCenter
        }
        TranslatedPlain {
            row: tr
            text: "/" + (tr.upper ? tr.text.toUpperCase() : tr.text)
            elide: Text.ElideRight
            width: tr.maxWidth > 0
                ? Math.min(implicitWidth, tr.maxWidth - trBefore.width - trScript.width - trAfter.width)
                : implicitWidth
        }
        TranslatedPlain { id: trAfter; row: tr; text: tr.after; visible: text !== "" }
    }

    // ------------------------------------------------------------ corners
    // Glass pills in the corners of each screen: workstations top left, the
    // time top right, the tray, network, sound and battery bottom right. They
    // tuck away while you work and come back when the pointer touches their
    // corner, when the workstation is empty, in the overview, or on Super+B.
    readonly property string artDir: Quickshell.env("ZEROSPACE_ART") || "/usr/share/0space/art"
    // The Dome, frosted: each pill shows the patch of it that lies behind it.
    readonly property string glassArt: "file://" + (Quickshell.env("ZEROSPACE_GLASS") || artDir + "/dome-glass.png")
    property bool cornersPinned: false

    IpcHandler {
        target: "corners"
        function toggle(): void { root.cornersPinned = !root.cornersPinned }
    }

    component Pill: Item {
        id: pill
        default property alias content: inner.data
        property var corner: null       // the Corner it sits in, to line up the glass
        property bool lit: false        // glowing: the current workstation, a warning
        property color edgeColour: root.glass
        property int pad: 13
        readonly property bool hovered: hover.hovered
        signal clicked(var mouse)
        signal scrolled(var wheel)

        implicitHeight: 34
        implicitWidth: inner.implicitWidth + pad * 2

        BorderImage {
            anchors.fill: parent
            anchors.margins: -36
            source: "file://" + root.artDir + "/shadow.png"
            border { left: 40; right: 40; top: 40; bottom: 40 }
        }

        BorderImage {
            anchors.fill: parent
            anchors.margins: -36
            source: "file://" + root.artDir + "/glow.png"
            border { left: 40; right: 40; top: 40; bottom: 40 }
            opacity: pill.lit ? 1 : (hover.hovered ? 0.75 : 0.22)
            Behavior on opacity { NumberAnimation { duration: 200 } }
        }

        Canvas {
            id: glassPane
            anchors.fill: parent
            property size art: Qt.size(0, 0)
            // Where the pill is on the screen, re-read whenever it moves.
            property point at: {
                pill.x; pill.y; pill.width; pill.parent ? pill.parent.x + pill.parent.y : 0;
                return pill.corner ? pill.mapToItem(pill.corner.contentItem, 0, 0) : Qt.point(0, 0);
            }
            onAtChanged: requestPaint()
            onWidthChanged: requestPaint()
            Component.onCompleted: loadImage(root.glassArt)
            // The image can finish loading before the canvas is ready to
            // draw; measure it whenever both are true.
            function measure() {
                if (!available || !isImageLoaded(root.glassArt)) return;
                const d = getContext("2d").createImageData(root.glassArt);
                art = Qt.size(d.width, d.height);
                requestPaint();
            }
            onImageLoaded: measure()
            onAvailableChanged: measure()

            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                const r = height / 2;
                ctx.beginPath();
                ctx.roundedRect(0.5, 0.5, width - 1, height - 1, r, r);
                ctx.closePath();
                ctx.save();
                ctx.clip();
                const c = pill.corner;
                if (c && art.width > 0 && isImageLoaded(root.glassArt)) {
                    // The Dome is drawn cover-fit; find this pill's patch of it.
                    const sw = c.screen.width, sh = c.screen.height;
                    const k = Math.max(sw / art.width, sh / art.height);
                    const ox = (sw - art.width * k) / 2, oy = (sh - art.height * k) / 2;
                    const sx = c.screenX + at.x, sy = c.screenY + at.y;
                    ctx.drawImage(root.glassArt, (sx - ox) / k, (sy - oy) / k, width / k, height / k,
                                  0, 0, width, height);
                }
                ctx.fillStyle = "rgba(9, 20, 44, 0.46)";
                ctx.fillRect(0, 0, width, height);
                const sheen = ctx.createLinearGradient(0, 0, 0, height);
                sheen.addColorStop(0, "rgba(159, 212, 255, 0.16)");
                sheen.addColorStop(0.55, "rgba(159, 212, 255, 0)");
                ctx.fillStyle = sheen;
                ctx.fillRect(0, 0, width, height);
                ctx.restore();
                ctx.lineWidth = 1;
                ctx.strokeStyle = Qt.rgba(pill.edgeColour.r, pill.edgeColour.g, pill.edgeColour.b,
                                          pill.lit ? 0.8 : 0.26);
                ctx.stroke();
            }
        }

        Connections {
            target: pill
            function onLitChanged() { glassPane.requestPaint() }
            function onEdgeColourChanged() { glassPane.requestPaint() }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            cursorShape: Qt.PointingHandCursor
            onClicked: mouse => pill.clicked(mouse)
            onWheel: wheel => pill.scrolled(wheel)
        }

        HoverHandler { id: hover }

        Row {
            id: inner
            anchors.centerIn: parent
            spacing: 8
        }
    }

    component Corner: PanelWindow {
        id: cw
        property bool atTop: true
        property bool atLeft: true
        property bool keep: false       // stay out: empty workstation, overview, pinned
        property bool peeking: false
        readonly property bool shown: keep || peeking || over.hovered
        property real slide: shown ? 0 : 1
        Behavior on slide { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
        default property alias pills: holder.data
        readonly property int edge: 14  // gap to the screen edge
        readonly property int room: 40  // space for the glow and shadow
        readonly property real screenX: atLeft ? 0 : screen.width - width
        readonly property real screenY: atTop ? 0 : screen.height - height

        function peek(ms) {
            peeking = true;
            hideTimer.interval = ms || 1200;
            hideTimer.restart();
        }

        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "0space-corner"
        anchors { top: cw.atTop; bottom: !cw.atTop; left: cw.atLeft; right: !cw.atLeft }
        implicitWidth: holder.implicitWidth + edge + room
        implicitHeight: holder.implicitHeight + edge + room
        // Hidden, only a small hot corner takes the pointer; the rest of the
        // screen corner stays clickable.
        mask: Region { item: cw.shown ? holder : hot }

        Timer { id: hideTimer; onTriggered: cw.peeking = false }

        Item {
            id: hot
            width: 18
            height: 18
            x: cw.atLeft ? 0 : parent.width - width
            y: cw.atTop ? 0 : parent.height - height
            HoverHandler { onHoveredChanged: if (hovered) cw.peek(1500) }
        }

        Row {
            id: holder
            spacing: 10
            layoutDirection: cw.atLeft ? Qt.LeftToRight : Qt.RightToLeft
            x: (cw.atLeft ? cw.edge : cw.room) + (cw.atLeft ? -1 : 1) * cw.slide * (implicitWidth + cw.edge + 12)
            y: cw.atTop ? cw.edge : cw.room
            opacity: 1 - cw.slide * 0.8
            HoverHandler {
                id: over
                onHoveredChanged: if (!hovered) cw.peek(900)
            }
        }
    }

    // What the corners report.
    SystemClock { id: clock; precision: SystemClock.Minutes }

    readonly property var battery: UPower.displayDevice
    readonly property bool hasBattery: !!battery && battery.isLaptopBattery
    readonly property int batteryPercent: !hasBattery ? 0
        : Math.round(battery.percentage <= 1 ? battery.percentage * 100 : battery.percentage)
    readonly property bool charging: hasBattery && (battery.state === UPowerDeviceState.Charging
                                                    || battery.state === UPowerDeviceState.FullyCharged)
    readonly property bool batteryLow: hasBattery && !charging && batteryPercent <= 15
    readonly property bool batteryFull: hasBattery && battery.state === UPowerDeviceState.FullyCharged
    // "2h 14m left", "full in 40m", from UPower's estimates.
    function batteryTime() {
        if (!hasBattery) return "";
        if (batteryFull) return "full";
        const secs = charging ? battery.timeToFull : battery.timeToEmpty;
        if (!secs || secs <= 0) return charging ? "charging" : "estimating";
        const h = Math.floor(secs / 3600), m = Math.round((secs % 3600) / 60);
        const t = h > 0 ? h + "h " + m + "m" : m + "m";
        return charging ? "full in " + t : t + " left";
    }

    PwObjectTracker { objects: [Pipewire.defaultAudioSink] }
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property int soundPercent: sink && sink.audio ? Math.round(sink.audio.volume * 100) : 0
    readonly property bool soundMuted: !!sink && !!sink.audio && sink.audio.muted

    // Network, from NetworkManager every ten seconds.
    property string netKind: "none"     // wifi, ethernet or none
    property string netName: ""
    property int netSignal: 0
    Process {
        id: netProbe
        command: ["sh", "-c",
            "nmcli -t -f TYPE,STATE,CONNECTION device 2>/dev/null | awk -F: '$2==\"connected\" && ($1==\"wifi\" || $1==\"ethernet\") { print $1; print $3; exit }';" +
            "nmcli -t -f ACTIVE,SIGNAL device wifi list --rescan no 2>/dev/null | awk -F: '$1==\"yes\" { print $2; exit }'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n").filter(l => l.length > 0);
                root.netKind = lines.length >= 2 ? lines[0] : "none";
                root.netName = lines.length >= 2 ? lines[1].replace(/\\:/g, ":") : "";
                root.netSignal = lines.length >= 3 ? parseInt(lines[2]) : 0;
            }
        }
    }
    Timer {
        interval: 10000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: netProbe.running = true
    }

    // Nerd Font icons (Maple Mono NF).
    readonly property string iconFont: "Maple Mono NF"
    function netIcon() {
        if (netKind === "ethernet") return "\u{F0200}";
        if (netKind !== "wifi") return "\u{F092E}";
        return ["\u{F091F}", "\u{F0922}", "\u{F0925}", "\u{F0928}"][Math.min(3, Math.floor(netSignal / 25))];
    }
    function batteryIcon() {
        if (charging) return "\u{F0084}";
        if (batteryPercent >= 95) return "\u{F0079}";
        return String.fromCodePoint(0xF007A + Math.max(0, Math.floor(batteryPercent / 10) - 1));
    }
    function soundIcon() {
        if (soundMuted || soundPercent === 0) return "\u{F0581}";
        return soundPercent < 34 ? "\u{F057F}" : (soundPercent < 67 ? "\u{F0580}" : "\u{F057E}");
    }

    component Glyph: Text {
        color: root.glass
        font.family: root.iconFont
        font.pixelSize: 16
        anchors.verticalCenter: parent.verticalCenter
    }
    component Label: Text {
        color: root.furTan
        font.pixelSize: 13
        anchors.verticalCenter: parent.verticalCenter
    }

    // The English half of a Translated line.
    component TranslatedPlain: Text {
        required property Item row
        color: row.ink
        font.pixelSize: row.size
        font.letterSpacing: row.letterSpacing
        style: row.outlined ? Text.Outline : Text.Normal
        styleColor: root.skyHigh
        anchors.verticalCenter: parent.verticalCenter
    }

    // ------------------------------------------------------------ thought-speak
    ListModel { id: thoughts }

    function speak(text) {
        // One line, never across the whole screen.
        let line = String(text).replace(/\s+/g, " ").trim();
        if (line.length > 140) line = line.slice(0, 138).replace(/\s+$/, "") + "…";
        thoughts.append({ "line": line });
        while (thoughts.count > 3)
            thoughts.remove(0);
        fade.restart();
    }

    Timer {
        id: fade
        interval: 8000
        onTriggered: if (thoughts.count > 0) { thoughts.remove(0); if (thoughts.count > 0) fade.restart(); }
    }

    NotificationServer {
        bodySupported: true
        actionsSupported: false
        onNotification: n => {
            const parts = [n.summary, n.body].filter(s => s && s.length > 0);
            root.speak(parts.join(". "));
            n.tracked = false;
        }
    }

    // The two-hour morph limit, as a break reminder at 1h50m.
    Timer {
        interval: 110 * 60 * 1000
        running: true
        repeat: true
        onTriggered: root.speak("Morph time: one hour, fifty minutes. Demorph now, aristh, or remain as you are")
    }

    Component.onCompleted: speak("Dome integrity nominal. All engines report ready")

    Variants {
        model: Quickshell.screens

        Scope {
            id: perScreen
            required property var modelData

            FileView {
                id: ringState
                path: Quickshell.env("XDG_RUNTIME_DIR") + "/0space-ring-" + perScreen.modelData.name + ".json"
                watchChanges: true
                printErrors: false
                onFileChanged: reload()
            }

            property var ring: {
                try { return JSON.parse(ringState.text()); } catch (e) { return null; }
            }
            readonly property bool ringShown: !!ring && ring.active && !ring.full

            // ---------------------------------------------------- the Dome
            PanelWindow {
                id: dome
                screen: perScreen.modelData
                WlrLayershell.layer: WlrLayer.Background
                WlrLayershell.namespace: "0space-dome"
                exclusionMode: ExclusionMode.Ignore
                anchors { top: true; bottom: true; left: true; right: true }
                color: root.skyHigh

                // The biosphere under the dome: sky, glass lattice, horizon,
                // alien grass and the red, blue and pink trees of home.
                Canvas {
                    id: biosphere
                    anchors.fill: parent
                    visible: !userImage.visible && !systemImage.visible
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()
                    onPaint: {
                        const ctx = getContext("2d");
                        const w = width, h = height;
                        const hz = h * 0.78;                     // the horizon
                        let seed = 11;
                        const rnd = () => { seed = (seed * 16807) % 2147483647; return seed / 2147483647; };
                        ctx.reset();

                        // Sky: deep night overhead, warming towards the horizon.
                        let g = ctx.createLinearGradient(0, 0, 0, hz);
                        g.addColorStop(0.00, "#040914");
                        g.addColorStop(0.45, "#0b1630");
                        g.addColorStop(0.80, "#2a1d46");
                        g.addColorStop(1.00, "#6b3a5e");
                        ctx.fillStyle = g;
                        ctx.fillRect(0, 0, w, h);

                        // Soft nebula drifting across the upper sky.
                        const nebula = (x, y, r, c, a) => {
                            const rg = ctx.createRadialGradient(x, y, 0, x, y, r);
                            rg.addColorStop(0, c);
                            rg.addColorStop(1, "transparent");
                            ctx.globalAlpha = a;
                            ctx.fillStyle = rg;
                            ctx.fillRect(x - r, y - r, r * 2, r * 2);
                        };
                        nebula(w * 0.28, h * 0.22, h * 0.45, "#3b4f9a", 0.22);
                        nebula(w * 0.62, h * 0.12, h * 0.38, "#6a3f8f", 0.16);
                        nebula(w * 0.45, h * 0.35, h * 0.30, "#2f6f8f", 0.10);

                        // Fine stars, a few brighter ones with a halo.
                        ctx.fillStyle = "#dfeaff";
                        for (let i = 0; i < 260; i++) {
                            const sx = rnd() * w, sy = rnd() * hz * 0.85;
                            const r = 0.3 + Math.pow(rnd(), 3) * 1.1;
                            ctx.globalAlpha = (0.25 + rnd() * 0.65) * (1 - sy / hz * 0.6);
                            ctx.beginPath(); ctx.arc(sx, sy, r, 0, Math.PI * 2); ctx.fill();
                        }
                        for (let i = 0; i < 6; i++) {
                            const sx = rnd() * w, sy = rnd() * hz * 0.5;
                            nebula(sx, sy, 7, "#ffffff", 0.35);
                            ctx.globalAlpha = 0.9;
                            ctx.fillStyle = "#ffffff";
                            ctx.beginPath(); ctx.arc(sx, sy, 1.2, 0, Math.PI * 2); ctx.fill();
                        }

                        // Two moons, shaded, with a faint glow.
                        const moon = (x, y, r, lit, dark) => {
                            nebula(x, y, r * 3.2, lit, 0.12);
                            const mg = ctx.createRadialGradient(x - r * 0.35, y - r * 0.35, r * 0.1, x, y, r);
                            mg.addColorStop(0, lit);
                            mg.addColorStop(1, dark);
                            ctx.globalAlpha = 0.95;
                            ctx.fillStyle = mg;
                            ctx.beginPath(); ctx.arc(x, y, r, 0, Math.PI * 2); ctx.fill();
                        };
                        moon(w * 0.84, h * 0.14, h * 0.028, "#efe4cf", "#8d7f6c");
                        moon(w * 0.885, h * 0.19, h * 0.013, "#c6d6f2", "#5c6f96");

                        // The dome: no lattice, just the glass rim catching the light.
                        ctx.globalAlpha = 0.18;
                        ctx.strokeStyle = "#a9d8ff";
                        ctx.lineWidth = 1.2;
                        ctx.beginPath();
                        ctx.ellipse(-w * 0.15, h * 0.04 - hz * 0.02, w * 1.3, hz * 1.9);
                        ctx.stroke();
                        ctx.globalAlpha = 0.07;
                        ctx.lineWidth = 6;
                        ctx.beginPath();
                        ctx.ellipse(-w * 0.13, h * 0.055, w * 1.26, hz * 1.86);
                        ctx.stroke();

                        // Warm glow where the sky meets the land.
                        ctx.save();
                        ctx.translate(w / 2, hz);
                        ctx.scale(1, 0.25);
                        nebula(0, 0, w * 0.6, "#e08aa8", 0.28);
                        ctx.restore();

                        // Hills in layers, fading into the distance.
                        const hills = (base, amp, col, a, phase) => {
                            ctx.globalAlpha = a;
                            ctx.fillStyle = col;
                            ctx.beginPath();
                            ctx.moveTo(0, h);
                            for (let x = 0; x <= w; x += 8) {
                                const y = base - amp * (0.55 * Math.sin(x / w * 5.1 + phase)
                                                      + 0.30 * Math.sin(x / w * 11.7 + phase * 2.3)
                                                      + 0.15 * Math.sin(x / w * 23.0 + phase * 0.7));
                                ctx.lineTo(x, y);
                            }
                            ctx.lineTo(w, h);
                            ctx.closePath();
                            ctx.fill();
                        };
                        hills(hz - h * 0.010, h * 0.030, "#4a3466", 0.55, 1.3);
                        hills(hz + h * 0.012, h * 0.026, "#2a2a4e", 0.80, 4.1);
                        hills(hz + h * 0.035, h * 0.020, "#13283a", 1.00, 2.2);

                        // Ground: dark, falling away to near black.
                        g = ctx.createLinearGradient(0, hz + h * 0.03, 0, h);
                        g.addColorStop(0, "#102536");
                        g.addColorStop(1, "#050d16");
                        ctx.globalAlpha = 1;
                        ctx.fillStyle = g;
                        ctx.fillRect(0, hz + h * 0.05, w, h);

                        // Trees only at the edges, out of the way of the windows:
                        // dark trunks, canopies tinted the colours of home.
                        const tree = (tx, base, th, col) => {
                            ctx.globalAlpha = 1;
                            ctx.strokeStyle = "#0a0f1c";
                            ctx.lineWidth = Math.max(2, th * 0.05);
                            ctx.lineCap = "round";
                            ctx.beginPath();
                            ctx.moveTo(tx, base);
                            ctx.bezierCurveTo(tx - th * 0.05, base - th * 0.4, tx + th * 0.1, base - th * 0.7, tx + th * 0.04, base - th);
                            ctx.stroke();
                            const blobs = [[0, -1.0, 0.30], [-0.22, -0.9, 0.20], [0.24, -0.92, 0.21], [0.04, -1.18, 0.19]];
                            for (const b of blobs) {
                                const bx = tx + th * (0.04 + b[0]), by = base + th * b[1], br = th * b[2];
                                const cg = ctx.createRadialGradient(bx - br * 0.3, by - br * 0.4, br * 0.1, bx, by, br);
                                cg.addColorStop(0, col);
                                cg.addColorStop(1, "#140c24");
                                ctx.globalAlpha = 0.85;
                                ctx.fillStyle = cg;
                                ctx.beginPath(); ctx.arc(bx, by, br, 0, Math.PI * 2); ctx.fill();
                            }
                        };
                        tree(w * 0.022, h * 0.845, h * 0.12, "#7a3d60");
                        tree(w * 0.060, h * 0.830, h * 0.075, "#38548a");
                        tree(w * 0.975, h * 0.850, h * 0.13, "#74343f");
                        tree(w * 0.940, h * 0.832, h * 0.07, "#7a3d60");
                        ctx.globalAlpha = 1;
                    }
                }

                Image {
                    id: userImage
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    source: "file://" + root.userArt
                    visible: status === Image.Ready
                }

                Image {
                    id: systemImage
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    source: "file://" + root.systemArt
                    visible: status === Image.Ready && !userImage.visible
                }

                // ------------------------------------------------ the ring
                // A curved band round the edge of the screen: Z-space, where
                // the other windows wait, marked out in the script.
                Canvas {
                    id: ringBand
                    anchors.fill: parent
                    visible: perScreen.ringShown || (!!perScreen.ring && perScreen.ring.overview)
                    property var r: perScreen.ring
                    onRChanged: requestPaint()
                    onWidthChanged: requestPaint()
                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.reset();
                        if (!r || !r.active)
                            return;
                        const cx = r.orbit[0], cy = r.orbit[1], rx = r.orbit[2], ry = r.orbit[3];
                        // In the carousel the ring is the floor the windows stand on, seen in
                        // perspective; in the overview it is a flat band round the edge.
                        const band = r.overview ? Math.max(40, Math.min(width, height) * 0.12)
                                                : Math.max(18, ry * 0.5);

                        // The band itself.
                        ctx.globalAlpha = 0.08;
                        ctx.strokeStyle = root.furBlue;
                        ctx.lineWidth = band;
                        ctx.beginPath(); ctx.ellipse(cx - rx, cy - ry, rx * 2, ry * 2); ctx.stroke();

                        // Its two edges.
                        ctx.globalAlpha = 0.35;
                        ctx.lineWidth = 1.2;
                        ctx.strokeStyle = root.glass;
                        ctx.beginPath(); ctx.ellipse(cx - rx - band / 2, cy - ry - band / 2, rx * 2 + band, ry * 2 + band); ctx.stroke();
                        ctx.beginPath(); ctx.ellipse(cx - rx + band / 2, cy - ry + band / 2, rx * 2 - band, ry * 2 - band); ctx.stroke();

                        // Tick marks and script round the outside edge.
                        ctx.globalAlpha = 0.6;
                        ctx.strokeStyle = root.furTan;
                        ctx.fillStyle = root.furTan;
                        ctx.lineWidth = 1;
                        // Four words, at the sides of the ring: the top is thought-speak's,
                        // the bottom belongs to whichever window orbits there.
                        const words = ["zero space", "escafil", "thought speak", "andalite"];
                        const wordAngles = [25, 155, 205, 335];
                        for (let i = 0; i < 72; i++) {
                            const a = i / 72 * Math.PI * 2;
                            const ox = cx + (rx + band / 2) * Math.cos(a), oy = cy + (ry + band / 2) * Math.sin(a);
                            const ix = cx + (rx + band / 2 + (i % 6 === 0 ? 10 : 5)) * Math.cos(a);
                            const iy = cy + (ry + band / 2 + (i % 6 === 0 ? 10 : 5)) * Math.sin(a);
                            ctx.beginPath(); ctx.moveTo(ox, oy); ctx.lineTo(ix, iy); ctx.stroke();
                        }
                        ctx.fillStyle = ctx.strokeStyle;
                        ctx.font = "19px '" + root.scriptFont + "'";
                        ctx.textAlign = "center";
                        ctx.textBaseline = "middle";
                        for (let i = 0; i < words.length; i++) {
                            const a = wordAngles[i] * Math.PI / 180;
                            const px = cx + (rx + band / 2 + 26) * Math.cos(a);
                            const py = cy + (ry + band / 2 + 22) * Math.sin(a);
                            ctx.fillText(words[i], px, py);
                        }
                        ctx.globalAlpha = 1;
                    }
                }

                // ------------------------------------------------ the windows
                // Corner brackets round the centre window, in Andalite blue.
                Item {
                    id: centreFrame
                    visible: !!perScreen.ring && perScreen.ring.active && !perScreen.ring.overview
                    readonly property int pad: 8
                    readonly property int arm: 34
                    x: perScreen.ring ? perScreen.ring.centre[0] - pad : 0
                    y: perScreen.ring ? perScreen.ring.centre[1] - pad : 0
                    width: perScreen.ring ? perScreen.ring.centre[2] + 2 * pad : 0
                    height: perScreen.ring ? perScreen.ring.centre[3] + 2 * pad : 0

                    Rectangle { anchors.fill: parent; anchors.margins: centreFrame.pad - 2; color: "transparent"; border.color: root.furBlue; border.width: 1; opacity: 0.6 }
                    Repeater {
                        model: 4
                        Item {
                            required property int index
                            width: centreFrame.arm; height: centreFrame.arm
                            x: (index % 2) ? centreFrame.width - width : 0
                            y: (index > 1) ? centreFrame.height - height : 0
                            Rectangle { width: parent.width; height: 3; color: root.furBlue; y: (index > 1) ? parent.height - 3 : 0 }
                            Rectangle { width: 3; height: parent.height; color: root.furBlue; x: (index % 2) ? parent.width - 3 : 0 }
                        }
                    }
                }

                // Each orbiting window: a soft halo, its name in the script,
                // and the name again in plain letters underneath.
                Repeater {
                    model: (perScreen.ringShown || (!!perScreen.ring && perScreen.ring.overview)) ? perScreen.ring.tiles : []

                    Item {
                        id: tile
                        required property var modelData
                        required property int index
                        readonly property bool isCentre: index === 0 && !perScreen.ring.overview
                        // "org.mozilla.firefox" reads as "firefox".
                        readonly property string label: {
                            const parts = modelData.name.split(".");
                            return parts[parts.length - 1].toLowerCase();
                        }
                        // Labels go under a window, unless that would run off the screen.
                        readonly property bool labelAbove: y + height + 44 > dome.height
                        x: modelData.x - modelData.w / 2
                        y: modelData.y - modelData.h / 2
                        width: modelData.w
                        height: modelData.h

                        Rectangle {
                            // Halos only in the flat overview: in the carousel the
                            // windows are turned in 3D and a flat frame would not fit.
                            visible: !tile.isCentre && perScreen.ring.overview
                            anchors.fill: parent
                            anchors.margins: -5
                            radius: 10
                            color: Qt.rgba(0.42, 0.64, 0.85, 0.18)
                            border.color: root.glass
                            border.width: 1
                        }

                        // The front window's name sits under its bottom-left bracket, clear of
                        // thought-speak above and the far side of the carousel.
                        Row {
                            visible: tile.isCentre
                            x: 0
                            y: parent.height + 20
                            spacing: 10
                            Translated { text: tile.label; glyph: 9; scriptInk: root.furBlue; ink: root.furBlue; size: 13; letterSpacing: 3; upper: true }
                        }

                        Column {
                            visible: !tile.isCentre
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: tile.labelAbove ? -implicitHeight - 9 : parent.height + 9
                            spacing: 2
                            Translated {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: tile.label
                                glyph: 6
                                size: 11
                                letterSpacing: 2
                                upper: true
                            }
                        }
                    }
                }
            }

            // ---------------------------------------------------- thought-speak
            // Floats in the clear space at the top of the orbit: the words in
            // the script, and in plain letters beneath.
            PanelWindow {
                screen: perScreen.modelData
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.namespace: "0space-thought-speak"
                exclusionMode: ExclusionMode.Ignore
                anchors { top: true }
                // Below the corner pills, never across them.
                margins.top: 62
                implicitWidth: perScreen.modelData.width * 0.6
                implicitHeight: 150
                color: "transparent"
                mask: Region {}

                Column {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 8

                    Repeater {
                        model: thoughts

                        Column {
                            required property string line
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 1
                            Translated {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: line
                                scriptText: line.split(" ").slice(0, 3).join(" ")
                                glyph: 9
                                size: 17
                                letterSpacing: 1.5
                                before: "< "
                                after: " >"
                                outlined: true
                                maxWidth: perScreen.modelData.width * 0.6
                            }
                        }
                    }
                }
            }

            // ---------------------------------------------------- the corners
            readonly property bool workstationEmpty: !ring || !ring.active || !ring.tiles || ring.tiles.length === 0
            readonly property bool cornersKept: root.cornersPinned || workstationEmpty || (!!ring && ring.overview)
            readonly property int workstation: ring && ring.workspace ? ring.workspace : 1
            readonly property string frontName: ring && ring.active && !ring.overview && ring.tiles
                && ring.tiles.length > 0 ? ring.tiles[0].name : ""
            onWorkstationChanged: topLeft.peek(1600)

            // Orders to the carousel plugin, through its pipe.
            Process { id: order }
            function goTo(n) {
                order.command = ["sh", "-c", "printf 'workspace %s\\n' \"$1\" > \"$2\"", "sh", String(n),
                    Quickshell.env("XDG_RUNTIME_DIR") + "/0space-ring-" + perScreen.modelData.name + ".ctl"];
                order.running = true;
            }

            Corner {
                id: topLeft
                screen: perScreen.modelData
                atTop: true
                atLeft: true
                keep: perScreen.cornersKept

                // Workstations: the current one a glowing capsule, the others
                // a filled dot if they hold windows, a faint ring if empty.
                Pill {
                    corner: topLeft
                    lit: true
                    pad: 12
                    onScrolled: wheel => perScreen.goTo(Math.max(1, Math.min(
                        perScreen.ring ? perScreen.ring.workspaces : 9,
                        perScreen.workstation + (wheel.angleDelta.y < 0 ? 1 : -1))))
                    Repeater {
                        model: perScreen.ring && perScreen.ring.workspaces ? perScreen.ring.workspaces : 9
                        Item {
                            id: ws
                            required property int index
                            readonly property int number: index + 1
                            readonly property bool current: number === perScreen.workstation
                            readonly property bool used: !!perScreen.ring && !!perScreen.ring.occupied
                                && perScreen.ring.occupied.indexOf(number) >= 0
                            width: current ? 30 : 14
                            height: 18
                            anchors.verticalCenter: parent.verticalCenter
                            Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                            Rectangle {
                                anchors.centerIn: parent
                                width: ws.current ? 30 : (ws.used ? 8 : 7)
                                height: ws.current ? 18 : width
                                radius: height / 2
                                color: ws.current ? root.furBlue : (ws.used ? root.furTan : "transparent")
                                border.width: ws.current || ws.used ? 0 : 1
                                border.color: Qt.rgba(0.62, 0.83, 1, 0.45)
                                Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                            }
                            Text {
                                anchors.centerIn: parent
                                visible: ws.current
                                text: ws.number
                                color: root.skyHigh
                                font.pixelSize: 12
                                font.bold: true
                            }
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -3
                                cursorShape: Qt.PointingHandCursor
                                onClicked: perScreen.goTo(ws.number)
                            }
                        }
                    }
                }

                // The window at the front of the carousel.
                Pill {
                    corner: topLeft
                    visible: perScreen.frontName !== ""
                    Translated {
                        anchors.verticalCenter: parent.verticalCenter
                        text: perScreen.frontName
                        glyph: 7
                        size: 12
                        letterSpacing: 2
                        upper: true
                        scriptInk: root.glass
                        ink: root.furTan
                    }
                }
            }

            Corner {
                id: topRight
                screen: perScreen.modelData
                atTop: true
                atLeft: false
                keep: perScreen.cornersKept

                // Power: lock, suspend, log out, restart, power off.
                Pill {
                    corner: topRight
                    pad: 11
                    onClicked: powerMenu.open = true
                    Glyph { text: "\u{F0425}"; font.pixelSize: 17 }
                }

                Pill {
                    corner: topRight
                    lit: true
                    Label {
                        text: Qt.formatTime(clock.date, "HH:mm")
                        color: root.glass
                        font.pixelSize: 15
                        font.bold: true
                        font.letterSpacing: 1
                    }
                }

                Pill {
                    corner: topRight
                    Translated {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Qt.formatDate(clock.date, "dddd")
                        glyph: 7
                        size: 13
                        scriptInk: root.glass
                    }
                    Label { text: Qt.formatDate(clock.date, "d MMMM") }
                }
            }

            Corner {
                id: bottomRight
                screen: perScreen.modelData
                atTop: false
                atLeft: false
                keep: perScreen.cornersKept || root.batteryLow

                // Battery: hover for the time left (or until full); red and
                // glowing when low. Only on machines that have one.
                Pill {
                    id: batteryPill
                    corner: bottomRight
                    visible: root.hasBattery
                    lit: root.batteryLow
                    edgeColour: root.batteryLow ? root.treeRed : root.glass
                    onClicked: Quickshell.execDetached(["mirrorwave", "--hold", "escafil", "scan"])
                    Glyph {
                        text: root.batteryIcon()
                        color: root.batteryLow ? root.treeRed : (root.charging ? root.furTan : root.glass)
                    }
                    Label { text: root.batteryPercent + "%" }
                    Label {
                        visible: batteryPill.hovered
                        text: root.batteryTime()
                        color: root.glass
                        font.pixelSize: 12
                    }
                }

                Pill {
                    corner: bottomRight
                    onClicked: Quickshell.execDetached(["0space-level", "mute"])
                    onScrolled: wheel => Quickshell.execDetached(["0space-level", wheel.angleDelta.y > 0 ? "up" : "down"])
                    Glyph { text: root.soundIcon(); color: root.soundMuted ? root.treeRed : root.glass }
                    Label { text: root.soundMuted ? "off" : root.soundPercent + "%" }
                }

                Pill {
                    corner: bottomRight
                    onClicked: Quickshell.execDetached(["mirrorwave", "nmtui"])
                    Glyph { text: root.netIcon(); color: root.netKind === "none" ? root.treeRed : root.glass }
                    Label {
                        text: root.netKind === "none" ? "Offline" : (root.netName || root.netKind)
                        elide: Text.ElideRight
                        width: Math.min(implicitWidth, 160)
                    }
                }

                // The tray: left click opens, right click for the menu.
                Pill {
                    corner: bottomRight
                    visible: SystemTray.items.values.length > 0
                    pad: 11
                    Repeater {
                        model: SystemTray.items
                        Item {
                            id: trayItem
                            required property SystemTrayItem modelData
                            width: 18
                            height: 18
                            anchors.verticalCenter: parent.verticalCenter
                            IconImage {
                                anchors.fill: parent
                                source: trayItem.modelData.icon
                                asynchronous: true
                            }
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -4
                                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                                cursorShape: Qt.PointingHandCursor
                                onClicked: mouse => {
                                    const item = trayItem.modelData;
                                    if (mouse.button === Qt.MiddleButton) {
                                        item.secondaryActivate();
                                    } else if (mouse.button === Qt.LeftButton && !item.onlyMenu) {
                                        item.activate();
                                    } else if (item.hasMenu) {
                                        const p = trayItem.mapToItem(bottomRight.contentItem, 0, 0);
                                        item.display(bottomRight, p.x, p.y - 8);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------ launcher
    // Super+Space (Wayfire runs: 0space-call launcher toggle). Type to search;
    // Up/Down to choose, Enter to launch, Esc to close.
    // ------------------------------------------------------------ power
    PanelWindow {
        id: powerMenu
        property bool open: false
        property int selected: 0
        property string armed: ""      // restart/off wait for a second press

        readonly property var choices: [
            { key: "lock", icon: "\u{F033E}", label: "Lock",
              command: ["swaylock", "-f", "-C", "/etc/swaylock/config"] },
            { key: "suspend", icon: "\u{F04B2}", label: "Suspend",
              command: ["systemctl", "suspend"] },
            { key: "logout", icon: "\u{F0343}", label: "Log out",
              command: ["sh", "-c", "loginctl terminate-session \"$XDG_SESSION_ID\" || pkill -f bin/wayfire"] },
            { key: "restart", icon: "\u{F0709}", label: "Restart", confirm: true,
              command: ["systemctl", "reboot"] },
            { key: "off", icon: "\u{F0425}", label: "Power off", confirm: true,
              command: ["systemctl", "poweroff"] }
        ]

        function choose(i) {
            const c = choices[i];
            if (c.confirm && armed !== c.key) { armed = c.key; disarm.restart(); return; }
            open = false;
            Quickshell.execDetached(c.command);
        }

        visible: open
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "0space-power"
        WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        onOpenChanged: { selected = 0; armed = ""; if (open) menu.forceActiveFocus(); }

        Timer { id: disarm; interval: 3000; onTriggered: powerMenu.armed = "" }

        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0.03, 0.07, 0.15, 0.45)
            MouseArea { anchors.fill: parent; onClicked: powerMenu.open = false }
        }

        Rectangle {
            id: menu
            focus: true
            width: 250
            height: rows.implicitHeight + 24
            anchors { top: parent.top; right: parent.right; topMargin: 60; rightMargin: 14 }
            radius: 16
            color: Qt.rgba(0.04, 0.09, 0.19, 0.94)
            border.color: root.glass
            border.width: 1
            MouseArea { anchors.fill: parent }

            BorderImage {
                anchors.fill: parent
                anchors.margins: -36
                z: -1
                source: "file://" + root.artDir + "/glow.png"
                border { left: 40; right: 40; top: 40; bottom: 40 }
            }

            Keys.onPressed: event => {
                const n = powerMenu.choices.length;
                if (event.key === Qt.Key_Escape) powerMenu.open = false;
                else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) powerMenu.selected = (powerMenu.selected + 1) % n;
                else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) powerMenu.selected = (powerMenu.selected + n - 1) % n;
                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) powerMenu.choose(powerMenu.selected);
                else return;
                event.accepted = true;
            }

            Column {
                id: rows
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                spacing: 4

                Repeater {
                    model: powerMenu.choices
                    Rectangle {
                        id: row
                        required property var modelData
                        required property int index
                        readonly property bool armedHere: powerMenu.armed === modelData.key
                        readonly property bool current: powerMenu.selected === index
                        width: rows.width
                        height: 40
                        radius: 12
                        color: armedHere ? Qt.rgba(0.72, 0.26, 0.31, 0.35)
                             : current ? Qt.rgba(0.42, 0.64, 0.85, 0.22) : "transparent"
                        border.width: current || armedHere ? 1 : 0
                        border.color: armedHere ? root.treeRed : root.glass

                        Row {
                            anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                            spacing: 12
                            Glyph {
                                text: row.modelData.icon
                                font.pixelSize: 18
                                color: row.armedHere ? root.treeRed : root.glass
                            }
                            Translated {
                                anchors.verticalCenter: parent.verticalCenter
                                text: row.armedHere ? "Again to " + row.modelData.label.toLowerCase() : row.modelData.label
                                scriptText: row.modelData.label
                                glyph: 7
                                size: 14
                                ink: row.armedHere ? root.treeRed : root.furTan
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: powerMenu.selected = row.index
                            onClicked: powerMenu.choose(row.index)
                        }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "power"
        function toggle(): void { powerMenu.open = !powerMenu.open }
    }

    IpcHandler {
        target: "launcher"
        function toggle(): void { launcher.open = !launcher.open }
        function open(): void { launcher.open = true }
        function close(): void { launcher.open = false }
    }

    PanelWindow {
        id: launcher
        property bool open: false
        property string query: ""
        property int selected: 0

        visible: open
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "0space-launcher"
        WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        onOpenChanged: {
            query = "";
            search.text = "";
            selected = 0;
            if (open) search.forceActiveFocus();
        }
        onQueryChanged: selected = 0

        // Best matches first: names that start with what you typed, then names
        // that contain it, then descriptions and keywords.
        readonly property var matches: {
            const q = query.trim().toLowerCase();
            const all = DesktopEntries.applications.values.filter(e => !e.noDisplay);
            const scored = [];
            for (const e of all) {
                const name = (e.name || "").toLowerCase();
                let score = -1;
                if (q === "") score = 0;
                else if (name.startsWith(q)) score = 0;
                else if (name.includes(q)) score = 1;
                else if (((e.genericName || "") + " " + (e.comment || "") + " " + (e.keywords || []).join(" "))
                         .toLowerCase().includes(q)) score = 2;
                if (score >= 0) scored.push({ entry: e, score: score, name: name });
            }
            scored.sort((a, b) => a.score - b.score || a.name.localeCompare(b.name));
            return scored.map(x => x.entry);
        }

        function launch(entry) {
            if (!entry) return;
            entry.execute();
            open = false;
        }

        // The Dome dims behind it; clicking outside closes it.
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0.03, 0.07, 0.15, 0.55)
            MouseArea { anchors.fill: parent; onClicked: launcher.open = false }
        }

        Rectangle {
            id: panel
            width: Math.min(620, parent.width - 80)
            height: column.implicitHeight + 36
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height * 0.2
            radius: 16
            color: Qt.rgba(0.04, 0.09, 0.19, 0.94)
            border.color: root.glass
            border.width: 1
            MouseArea { anchors.fill: parent }   // clicks on the panel don't close it

            Column {
                id: column
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 18 }
                spacing: 12

                Translated { text: "Launch"; glyph: 8; size: 12; letterSpacing: 3; upper: true; scriptInk: root.furBlue; ink: root.furBlue }

                Row {
                    width: parent.width
                    spacing: 4
                    Text { text: "<"; color: root.furTan; font.pixelSize: 22 }
                    TextInput {
                        id: search
                        width: parent.width - 40
                        color: root.furTan
                        selectionColor: root.furBlue
                        font.pixelSize: 22
                        cursorDelegate: Rectangle { width: 2; color: root.glass }
                        onTextChanged: launcher.query = text
                        Text {
                            visible: !search.text
                            text: "What do you need, " + (Quickshell.env("USER") || "aristh") + "?"
                            color: Qt.rgba(0.85, 0.76, 0.6, 0.45)
                            font.pixelSize: 22
                        }
                        Keys.onPressed: event => {
                            const n = launcher.matches.length;
                            if (event.key === Qt.Key_Escape) { launcher.open = false; event.accepted = true; }
                            else if (event.key === Qt.Key_Down || (event.key === Qt.Key_Tab)) {
                                launcher.selected = Math.min(n - 1, launcher.selected + 1); event.accepted = true;
                            } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) {
                                launcher.selected = Math.max(0, launcher.selected - 1); event.accepted = true;
                            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                launcher.launch(launcher.matches[launcher.selected]); event.accepted = true;
                            }
                        }
                    }
                    Text { text: ">"; color: root.furTan; font.pixelSize: 22 }
                }

                Rectangle { width: parent.width; height: 1; color: root.lineColour }

                ListView {
                    id: results
                    width: parent.width
                    height: Math.min(8, Math.max(1, count)) * 44
                    clip: true
                    model: launcher.matches
                    currentIndex: launcher.selected
                    highlightMoveDuration: 90
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: Item {
                        id: row
                        required property var modelData
                        required property int index
                        width: results.width
                        height: 44
                        readonly property bool chosen: index === launcher.selected

                        Rectangle {
                            anchors.fill: parent
                            radius: 8
                            color: row.chosen ? Qt.rgba(0.42, 0.64, 0.85, 0.22) : "transparent"
                            Rectangle {
                                visible: row.chosen
                                width: 3; radius: 2
                                anchors { left: parent.left; top: parent.top; bottom: parent.bottom; margins: 8 }
                                color: root.glass
                            }
                        }

                        Row {
                            anchors { left: parent.left; leftMargin: 18; verticalCenter: parent.verticalCenter }
                            spacing: 12
                            IconImage {
                                implicitSize: 26
                                anchors.verticalCenter: parent.verticalCenter
                                source: Quickshell.iconPath(row.modelData.icon, "application-x-executable")
                            }
                            Translated {
                                anchors.verticalCenter: parent.verticalCenter
                                text: row.modelData.name
                                glyph: 8
                                size: 16
                                scriptInk: row.chosen ? root.glass : root.furBlue
                                ink: row.chosen ? root.furTan : "#c8d3e6"
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: row.modelData.genericName || ""
                                color: Qt.rgba(0.78, 0.83, 0.9, 0.45)
                                font.pixelSize: 12
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: launcher.selected = row.index
                            onClicked: launcher.launch(row.modelData)
                        }
                    }
                }

                Text {
                    visible: launcher.matches.length === 0
                    text: "< Nothing aboard by that name. Try: escafil seek " + launcher.query.trim() + " >"
                    color: Qt.rgba(0.85, 0.76, 0.6, 0.6)
                    font.pixelSize: 13
                }
            }
        }
    }

    // ------------------------------------------------------------ levels
    // Volume, microphone and brightness keys run 0space-level, which sets the
    // level and reports it here: a gauge at the bottom of the screen.
    IpcHandler {
        target: "level"
        function display(kind: string, percent: int, muted: bool): void {
            level.kind = kind;
            level.percent = Math.max(0, Math.min(100, percent));
            level.muted = muted;
            level.shown = true;
            levelTimer.restart();
        }
    }

    Timer { id: levelTimer; interval: 1600; onTriggered: level.shown = false }

    PanelWindow {
        id: level
        property string kind: "Volume"
        property int percent: 0
        property bool muted: false
        property bool shown: false

        visible: shown
        color: "transparent"
        anchors.bottom: true
        margins.bottom: 64
        implicitWidth: 420
        implicitHeight: 64
        exclusionMode: ExclusionMode.Ignore
        mask: Region {}
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "0space-level"

        Rectangle {
            anchors.fill: parent
            radius: 14
            color: Qt.rgba(0.04, 0.09, 0.19, 0.88)
            border.color: level.muted ? root.treeRed : root.glass
            border.width: 1

            Row {
                anchors.centerIn: parent
                spacing: 14

                Translated {
                    anchors.verticalCenter: parent.verticalCenter
                    text: level.muted ? level.kind + " off" : level.kind
                    glyph: 7
                    size: 13
                    letterSpacing: 2
                    upper: true
                    ink: level.muted ? root.treeRed : root.furTan
                }

                // Twenty cells, one per 5%.
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3
                    Repeater {
                        model: 20
                        Rectangle {
                            required property int index
                            width: 7
                            height: 6 + index * 0.7
                            anchors.bottom: parent.bottom
                            radius: 2
                            color: index < Math.round(level.percent / 5)
                                ? (level.muted ? Qt.rgba(0.72, 0.26, 0.31, 0.5) : root.glass)
                                : root.lineColour
                        }
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: level.percent + "%"
                    color: root.furTan
                    font.pixelSize: 13
                    width: 40
                }
            }
        }
    }
}

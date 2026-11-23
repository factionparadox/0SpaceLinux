// 0-Space shell: the Dome, the ring, the script, and thought-speak.
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

    // ------------------------------------------------------------ the script
    // An invented script: every letter becomes a glyph built from arcs, a
    // stem, hooks and a dot, chosen by the letter's code, so the same word
    // always looks the same. Spaces stay spaces.
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
        property real glyph: 8
        property color scriptInk: root.glass
        property color ink: root.furTan
        property int size: 13
        property real letterSpacing: 0
        property bool upper: false
        property string before: ""
        property string after: ""
        property bool outlined: false
        spacing: 0
        TranslatedPlain { row: tr; text: tr.before; visible: text !== "" }
        Script {
            text: tr.text.toLowerCase()
            glyph: tr.glyph
            ink: tr.scriptInk
            style: tr.outlined ? Text.Outline : Text.Normal
            styleColor: root.skyHigh
            anchors.verticalCenter: parent.verticalCenter
        }
        TranslatedPlain { row: tr; text: "/" + (tr.upper ? tr.text.toUpperCase() : tr.text) + tr.after }
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
        thoughts.append({ "line": text });
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
                margins.top: 14
                implicitWidth: perScreen.modelData.width * 0.7
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
                                glyph: 9
                                size: 17
                                letterSpacing: 1.5
                                before: "< "
                                after: " >"
                                outlined: true
                            }
                        }
                    }
                }
            }
        }
    }
}

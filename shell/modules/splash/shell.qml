import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// The login splash: a full-screen cover that the session program starts, as a second small
// Quickshell instance, as soon as KWin is up. It stays until the main shell says it is ready
// (it writes $XDG_RUNTIME_DIR/caelestia-shell-ready) and the minimum time has passed, then fades
// out and exits. If the shell never says so, it leaves after maxMs anyway, so a broken shell
// cannot leave the screen covered.
//
// It draws either the Caelestia design (the logo and three dots) or a Plymouth theme: the
// session program (or the Preview buttons in Nexus) hands it a small description of the theme in
// CAELESTIA_SPLASH_THEME, built by utils/scripts/splash.js from the theme's own files.
//
// It imports nothing from the main shell on purpose: it has to load fast and keep working when
// the shell does not. The settings arrive as environment variables from the session program
// (or from the Preview button in Nexus -> Splash, which sets CAELESTIA_SPLASH_PREVIEW=1 and
// needs no ready file).
ShellRoot {
    id: root

    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || ""
    readonly property string schemePath: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/caelestia/scheme.json"
    readonly property bool preview: Quickshell.env("CAELESTIA_SPLASH_PREVIEW") === "1"
    readonly property bool showLogo: Quickshell.env("CAELESTIA_SPLASH_LOGO") !== "0"
    readonly property real configuredSeconds: {
        const n = Number(Quickshell.env("CAELESTIA_SPLASH_MIN"));
        return Number.isFinite(n) && n >= 0 ? n : 2;
    }
    // A preview is shown for at least 3 s, or it would be gone before it could be looked at.
    readonly property int minMs: Math.round((preview ? Math.max(configuredSeconds, 3) : configuredSeconds) * 1000)
    readonly property int maxMs: 20000
    // Time between the shell's signal and the fade, for its windows to be drawn.
    readonly property int settleMs: preview ? 0 : 600

    // The Plymouth theme to draw, or null for the Caelestia design.
    readonly property var theme: {
        try {
            const spec = JSON.parse(Quickshell.env("CAELESTIA_SPLASH_THEME") || "null");
            return spec && (spec.kind === "frames" || spec.kind === "star") ? spec : null;
        } catch (e) {
            return null;
        }
    }
    readonly property string kind: theme ? theme.kind : "plain"

    property color background: "#12131a"
    property color accent: "#b8c3ff"
    // The color of what is written or drawn on the background: the swoosh of the logo.
    property color ink: "#e6e6ee"
    // The scheme has been read, or could not be: nothing is drawn before, or a light scheme would
    // start as the dark default and change.
    property bool schemeReady: false
    // A theme brings its own background; the Caelestia design uses the user's colours.
    readonly property color backgroundTop: theme ? theme.bg[0] : background
    readonly property color backgroundBottom: theme ? theme.bg[1] : background
    property bool minElapsed: false
    property bool shellReady: false
    property bool closing: false

    readonly property bool readyToClose: minElapsed && (preview || shellReady)

    function pad(n: int, width: int): string {
        let text = String(n);
        while (text.length < width)
            text = `0${text}`;
        return text;
    }

    function themeUrl(name: string): string {
        return `file://${theme.dir}/${name}`;
    }

    function frameUrl(index: int): string {
        return themeUrl(`${theme.prefix}${pad(theme.first + index, theme.pad)}.png`);
    }

    function hex(value: string): string {
        return value.startsWith("#") ? value : `#${value}`;
    }

    // The user's colours, as the shell wrote them, in a light scheme too: the logo is drawn in them.
    function loadScheme(text: string): void {
        try {
            const scheme = JSON.parse(text);
            if (!scheme.colours)
                return;
            if (scheme.colours.surface)
                root.background = hex(scheme.colours.surface);
            if (scheme.colours.primary)
                root.accent = hex(scheme.colours.primary);
            if (scheme.colours.onSurface)
                root.ink = hex(scheme.colours.onSurface);
        } catch (e) {
            // keep the defaults
        }
    }

    onReadyToCloseChanged: {
        if (readyToClose)
            settleTimer.start();
    }

    Timer {
        interval: root.minMs
        running: true
        onTriggered: root.minElapsed = true
    }

    Timer {
        id: settleTimer

        interval: root.settleMs
        onTriggered: root.closing = true
    }

    Timer {
        interval: root.maxMs
        running: true
        onTriggered: root.closing = true
    }

    // FileView does not notice a file that appears later, so it is read again every 400 ms.
    Timer {
        interval: 400
        repeat: true
        running: !root.preview && !root.shellReady && !root.closing
        onTriggered: readyFile.reload()
    }

    FileView {
        id: readyFile

        path: `${root.runtimeDir}/caelestia-shell-ready`
        printErrors: false
        onLoaded: root.shellReady = true
    }

    FileView {
        path: root.schemePath
        printErrors: false
        onLoaded: {
            root.loadScheme(text());
            root.schemeReady = true;
        }
        onLoadFailed: root.schemeReady = true
    }

    // A scheme that is slow to read, or an event that does not come, must not keep the screen bare.
    Timer {
        interval: 1500
        running: true
        onTriggered: root.schemeReady = true
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win

            required property ShellScreen modelData

            screen: modelData
            color: "transparent"
            WlrLayershell.namespace: "caelestia-splash"
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop {
                        position: 0
                        color: root.backgroundTop
                    }
                    GradientStop {
                        position: 1
                        color: root.backgroundBottom
                    }
                }
                opacity: root.closing || !root.schemeReady ? 0 : 1

                Behavior on opacity {
                    NumberAnimation {
                        duration: 350
                    }
                }

                onOpacityChanged: {
                    if (root.closing && opacity === 0)
                        Qt.quit();
                }

                Loader {
                    anchors.fill: parent
                    sourceComponent: root.kind === "frames" ? framesComp : root.kind === "star" ? starComp : caelestiaComp
                }
            }
        }
    }

    // The Caelestia design: the logo and three dots that pulse one after the other.
    Component {
        id: caelestiaComp

        Item {
            Column {
                anchors.centerIn: parent
                spacing: 28

                // The logo, drawn from its own paths (the ones in logo.svg) so that its two colors are
                // the user's: the crescent and the stars take the accent, the swoosh takes the text
                // color, light on a dark scheme and dark on a light one. As a picture the swoosh was a
                // fixed light grey that vanished on a light background. The item is the layer, so the
                // edges are smoothed at the size it is shown in and not at the size of the paths.
                Item {
                    visible: root.showLogo
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 96
                    height: 96
                    layer.enabled: true
                    layer.samples: 4

                    Shape {
                        // The group of logo.svg: its scale, and its shift down, both times the 96 / 128
                        // the 128 by 128 box is shown at.
                        transform: [
                            Scale {
                                xScale: 0.0670432725
                                yScale: 0.0670432725
                            },
                            Translate {
                                y: 14.12957925
                            }
                        ]

                        ShapePath {
                            fillColor: root.accent
                            fillRule: ShapePath.WindingFill
                            strokeColor: "transparent"

                            PathSvg {
                                path: "m 475.79,480.32 c -86.73,17.9 -182.84,47.16 -250.83,69.53 -5.5,1.81 -9.8,-4.87 -5.89,-9.13 60.07,-65.44 108.05,-148.67 108.05,-148.67 96.79,-164.04 256.76,-262.84 445.51,-236.29 72.29,10.17 137.85,37.79 192.94,78.01 11.05,8.07 12.75,23.9 3.52,34 -4.45,4.87 -10.63,7.45 -16.89,7.45 -3.82,0 -7.66,-0.96 -11.16,-2.96 C 905.11,251.68 864.76,242.2 821.3,236.08 674.89,215.49 537.25,289.19 474.05,413.1 c -10.51,20.6 -6.82,42.54 5.03,58.29 2.5,3.32 0.78,8.1 -3.29,8.94 z"
                            }
                        }

                        ShapePath {
                            fillColor: root.ink
                            fillRule: ShapePath.WindingFill
                            strokeColor: "transparent"

                            PathSvg {
                                path: "m 1151.76,579.16 c -7.27,1.28 -14.11,-4.09 -14.33,-11.48 -0.63,-21.91 1.71,-43.51 -2.22,-64.64 -3.08,-16.6 -18.52,-27.99 -35.31,-26.16 l -0.57,0.07 c -73,8.06 -275.36,34.58 -536.62,104.13 -77.07,20.51 -109.86,111.75 -63.34,176.52 51.67,71.96 132.35,122.14 228.17,135.62 132.09,18.58 257.01,-37.58 326.59,-141.44 6.04,-9.03 17.25,-13.06 27.57,-9.65 10.22,3.37 16.47,12.84 16.47,22.82 0,3.66 -0.84,7.38 -2.63,10.9 -80.84,158.87 -256.15,256.54 -442.55,230.31 -87.67,-12.33 -165.46,-50.36 -226.74,-105.39 -0.05,-0.04 -0.11,-0.09 -0.17,-0.13 C 344.72,843.18 261.73,788.92 121.54,766.76 -88.91,733.49 14.95,668.95 126.72,612.74 c 82.29,-35.04 281.44,-88.35 405.1,-120 1.75,-0.29 3.52,-0.67 5.29,-1.13 16.96,-4.44 35.79,-9.29 56.17,-14.41 11.83,-2.95 21.61,-5.37 28.86,-7.16 1.02,-0.25 1.98,-0.49 2.89,-0.71 3.47,-0.85 6.21,-1.52 8.16,-1.99 0.31,-0.08 0.63,-0.16 0.95,-0.24 0.3,-0.07 0.58,-0.14 0.82,-0.2 0.22,-0.05 0.44,-0.1 0.66,-0.16 0.16,-0.04 0.33,-0.08 0.5,-0.12 0.11,-0.03 0.22,-0.05 0.34,-0.08 0.13,-0.03 0.19,-0.05 0.19,-0.05 118.77,-28.85 275.31,-62.84 421.88,-82.11 11.37,-1.49 22.68,-2.86 33.89,-4.16 83.78,-9.75 162.97,-14.06 228.32,-9.08 284.26,21.75 -52.61,187.49 -168.98,208.02 z"
                            }
                        }

                        ShapePath {
                            fillColor: root.accent
                            fillRule: ShapePath.WindingFill
                            strokeColor: "transparent"

                            PathSvg {
                                path: "m 1096.96,0.7 c -3.27,23.29 -19.27,94.08 -93.49,102.76 -0.95,0.11 -0.95,1.47 0,1.58 74.22,8.68 90.24,79.48 93.51,102.76 0.13,0.93 1.47,0.93 1.6,0 3.27,-23.29 19.27,-94.08 93.49,-102.76 0.95,-0.11 0.95,-1.47 0,-1.58 -74.22,-8.68 -90.24,-79.48 -93.51,-102.76 -0.13,-0.93 -1.47,-0.93 -1.6,0 z"
                            }
                        }

                        ShapePath {
                            fillColor: root.accent
                            fillRule: ShapePath.WindingFill
                            strokeColor: "transparent"

                            PathSvg {
                                path: "m 1267.37,173.28 c -2.44,14.41 -12.09,48.65 -49,54.42 -0.92,0.14 -0.92,1.43 0,1.57 36.91,5.77 46.57,40.02 49.01,54.42 0.15,0.89 1.44,0.89 1.59,0 2.44,-14.41 12.09,-48.65 49,-54.42 0.92,-0.14 0.92,-1.43 0,-1.57 -36.91,-5.77 -46.57,-40.02 -49.01,-54.42 -0.15,-0.89 -1.44,-0.89 -1.59,0 z"
                            }
                        }

                        ShapePath {
                            fillColor: root.accent
                            fillRule: ShapePath.WindingFill
                            strokeColor: "transparent"

                            PathSvg {
                                path: "m 1259.85,729.09 c -2.11,11.28 -9.63,35.23 -35.8,39.95 -0.89,0.16 -0.89,1.4 0,1.56 26.17,4.72 33.7,28.66 35.81,39.95 0.16,0.88 1.42,0.88 1.59,0 2.11,-11.28 9.63,-35.23 35.8,-39.95 0.89,-0.16 0.89,-1.4 0,-1.56 -26.17,-4.72 -33.7,-28.66 -35.81,-39.95 -0.16,-0.88 -1.42,-0.88 -1.59,0 z"
                            }
                        }
                    }
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 12

                    Repeater {
                        model: 3

                        Rectangle {
                            id: dot

                            required property int index

                            width: 10
                            height: 10
                            radius: 5
                            color: root.accent
                            opacity: 0.25

                            SequentialAnimation on opacity {
                                loops: Animation.Infinite

                                PauseAnimation {
                                    duration: dot.index * 200
                                }
                                NumberAnimation {
                                    to: 1
                                    duration: 400
                                }
                                NumberAnimation {
                                    to: 0.25
                                    duration: 400
                                }
                                PauseAnimation {
                                    duration: (2 - dot.index) * 200
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // A two-step theme: a ring of numbered frames played in a loop, and a watermark. All frames
    // are loaded at once and only the current one is shown, so that switching does not flicker.
    // An image is placed the way Plymouth does: the alignment fraction applies to the free space.
    Component {
        id: framesComp

        Item {
            id: stage

            property int frame: 0

            Timer {
                interval: Math.round(1000 / (root.theme.fps || 25))
                running: true
                repeat: true
                onTriggered: stage.frame = (stage.frame + 1) % root.theme.count
            }

            Repeater {
                model: root.theme.count

                Image {
                    required property int index

                    visible: index === stage.frame
                    source: root.frameUrl(index)
                    x: (stage.width - width) * root.theme.x
                    y: (stage.height - height) * root.theme.y
                }
            }

            Image {
                visible: !!root.theme.watermark
                source: root.theme.watermark ? root.themeUrl(root.theme.watermark.file) : ""
                x: root.theme.watermark ? (stage.width - width) * root.theme.watermark.x : 0
                y: root.theme.watermark ? (stage.height - height) * root.theme.watermark.y : 0
            }
        }
    }

    // The fade-in theme: one star that fades in and out in the middle.
    Component {
        id: starComp

        Item {
            Image {
                anchors.centerIn: parent
                source: root.themeUrl(root.theme.file)
                opacity: 0.2

                SequentialAnimation on opacity {
                    loops: Animation.Infinite

                    NumberAnimation {
                        to: 1
                        duration: 1200
                    }
                    NumberAnimation {
                        to: 0.2
                        duration: 1200
                    }
                }
            }
        }
    }
}

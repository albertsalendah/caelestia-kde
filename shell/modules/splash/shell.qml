import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// The login splash: a full-screen cover that the session program starts, as a second small
// Quickshell instance, as soon as KWin is up. It stays until the main shell says it is ready
// (it writes $XDG_RUNTIME_DIR/caelestia-shell-ready) and the minimum time has passed, then fades
// out and exits. If the shell never says so, it leaves after maxMs anyway, so a broken shell
// cannot leave the screen covered.
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

    property color background: "#12131a"
    property color accent: "#b8c3ff"
    property bool minElapsed: false
    property bool shellReady: false
    property bool closing: false

    readonly property bool readyToClose: minElapsed && (preview || shellReady)

    function hex(value: string): string {
        return value.startsWith("#") ? value : `#${value}`;
    }

    // The user's colours, as the shell wrote them. A light scheme keeps the dark default: the
    // logo has white parts that would vanish on it.
    function loadScheme(text: string): void {
        try {
            const scheme = JSON.parse(text);
            if (scheme.mode === "light" || !scheme.colours)
                return;
            if (scheme.colours.surface)
                root.background = hex(scheme.colours.surface);
            if (scheme.colours.primary)
                root.accent = hex(scheme.colours.primary);
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
        onLoaded: root.loadScheme(text())
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
                color: root.background
                opacity: root.closing ? 0 : 1

                Behavior on opacity {
                    NumberAnimation {
                        duration: 350
                    }
                }

                onOpacityChanged: {
                    if (root.closing && opacity === 0)
                        Qt.quit();
                }

                Column {
                    anchors.centerIn: parent
                    spacing: 28

                    Image {
                        visible: root.showLogo
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 96
                        height: 96
                        source: Qt.resolvedUrl("../../assets/logo.svg")
                        sourceSize: Qt.size(192, 192)
                        fillMode: Image.PreserveAspectFit
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
    }
}

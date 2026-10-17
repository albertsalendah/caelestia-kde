pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../utils/scripts/splash.js" as Logic

// The settings behind Nexus -> Splash.
//
// Login splash: ~/.config/caelestia-splashrc is read with FileView and changed with
// kwriteconfig6. The session program reads the same file at login, so a change counts from the
// next login; preview() runs the splash now. It shows the Caelestia design or a Plasma
// look-and-feel splash theme.
//
// Boot splash: the Plymouth theme. The list and the current theme are read with
// plymouth-set-default-theme, and applying one runs it as root through pkexec with -R, which
// rebuilds the boot image (it can take a minute or more).
Singleton {
    id: root

    readonly property string rcPath: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/caelestia-splashrc"
    readonly property string splashQml: Quickshell.shellDir + "/modules/splash/shell.qml"

    // The login splash's settings, as Logic.settingsFrom returns them.
    property string configText: ""
    readonly property var settings: Logic.settingsFrom(root.configText)
    // False when the splash's QML is not in this install (an install from before it existed).
    property bool splashInstalled: false
    property string error: ""
    property var queue: []

    // The Plasma splash themes the login can show, and whether ksplashqml is there to run them.
    property var plasmaThemes: []
    property bool ksplashAvailable: false

    // Boot splash.
    property var themes: []
    // What the splash can draw of each Plymouth theme ({name: spec}, see Logic.buildSpec).
    property var specs: ({})
    property string currentTheme: ""
    // "idle", "applying", "done", "cancelled" or "failed".
    property string bootState: "idle"
    readonly property bool plymouthAvailable: root.themes.length > 0

    function setEnabled(enabled: bool): void {
        write("Enabled", enabled);
    }

    function setShowLogo(show: bool): void {
        write("ShowLogo", show);
    }

    // Chooses what the login shows: "" is the Caelestia design, else the id of a Plasma
    // look-and-feel theme whose splash ksplashqml runs.
    function setPlasmaTheme(id: string): void {
        if (id !== "" && !Logic.validTheme(id))
            return;
        write("PlasmaTheme", id);
    }

    function setMinSeconds(seconds: int): void {
        write("MinSeconds", seconds);
    }

    function write(key: string, value: var): void {
        enqueue(Logic.writeArgs(key, value));
    }

    function enqueue(args: var): void {
        root.error = "";
        root.queue = root.queue.concat([args]);
        if (!writeProcess.running)
            next();
    }

    function next(): void {
        if (root.queue.length === 0) {
            rcFile.reload();
            return;
        }
        writeProcess.command = ["kwriteconfig6"].concat(root.queue[0]);
        root.queue = root.queue.slice(1);
        writeProcess.running = true;
    }

    // Shows the login splash now: the chosen Plasma theme through ksplashqml's own test mode, or
    // the Caelestia design.
    function preview(): void {
        const command = Logic.loginPreviewCommand(root.splashQml, root.settings);
        if (command.length > 0)
            Quickshell.execDetached(command);
    }

    // Shows a Plymouth theme now, the way the login splash would draw it. The boot itself is
    // drawn by Plymouth, so this is only close to it (a theme made of a program is not drawn).
    function previewTheme(name: string): void {
        Quickshell.execDetached(Logic.previewCommand(root.splashQml, root.settings, root.specs[name] ?? null));
    }

    function refreshThemes(): void {
        themesProcess.running = true;
        currentProcess.running = true;
        surveyProcess.running = true;
        lnfProcess.running = true;
    }

    function applyTheme(theme: string): void {
        const command = Logic.applyCommand(theme);
        if (command.length === 0 || root.bootState === "applying")
            return;
        root.bootState = "applying";
        applyProcess.command = command;
        applyProcess.running = true;
    }

    Component.onCompleted: refreshThemes()

    Process {
        id: writeProcess

        onExited: code => {
            if (code !== 0)
                root.error = "write-failed";
            root.next();
        }
    }

    Process {
        id: themesProcess

        command: ["plymouth-set-default-theme", "--list"]
        stdout: StdioCollector {
            onStreamFinished: root.themes = Logic.parseThemes(text)
        }
    }

    Process {
        id: surveyProcess

        command: Logic.surveyCommand()
        stdout: StdioCollector {
            onStreamFinished: root.specs = Logic.specsFrom(text)
        }
    }

    Process {
        id: lnfProcess

        command: Logic.lnfCommand((Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") + "/.local/share")) + "/plasma/look-and-feel")
        stdout: StdioCollector {
            onStreamFinished: {
                const found = Logic.parseLnf(text);
                root.ksplashAvailable = found.ksplash;
                root.plasmaThemes = found.themes;
            }
        }
    }

    Process {
        id: currentProcess

        command: ["plymouth-set-default-theme"]
        stdout: StdioCollector {
            onStreamFinished: root.currentTheme = text.trim()
        }
    }

    Process {
        id: applyProcess

        onExited: code => {
            root.bootState = Logic.applyResult(code);
            root.refreshThemes();
        }
    }

    FileView {
        id: rcFile

        path: root.rcPath
        watchChanges: true
        printErrors: false

        onLoaded: root.configText = text()
        onLoadFailed: root.configText = ""
        onFileChanged: reload()
    }

    FileView {
        path: root.splashQml
        printErrors: false

        onLoaded: root.splashInstalled = true
        onLoadFailed: root.splashInstalled = false
    }
}

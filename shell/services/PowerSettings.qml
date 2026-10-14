pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../utils/scripts/power.js" as Logic

// powerdevil's settings (dim, screen off, suspend, power profile) for the plugged-in and
// on-battery profiles. They are read from ~/.config/powerdevilrc and changed with kwriteconfig6;
// powerdevil is then told to read the file again with refreshStatus, not reparseConfiguration:
// the latter only reloads the global settings, so a new power profile would wait for the next
// change of power source, while refreshStatus also reloads the active profile and applies it.
// Nothing here can blank a screen or lose work on its own, so a change applies at once with no
// keep-or-revert step.
Singleton {
    id: root

    readonly property string rcPath: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/powerdevilrc"

    // The parsed file, as Logic.parseIni returns it. Empty when the file does not exist yet:
    // powerdevil only creates it once something differs from its defaults.
    property var config: ({})
    property string error: ""

    // kwriteconfig6 argument lists still to run.
    property var queue: []

    function settings(profile: string): var {
        return Logic.settingsFor(root.config, profile);
    }

    function setDelay(profile: string, kind: string, seconds: int): void {
        enqueue(profile, Logic.changesForDelay(kind, seconds, settings(profile)));
    }

    function setPowerProfile(profile: string, name: string): void {
        enqueue(profile, Logic.changesForProfile(name));
    }

    function enqueue(profile: string, changes: var): void {
        root.error = "";
        root.queue = root.queue.concat(changes.map(c => Logic.buildWriteArgs(profile, c)));
        if (!writeProcess.running && !reparseProcess.running)
            next();
    }

    function next(): void {
        if (root.queue.length === 0) {
            reparseProcess.running = true;
            return;
        }
        writeProcess.command = ["kwriteconfig6"].concat(root.queue[0]);
        root.queue = root.queue.slice(1);
        writeProcess.running = true;
    }

    Process {
        id: writeProcess

        onExited: code => {
            if (code !== 0)
                root.error = "write-failed";
            root.next();
        }
    }

    Process {
        id: reparseProcess

        command: ["qdbus6", "org.kde.Solid.PowerManagement", "/org/kde/Solid/PowerManagement", "org.kde.Solid.PowerManagement.refreshStatus"]
        onExited: code => {
            if (code !== 0)
                root.error = "reload-failed";
            rcFile.reload();
        }
    }

    FileView {
        id: rcFile

        path: root.rcPath
        watchChanges: true
        printErrors: false

        onLoaded: root.config = Logic.parseIni(text())
        onLoadFailed: root.config = ({})
        onFileChanged: reload()
    }
}

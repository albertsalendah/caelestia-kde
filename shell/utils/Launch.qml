pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config

Singleton {
    id: root

    property bool hasSystemdCat: false
    property bool hasApp2Unit: false

    // Terminals that take a command only after a flag. foot and kitty run whatever follows
    // their name, so they are not listed. Settings > Apps stores the picked app's launch
    // command (for Konsole just "konsole"), which is why the flag is added here, not there.
    readonly property var terminalExecFlags: ({
            "konsole": ["-e"],
            "alacritty": ["-e"],
            "xterm": ["-e"],
            "urxvt": ["-e"],
            "st": ["-e"],
            "ghostty": ["-e"],
            "tilix": ["-e"],
            "lxterminal": ["-e"],
            "xfce4-terminal": ["-x"],
            "terminator": ["-x"],
            "gnome-terminal": ["--"],
            "wezterm": ["start", "--"]
        })

    /// The command that runs `command` in the configured terminal. The flag the terminal needs
    /// before a command is added unless the setting already ends with it (for example
    /// ["konsole", "-e"]), so both forms of the setting work.
    function terminalCommand(command: list<string>): list<string> {
        const terminal = GlobalConfig.general.apps.terminal;
        if (terminal.length === 0)
            return command;

        const known = root.terminalExecFlags[terminal[0].split('/').pop()];
        const flags = Array.isArray(known) ? known : [];
        const offset = terminal.length - flags.length;
        const carriesFlags = flags.length > 0 && offset > 0 && flags.every((flag, i) => terminal[offset + i] === flag);
        return [...terminal, ...(carriesFlags ? [] : flags), ...command];
    }

    /// Wraps a command so it does not run on the shell's stdio.
    /// Returns the command unchanged when nothing is available to wrap it.
    function wrap(command: list<string>): list<string> {
        if (command.length === 0)
            return command;

        if (root.hasApp2Unit) {
            const appName = command[0].split('/').pop();
            if (root.hasSystemdCat)
                return ["app2unit", "-a", appName, "--", "systemd-cat", "--", ...command];
            return ["app2unit", "-a", appName, "--", ...command];
        }

        if (root.hasSystemdCat)
            return ["systemd-run", "--user", "--scope", "--quiet", "systemd-cat", "--", ...command];

        return ["systemd-run", "--user", "--scope", "--quiet", "--", ...command];
    }

    function exec(command: list<string>): void {
        if (command.length > 0)
            Quickshell.execDetached(root.wrap(command));
    }

    function launchEntry(entry: DesktopEntry): void {
        if (entry.runInTerminal)
            Quickshell.execDetached({
                command: root.wrap(root.terminalCommand([`${Quickshell.shellDir}/assets/wrap_term_launch.sh`, ...entry.command])),
                workingDirectory: entry.workingDirectory
            });
        else
            Quickshell.execDetached({
                command: root.wrap(entry.command),
                workingDirectory: entry.workingDirectory
            });
    }

    Process {
        running: true
        command: ["sh", "-c", "command -v systemd-cat >/dev/null 2>&1 && echo cat; command -v app2unit >/dev/null 2>&1 && echo unit"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.hasSystemdCat = text.includes("cat");
                root.hasApp2Unit = text.includes("unit");
            }
        }
    }
}

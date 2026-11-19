pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config
import Caelestia.Images

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
    /// ["konsole", "-e"]), so both forms of the setting work. terminalOverride replaces the
    /// configured terminal for a caller that has resolved its own.
    function terminalCommand(command: list<string>, terminalOverride: var): list<string> {
        const terminal = terminalOverride ?? GlobalConfig.general.apps.terminal;
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

    /// Whether `url` names a web page. The two callers that need this — a link in a
    /// notification body and a portal's redirect — both act on text someone else
    /// chose, and only a page may be opened from either.
    function isWebUrl(url: string): bool {
        return /^https?:\/\//i.test(url || "");
    }

    /// Opens a link clicked in a notification. The URL is sender-controlled text, so
    /// only web and mail links go through: another scheme (`file://`, `smb://`, an
    /// application's own handler) would turn one click into whatever the sender named.
    function openUrl(url: string): void {
        if (!root.isWebUrl(url) && !/^mailto:/i.test(url || ""))
            return;

        Qt.openUrlExternally(url);
    }

    /// Whether KDE ships a settings module by this name. Printing, the on-screen
    /// keyboard and the accessibility options stay KDE's to own: the shell gives them a
    /// front door, and says so when the module is missing rather than opening a dead page.
    function kcmAvailable(name: string): bool {
        const dirs = ["/usr/lib/qt6/plugins/plasma/kcms/systemsettings", "/usr/lib64/qt6/plugins/plasma/kcms/systemsettings"];
        return dirs.some(dir => IUtils.fileExists(`${dir}/${name}.so`));
    }

    /// Opens one of those modules.
    function kcm(name: string): void {
        root.exec(["systemsettings", name]);
    }

    function launchInTerminal(command: list<string>, workingDirectory: string): void {
        Quickshell.execDetached({
            command: root.wrap(root.terminalCommand([`${Quickshell.shellDir}/assets/wrap_term_launch.sh`, ...command])),
            workingDirectory: workingDirectory
        });
    }

    function launchEntry(entry: DesktopEntry): void {
        if (entry.runInTerminal)
            root.launchInTerminal(entry.command, entry.workingDirectory);
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

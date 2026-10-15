pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../utils/scripts/displays.js" as Logic

// Monitors as `kscreen-doctor` sees them, and the changes made to them from
// Nexus -> Display. Every change is applied at once and then has to be kept
// within `confirmSeconds`, or the monitors go back to what they were: a bad mode
// can blank a screen, and this session has no System Settings to undo it.
// Brightness is the exception: it is applied as the slider moves and has nothing to keep. So is
// choosing the primary monitor, which cannot blank a screen.
// A change that leaves a monitor on top of another, or cut off from the rest, also moves that
// monitor to the nearest place where the layout is valid again (Logic.settleLayout).
Singleton {
    id: root

    readonly property int confirmSeconds: 15

    property var outputs: []
    property bool loaded: false

    // Monitor names from their EDID: {"HDMI-A-1": {vendor, model}}. Read again when the list of
    // monitors changes, not on every refresh.
    property var edids: ({})
    property bool edidAgain: false

    // True while a change is being applied or undone; the page does not re-read the monitors then.
    readonly property bool busy: applyProcess.running || revertProcess.running

    // Brightness of each monitor in percent: {"HDMI-A-1": 41}. Not part of `outputs`, so that a
    // change does not rebuild the rows while a slider is being dragged.
    property var brightness: ({})
    // True from the first move of a slider until its last change has been applied; what
    // kscreen-doctor reports in the meantime is older than the slider and is not shown.
    property bool adjusting: false
    property var pendingBrightness: ({})

    // "" or a code: unknown-output, unknown-mode, unknown-rotation, invalid-position,
    // invalid-mirror, overlap, last-enabled, apply-failed, brightness-failed
    property string error: ""

    // Readings still to be made after a monitor was plugged in or out, and failed readings in a row.
    property int recheck: 0
    property int retries: 0

    // The change being applied is not to be kept or reverted (the primary monitor).
    property bool quiet: false

    property bool confirming: false
    property int secondsLeft: 0
    property var previous: []

    function refresh(): void {
        if (!listProcess.running)
            listProcess.running = true;
    }

    function apply(changes: var): void {
        run(changes, true);
    }

    function applyQuietly(changes: var): void {
        run(changes, false);
    }

    function run(changes: var, keepPrompt: bool): void {
        if (applyProcess.running || revertProcess.running)
            return;

        const settled = Logic.settleLayout(root.outputs, changes);
        const problem = Logic.validate(root.outputs, settled);
        if (problem !== "") {
            root.error = problem;
            return;
        }

        root.error = "";
        root.quiet = !keepPrompt;
        // A second change while the first is still waiting keeps the original state to go back to.
        if (keepPrompt && !root.confirming)
            root.previous = Logic.snapshot(root.outputs);

        applyProcess.command = ["kscreen-doctor"].concat(Logic.buildApplyArgs(settled));
        applyProcess.running = true;
    }

    function setEnabled(name: string, enabled: bool): void {
        apply([
            {
                name: name,
                enabled: enabled
            }
        ]);
    }

    function setMode(name: string, modeId: string): void {
        apply([
            {
                name: name,
                modeId: modeId
            }
        ]);
    }

    function setScale(name: string, scale: real): void {
        apply([
            {
                name: name,
                scale: scale
            }
        ]);
    }

    // Where the monitor goes in the layout, in logical pixels (see Logic.snapLayout).
    function setPosition(name: string, x: real, y: real): void {
        apply([
            {
                name: name,
                pos: {
                    x: Math.round(x),
                    y: Math.round(y)
                }
            }
        ]);
    }

    function setPrimary(name: string): void {
        applyQuietly(Logic.primaryChanges(root.outputs, name));
    }

    // Show the same picture as the primary monitor, or go back to extending the desktop.
    function setCopy(name: string, copy: bool): void {
        apply(Logic.copyChanges(root.outputs, name, copy));
    }

    // The kernel reported a change at a monitor port. KWin needs a moment to catch up, so the
    // monitors are read again a little later and once more after that.
    function hotplugged(): void {
        root.recheck = 2;
        hotplugTimer.restart();
    }

    function setRotation(name: string, rotation: string): void {
        apply([
            {
                name: name,
                rotation: rotation
            }
        ]);
    }

    // The slider's value, 0 to 1. The percentage is shown at once; kscreen-doctor is called once
    // the slider has been still for a moment, with the last value of every monitor moved.
    function setBrightness(name: string, value: real): void {
        const percent = Logic.brightnessPercent(value);
        if (root.error === "brightness-failed")
            root.error = "";
        root.brightness = Logic.withBrightness(root.brightness, name, percent);
        root.pendingBrightness = Logic.withBrightness(root.pendingBrightness, name, percent);
        root.adjusting = true;
        brightnessTimer.restart();
    }

    function keep(): void {
        root.confirming = false;
        root.previous = [];
    }

    function revert(): void {
        if (!root.confirming)
            return;

        root.confirming = false;
        const args = Logic.buildRevertArgs(root.previous);
        if (args.length === 0) {
            root.previous = [];
            root.refresh();
            return;
        }

        revertProcess.command = ["kscreen-doctor"].concat(args);
        revertProcess.running = true;
    }

    Process {
        id: listProcess

        command: ["kscreen-doctor", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                // A reading that failed or was cut short is ignored: it would empty the page.
                // Tried again a few times, then the page keeps what it has.
                if (!Logic.isListing(text)) {
                    if (root.retries < 3) {
                        root.retries += 1;
                        retryTimer.restart();
                    }
                    return;
                }
                root.retries = 0;

                // Only replace the list when something changed: a new list rebuilds the rows of
                // the page, which would close a menu that is open.
                const levels = Logic.parseBrightness(text);
                if (!root.adjusting && !Logic.sameOutputs(levels, root.brightness))
                    root.brightness = levels;

                const parsed = Logic.parseOutputs(text);
                if (!root.loaded || !Logic.sameOutputs(parsed, root.outputs)) {
                    root.outputs = parsed;
                    if (edidProcess.running)
                        root.edidAgain = true;
                    else
                        edidProcess.running = true;
                }
                root.loaded = true;
            }
        }
    }

    Timer {
        id: hotplugTimer

        interval: 1500
        repeat: true
        onTriggered: {
            root.refresh();
            root.recheck -= 1;
            if (root.recheck <= 0)
                hotplugTimer.stop();
        }
    }

    Timer {
        id: retryTimer

        interval: 1000
        onTriggered: root.refresh()
    }

    Process {
        id: edidProcess

        command: ["bash", "-c", Logic.EDID_SCRIPT, "edid", "/sys/class/drm"]
        stdout: StdioCollector {
            onStreamFinished: {
                const names = Logic.parseEdidList(text);
                if (!Logic.sameOutputs(names, root.edids))
                    root.edids = names;
                if (root.edidAgain) {
                    root.edidAgain = false;
                    edidProcess.running = true;
                }
            }
        }
    }

    Process {
        id: applyProcess

        onExited: code => {
            if (code === 0) {
                if (!root.quiet) {
                    root.confirming = true;
                    root.secondsLeft = root.confirmSeconds;
                }
            } else {
                root.error = "apply-failed";
                if (!root.confirming)
                    root.previous = [];
            }
            root.refresh();
        }
    }

    Process {
        id: revertProcess

        onExited: {
            root.previous = [];
            root.refresh();
        }
    }

    Process {
        id: brightnessProcess

        onExited: code => {
            if (code !== 0)
                root.error = "brightness-failed";
            root.adjusting = Object.keys(root.pendingBrightness).length > 0 || brightnessTimer.running;
            root.refresh();
        }
    }

    Timer {
        id: brightnessTimer

        interval: 300
        onTriggered: {
            if (brightnessProcess.running) {
                brightnessTimer.restart();
                return;
            }

            const args = Logic.buildBrightnessArgs(root.pendingBrightness);
            root.pendingBrightness = ({});
            if (args.length === 0) {
                root.adjusting = false;
                return;
            }

            brightnessProcess.command = ["kscreen-doctor"].concat(args);
            brightnessProcess.running = true;
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.confirming
        onTriggered: {
            root.secondsLeft -= 1;
            if (root.secondsLeft <= 0)
                root.revert();
        }
    }
}

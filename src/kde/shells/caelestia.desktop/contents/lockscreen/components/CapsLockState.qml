import QtQuick
import org.kde.plasma.plasma5support as Plasma5Support
import "../LockScreenHelpers.js" as Helpers

// Whether Caps Lock is on, read from the keyboard's LED. It replaces
// org.kde.plasma.private.keyboardindicator, which only plasma-workspace has. Nothing is polled:
// call refresh() when a key is pressed (the LED changes a moment after the key).
Item {
    id: root

    readonly property string command: "cat /sys/class/leds/*::capslock/brightness 2>/dev/null"
    property bool locked: false

    function refresh(): void {
        settle.restart();
    }

    Component.onCompleted: root.refresh()

    Timer {
        id: settle

        interval: 60
        onTriggered: source.connectSource(root.command)
    }

    Plasma5Support.DataSource {
        id: source

        engine: "executable"
        connectedSources: []
        onNewData: (name, data) => {
            root.locked = Helpers.capsLockOn(data.stdout);
            disconnectSource(name);
        }
    }
}

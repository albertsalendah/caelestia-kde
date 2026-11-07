import QtQuick
import org.kde.plasma.plasma5support as Plasma5Support
import ".."
import "../LockScreenHelpers.js" as Helpers

// Whether Caps Lock is on, read from the keyboard's LED. It replaces
// org.kde.plasma.private.keyboardindicator, which only plasma-workspace has. Nothing is polled:
// it is read again when the typed password changes (the password field takes printable keys, so
// the lock screen's own key handler never sees them), when a key is pressed and when a key is
// released, each a moment after the key because the LED changes a moment later. The release
// matters when Caps Lock is turned off: the password does not change then, and the LED may not
// have changed yet by the time the press is read.
Item {
    id: root

    readonly property string command: "cat /sys/class/leds/*::capslock/brightness 2>/dev/null"
    property bool locked: false

    function refresh(): void {
        settle.restart();
    }

    Component.onCompleted: root.refresh()

    Connections {
        target: PasswordSync

        function onPasswordChanged(): void {
            root.refresh();
        }
    }

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

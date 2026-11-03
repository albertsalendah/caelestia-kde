import QtQuick
import org.kde.plasma.plasma5support as Plasma5Support
import "../LockScreenHelpers.js" as Helpers

// The keyboard layouts KWin knows and the one in use, and a way to switch to the next one. It
// replaces plasma-workspace's KeyboardLayoutSwitcher and asks KWin's own D-Bus service for
// the same things, through busctl.
Item {
    id: root

    readonly property string listCommand: "busctl --user call org.kde.keyboard /Layouts org.kde.KeyboardLayouts getLayoutsList 2>/dev/null"
    readonly property string currentCommand: "busctl --user call org.kde.keyboard /Layouts org.kde.KeyboardLayouts getLayout 2>/dev/null"
    readonly property string nextCommand: "busctl --user call org.kde.keyboard /Layouts org.kde.KeyboardLayouts switchToNextLayout 2>/dev/null"
    property var layouts: []
    property int current: 0
    readonly property bool hasMultipleLayouts: layouts.length > 1
    readonly property string longName: current < layouts.length ? layouts[current].longName : ""

    function refresh(): void {
        source.connectSource(root.listCommand);
        source.connectSource(root.currentCommand);
    }

    function switchToNext(): void {
        if (!root.hasMultipleLayouts)
            return;
        root.current = (root.current + 1) % root.layouts.length;
        source.connectSource(root.nextCommand);
    }

    Component.onCompleted: root.refresh()

    Plasma5Support.DataSource {
        id: source

        engine: "executable"
        connectedSources: []
        onNewData: (name, data) => {
            if (name === root.listCommand)
                root.layouts = Helpers.parseLayouts(data.stdout);
            else if (name === root.currentCommand)
                root.current = Helpers.parseUint(data.stdout);
            disconnectSource(name);
        }
    }
}

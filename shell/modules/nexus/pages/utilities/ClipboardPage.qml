import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.modules.nexus.common

PageBase {
    id: root

    // The clipboard icon is one entry of the bar's status icon list. A bar that
    // was set up before the icon existed has no such entry yet.
    readonly property int iconIndex: Config.bar.statusIcons.values.findIndex(entry => entry.id === "clipboard")
    readonly property bool iconShown: root.iconIndex >= 0 && Config.bar.statusIcons.values[root.iconIndex].enabled

    function setIconShown(show: bool): void {
        if (root.iconIndex >= 0)
            GlobalConfig.bar.statusIcons.at(root.iconIndex).enabled = show;
        else if (show)
            GlobalConfig.bar.statusIcons.insert({ id: "clipboard", enabled: true });
    }

    title: qsTr("Clipboard")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            first: true
            text: qsTr("History")
        }

        StepperRow {
            first: true
            label: qsTr("Maximum entries")
            subtext: qsTr("Number of entries available in the launcher")
            reset: ({ node: GlobalConfig.launcher, setting: "clipboardMaxEntries" })
            value: GlobalConfig.launcher.clipboardMaxEntries
            from: 1
            to: 2048
            stepSize: 1
            onMoved: value => GlobalConfig.launcher.clipboardMaxEntries = value
        }

        ToggleRow {
            last: true
            text: qsTr("Confirm clear")
            subtext: qsTr("Ask before clearing the clipboard history")
            reset: ({ node: GlobalConfig.launcher, setting: "confirmClearClipboard" })
            checked: GlobalConfig.launcher.confirmClearClipboard
            onToggled: GlobalConfig.launcher.confirmClearClipboard = checked
        }

        SectionHeader {
            text: qsTr("Status bar")
        }

        ToggleRow {
            first: true
            text: qsTr("Show in status bar")
            subtext: qsTr("A clipboard icon among the status icons; its popout lists the recent clips")
            checked: root.iconShown
            onToggled: root.setIconShown(checked)
        }

        ToggleRow {
            text: qsTr("Open on hover")
            subtext: qsTr("Off: the popout opens when you click the icon and stays until you click elsewhere. Meta+V always opens it that way")
            reset: ({ node: GlobalConfig.bar.status, setting: "clipboardOpenOnHover" })
            checked: Config.bar.status.clipboardOpenOnHover
            onToggled: GlobalConfig.bar.status.clipboardOpenOnHover = checked
        }

        StepperRow {
            last: true
            label: qsTr("Rows visible in popout")
            subtext: qsTr("How many clips the popout shows before its list scrolls")
            reset: ({ node: GlobalConfig.bar.status, setting: "clipboardEntries" })
            value: Config.bar.status.clipboardEntries
            from: 1
            to: 15
            stepSize: 1
            onMoved: value => GlobalConfig.bar.status.clipboardEntries = value
        }
    }
}

pragma ComponentBehavior: Bound

import QtQuick.Layouts
import Caelestia.Config
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Tray")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        ToggleRow {
            first: true
            text: qsTr("Background")
            reset: ({ node: GlobalConfig.bar.tray, setting: "background" })
            checked: Config.bar.tray.background
            onToggled: GlobalConfig.bar.tray.background = checked
        }

        ToggleRow {
            text: qsTr("Recolor icons")
            reset: ({ node: GlobalConfig.bar.tray, setting: "recolour" })
            checked: Config.bar.tray.recolour
            onToggled: GlobalConfig.bar.tray.recolour = checked
        }

        ToggleRow {
            text: qsTr("Compact")
            reset: ({ node: GlobalConfig.bar.tray, setting: "compact" })
            checked: Config.bar.tray.compact
            onToggled: GlobalConfig.bar.tray.compact = checked
        }

        ToggleRow {
            last: true
            text: qsTr("Popout on hover")
            subtext: qsTr("Show the tray menu popout when hovering")
            reset: ({ node: GlobalConfig.bar.popouts, setting: "tray" })
            checked: Config.bar.popouts.tray
            onToggled: GlobalConfig.bar.popouts.tray = checked
        }
    }
}

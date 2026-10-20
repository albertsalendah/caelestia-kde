pragma ComponentBehavior: Bound

import QtQuick.Layouts
import Caelestia.Config
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Clock")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        ToggleRow {
            first: true
            text: qsTr("Background")
            reset: ({ node: GlobalConfig.bar.clock, setting: "background" })
            checked: Config.bar.clock.background
            onToggled: GlobalConfig.bar.clock.background = checked
        }

        ToggleRow {
            text: qsTr("Show date")
            reset: ({ node: GlobalConfig.bar.clock, setting: "showDate" })
            checked: Config.bar.clock.showDate
            onToggled: GlobalConfig.bar.clock.showDate = checked
        }

        ToggleRow {
            text: qsTr("Show icon")
            reset: ({ node: GlobalConfig.bar.clock, setting: "showIcon" })
            checked: Config.bar.clock.showIcon
            onToggled: GlobalConfig.bar.clock.showIcon = checked
        }

        ToggleRow {
            text: qsTr("Show seconds")
            subtext: qsTr("Add a seconds line to the clock")
            reset: ({ node: GlobalConfig.bar.clock, setting: "showSeconds" })
            checked: Config.bar.clock.showSeconds
            onToggled: GlobalConfig.bar.clock.showSeconds = checked
        }

        ToggleRow {
            last: true
            text: qsTr("Calendar popout")
            subtext: qsTr("Show a mini calendar when hovering the clock")
            reset: ({ node: GlobalConfig.bar.popouts, setting: "clock" })
            checked: Config.bar.popouts.clock
            onToggled: GlobalConfig.bar.popouts.clock = checked
        }
    }
}

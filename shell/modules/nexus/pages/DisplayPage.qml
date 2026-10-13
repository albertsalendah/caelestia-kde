pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common
import "../../../utils/scripts/displays.js" as Logic

PageBase {
    id: root

    title: qsTr("Display")

    function errorText(code: string): string {
        switch (code) {
        case "last-enabled":
            return qsTr("At least one monitor has to stay enabled.");
        case "unknown-output":
            return qsTr("That monitor is no longer connected.");
        case "unknown-mode":
            return qsTr("That mode is not available for this monitor.");
        default:
            return qsTr("The display settings could not be applied.");
        }
    }

    // Menu entries made at run time, because a monitor's modes are only known once it is read.
    function makeItems(entries: var): var {
        return entries.map(e => itemComp.createObject(root, {
                text: e.text,
                value: e.value
            }));
    }

    Component.onCompleted: Displays.refresh()

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        Component {
            id: itemComp

            MenuItem {}
        }

        ConnectedRect {
            first: true
            last: true
            visible: Displays.confirming
            Layout.fillWidth: true
            Layout.bottomMargin: Tokens.spacing.largeIncreased
            implicitHeight: promptRow.implicitHeight + Tokens.padding.medium * 2

            RowLayout {
                id: promptRow

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.medium

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Keep these display settings? Going back in %1 s").arg(Displays.secondsLeft)
                    font: Tokens.font.body.small
                    wrapMode: Text.WordWrap
                }

                IconTextButton {
                    text: qsTr("Revert")
                    icon: "undo"
                    type: TextButton.Tonal
                    onClicked: Displays.revert()
                }

                IconTextButton {
                    text: qsTr("Keep")
                    icon: "check"
                    type: TextButton.Filled
                    onClicked: Displays.keep()
                }
            }
        }

        StyledText {
            visible: Displays.error !== ""
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.padding.small
            Layout.bottomMargin: Tokens.spacing.extraSmall
            text: root.errorText(Displays.error)
            color: Colours.palette.m3error
            font: Tokens.font.body.small
            wrapMode: Text.WordWrap
        }

        StyledText {
            visible: Displays.loaded && Displays.outputs.length === 0
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.padding.small
            text: qsTr("No monitors were found.")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.small
        }

        Repeater {
            model: Displays.outputs

            ColumnLayout {
                id: monitor

                required property var modelData
                required property int index

                readonly property string resKey: Logic.currentResolutionKey(modelData)
                readonly property var resItems: root.makeItems(Logic.resolutionsOf(modelData).map(r => ({
                            text: r.label,
                            value: r.key
                        })))
                readonly property var rateItems: root.makeItems(Logic.refreshRatesFor(modelData, resKey).map(r => ({
                            text: r.label,
                            value: r.id
                        })))
                readonly property var scaleItems: root.makeItems(Logic.scalePresets(modelData.scale).map(s => ({
                            text: s.label,
                            value: s.value
                        })))

                Layout.fillWidth: true
                spacing: Tokens.spacing.extraSmall / 2

                SectionHeader {
                    first: monitor.index === 0
                    text: monitor.modelData.name
                }

                ToggleRow {
                    first: true
                    last: !monitor.modelData.enabled
                    text: qsTr("Enabled")
                    subtext: qsTr("Turn this monitor on or off")
                    checked: monitor.modelData.enabled
                    onToggled: {
                        Displays.setEnabled(monitor.modelData.name, checked);
                        checked = Qt.binding(() => monitor.modelData.enabled);
                    }
                }

                SelectRow {
                    visible: monitor.modelData.enabled
                    label: qsTr("Resolution")
                    menuItems: monitor.resItems
                    active: monitor.resItems.find(i => i.value === monitor.resKey) ?? null
                    fallbackText: qsTr("Unknown")
                    onSelected: item => Displays.setMode(monitor.modelData.name, Logic.bestModeId(monitor.modelData, item.value))
                }

                SelectRow {
                    visible: monitor.modelData.enabled
                    label: qsTr("Refresh rate")
                    menuItems: monitor.rateItems
                    active: monitor.rateItems.find(i => i.value === monitor.modelData.currentModeId) ?? null
                    fallbackText: qsTr("Unknown")
                    onSelected: item => Displays.setMode(monitor.modelData.name, item.value)
                }

                SelectRow {
                    visible: monitor.modelData.enabled
                    last: true
                    label: qsTr("Scale")
                    subtext: qsTr("Size of everything on this monitor")
                    menuItems: monitor.scaleItems
                    active: monitor.scaleItems.find(i => Logic.sameScale(i.value, monitor.modelData.scale)) ?? null
                    fallbackText: qsTr("Unknown")
                    onSelected: item => Displays.setScale(monitor.modelData.name, item.value)
                }
            }
        }
    }
}

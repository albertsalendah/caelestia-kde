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
        case "unknown-rotation":
            return qsTr("That orientation is not available.");
        case "brightness-failed":
            return qsTr("The brightness could not be changed.");
        case "invalid-position":
            return qsTr("That position is not valid.");
        case "invalid-mirror":
            return qsTr("That monitor cannot copy the primary monitor.");
        case "overlap":
            return qsTr("The monitors would overlap.");
        default:
            return qsTr("The display settings could not be applied.");
        }
    }

    // The monitors that extend the desktop, as the canvas draws them.
    readonly property var layoutRects: Logic.layoutRects(Displays.outputs)
    readonly property bool showCanvas: layoutRects.length > 1
    readonly property string primaryMonitor: Logic.primaryName(Displays.outputs)
    readonly property int enabledCount: Displays.outputs.filter(o => o.enabled).length

    function monitorTitle(name: string): string {
        if (Logic.isBuiltIn(name))
            return qsTr("Built-in Screen");
        const model = Logic.modelName(name, Displays.edids);
        return model !== "" ? model : name;
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

        // Plugging in or unplugging a monitor does not tell this page anything, so it looks again
        // every two seconds while it is shown. Not while a change is being applied.
        Timer {
            interval: 2000
            repeat: true
            running: root.visible && !Displays.busy
            onTriggered: Displays.refresh()
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

        SectionHeader {
            visible: root.showCanvas
            first: true
            text: qsTr("Arrangement")
        }

        DisplayCanvas {
            visible: root.showCanvas
            Layout.fillWidth: true
            Layout.preferredHeight: implicitHeight
            rects: root.layoutRects
            primary: root.primaryMonitor
            titles: {
                const t = {};
                Displays.outputs.forEach(o => t[o.name] = root.monitorTitle(o.name));
                return t;
            }
            onDropped: (name, x, y) => Displays.setPosition(name, x, y)
        }

        StyledText {
            visible: root.showCanvas
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.padding.small
            text: qsTr("Drag a monitor to arrange it. It snaps to the edge of another monitor.")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.small
            wrapMode: Text.WordWrap
        }

        Repeater {
            model: Displays.outputs

            ColumnLayout {
                id: monitor

                required property var modelData
                required property int index

                readonly property string resKey: Logic.currentResolutionKey(modelData)
                readonly property string monitorTitle: root.monitorTitle(modelData.name)
                readonly property bool isPrimary: root.primaryMonitor === modelData.name
                readonly property var resItems: root.makeItems(Logic.resolutionsOf(modelData).map(r => ({
                            text: r.label,
                            value: r.key
                        })))
                readonly property var rateItems: root.makeItems(Logic.refreshRatesFor(modelData, resKey).map(r => ({
                            text: r.label,
                            value: r.id
                        })))
                readonly property var rotationItems: root.makeItems([
                    {
                        text: qsTr("Normal"),
                        value: "none"
                    },
                    {
                        text: qsTr("Rotated left"),
                        value: "left"
                    },
                    {
                        text: qsTr("Upside down"),
                        value: "inverted"
                    },
                    {
                        text: qsTr("Rotated right"),
                        value: "right"
                    }
                ])
                readonly property bool hasBrightness: Displays.brightness[modelData.name] !== undefined
                readonly property int brightnessPercent: Displays.brightness[modelData.name] ?? 100
                readonly property var scaleItems: root.makeItems(Logic.scalePresets(modelData.scale).map(s => ({
                            text: s.label,
                            value: s.value
                        })))

                Layout.fillWidth: true
                spacing: Tokens.spacing.extraSmall / 2

                SectionHeader {
                    first: monitor.index === 0 && !root.showCanvas
                    text: monitor.monitorTitle
                }

                // The connection, under the name, so that a monitor can be told from its port.
                StyledText {
                    visible: monitor.monitorTitle !== monitor.modelData.name
                    Layout.fillWidth: true
                    Layout.leftMargin: Tokens.padding.small
                    Layout.bottomMargin: Tokens.spacing.extraSmall
                    text: monitor.modelData.name
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                    elide: Text.ElideRight
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

                ToggleRow {
                    visible: monitor.modelData.enabled && monitor.modelData.mirrorOf === "" && root.enabledCount > 1
                    text: qsTr("Primary monitor")
                    subtext: qsTr("The main display")
                    checked: monitor.isPrimary
                    enabled: !monitor.isPrimary
                    onToggled: {
                        Displays.setPrimary(monitor.modelData.name);
                        checked = Qt.binding(() => monitor.isPrimary);
                    }
                }

                ToggleRow {
                    visible: monitor.modelData.enabled && !monitor.isPrimary && root.enabledCount > 1
                    text: qsTr("Copy the primary monitor")
                    subtext: qsTr("Show the same picture instead of extending the desktop")
                    checked: monitor.modelData.mirrorOf !== ""
                    onToggled: {
                        Displays.setCopy(monitor.modelData.name, checked);
                        checked = Qt.binding(() => monitor.modelData.mirrorOf !== "");
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
                    label: qsTr("Scale")
                    subtext: qsTr("Size of everything on this monitor")
                    menuItems: monitor.scaleItems
                    active: monitor.scaleItems.find(i => Logic.sameScale(i.value, monitor.modelData.scale)) ?? null
                    fallbackText: qsTr("Unknown")
                    onSelected: item => Displays.setScale(monitor.modelData.name, item.value)
                }

                SelectRow {
                    visible: monitor.modelData.enabled
                    last: !monitor.hasBrightness
                    label: qsTr("Orientation")
                    menuItems: monitor.rotationItems
                    active: monitor.rotationItems.find(i => i.value === monitor.modelData.rotation) ?? null
                    fallbackText: qsTr("Unknown")
                    onSelected: item => Displays.setRotation(monitor.modelData.name, item.value)
                }

                // Applies as the slider moves, with nothing to keep; the number is the one that is set.
                SliderRow {
                    visible: monitor.modelData.enabled && monitor.hasBrightness
                    last: true
                    icon: "brightness_6"
                    label: qsTr("Brightness")
                    valueLabel: monitor.brightnessPercent + "%"
                    value: monitor.brightnessPercent / 100
                    onMoved: value => Displays.setBrightness(monitor.modelData.name, value)
                }
            }
        }
    }
}

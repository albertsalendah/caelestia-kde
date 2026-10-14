pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common
import "../../../utils/scripts/power.js" as Logic

PageBase {
    id: root

    title: qsTr("Power")

    // The on-battery settings only matter when there is a battery.
    readonly property var sections: UPower.displayDevice.isLaptopBattery ? [
        {
            id: "AC",
            title: qsTr("Plugged in")
        },
        {
            id: "Battery",
            title: qsTr("On battery")
        }
    ] : [
        {
            id: "AC",
            title: qsTr("Plugged in")
        }
    ]

    function errorText(code: string): string {
        switch (code) {
        case "reload-failed":
            return qsTr("The setting was saved, but the power service did not reload it.");
        default:
            return qsTr("The power settings could not be saved.");
        }
    }

    function delayText(choice: var): string {
        return choice.value === 0 ? qsTr("Never") : choice.label;
    }

    function profileText(choice: var): string {
        switch (choice.value) {
        case "":
            return qsTr("Don't change");
        case "power-saver":
            return qsTr("Power saver");
        case "balanced":
            return qsTr("Balanced");
        case "performance":
            return qsTr("Performance");
        default:
            return choice.label;
        }
    }

    // Menu entries made at run time, because the delays offered depend on what is set now.
    function makeItems(entries: var): var {
        return entries.map(e => itemComp.createObject(root, {
                text: e.text,
                value: e.value
            }));
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        Component {
            id: itemComp

            MenuItem {}
        }

        StyledText {
            visible: PowerSettings.error !== ""
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.padding.small
            Layout.bottomMargin: Tokens.spacing.extraSmall
            text: root.errorText(PowerSettings.error)
            color: Colours.palette.m3error
            font: Tokens.font.body.small
            wrapMode: Text.WordWrap
        }

        Repeater {
            model: root.sections

            ColumnLayout {
                id: section

                required property var modelData
                required property int index

                readonly property var current: PowerSettings.settings(modelData.id)
                readonly property int dimNow: Logic.currentDelay("dim", current)
                readonly property int offNow: Logic.currentDelay("off", current)
                readonly property int suspendNow: Logic.currentDelay("suspend", current)
                readonly property var profileItems: root.makeItems(Logic.profileChoices(PowerProfiles.hasPerformanceProfile, current.powerProfile).map(c => ({
                            text: root.profileText(c),
                            value: c.value
                        })))
                readonly property var dimItems: root.makeItems(Logic.delayChoices(dimNow).map(c => ({
                            text: root.delayText(c),
                            value: c.value
                        })))
                readonly property var offItems: root.makeItems(Logic.delayChoices(offNow).map(c => ({
                            text: root.delayText(c),
                            value: c.value
                        })))
                readonly property var suspendItems: root.makeItems(Logic.delayChoices(suspendNow).map(c => ({
                            text: root.delayText(c),
                            value: c.value
                        })))

                Layout.fillWidth: true
                spacing: Tokens.spacing.extraSmall / 2

                SectionHeader {
                    first: section.index === 0
                    text: section.modelData.title
                }

                SelectRow {
                    first: true
                    label: qsTr("Power profile")
                    subtext: qsTr("Used while on this power source")
                    menuItems: section.profileItems
                    active: section.profileItems.find(i => i.value === section.current.powerProfile) ?? null
                    fallbackText: qsTr("Don't change")
                    onSelected: item => PowerSettings.setPowerProfile(section.modelData.id, item.value)
                }

                SelectRow {
                    label: qsTr("Dim screen after")
                    menuItems: section.dimItems
                    active: section.dimItems.find(i => i.value === section.dimNow) ?? null
                    fallbackText: qsTr("Never")
                    onSelected: item => PowerSettings.setDelay(section.modelData.id, "dim", item.value)
                }

                SelectRow {
                    label: qsTr("Turn off screen after")
                    menuItems: section.offItems
                    active: section.offItems.find(i => i.value === section.offNow) ?? null
                    fallbackText: qsTr("Never")
                    onSelected: item => PowerSettings.setDelay(section.modelData.id, "off", item.value)
                }

                SelectRow {
                    last: true
                    label: qsTr("Suspend after")
                    menuItems: section.suspendItems
                    active: section.suspendItems.find(i => i.value === section.suspendNow) ?? null
                    fallbackText: qsTr("Never")
                    onSelected: item => PowerSettings.setDelay(section.modelData.id, "suspend", item.value)
                }
            }
        }
    }
}

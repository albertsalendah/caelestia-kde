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

    // The on-battery and low-battery settings only matter when there is a battery. powerdevil
    // uses the low-battery profile once the charge is at or below its low-battery level.
    readonly property var sections: {
        const list = [
            {
                id: "AC",
                title: qsTr("Plugged in")
            }
        ];
        if (UPower.displayDevice.isLaptopBattery)
            list.push({
                id: "Battery",
                title: qsTr("On battery")
            }, {
                id: "LowBattery",
                title: qsTr("Low battery"),
                hint: qsTr("Used when the charge is at or below the low-battery level (10% by default)")
            });
        return list;
    }

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

    function actionText(choice: var): string {
        switch (choice.value) {
        case 0:
            return qsTr("Do nothing");
        case 1:
            return qsTr("Sleep");
        case 2:
            return qsTr("Hibernate");
        case 8:
            return qsTr("Shut down");
        case 16:
            return qsTr("Show logout dialog");
        case 32:
            return qsTr("Lock screen");
        case 64:
            return qsTr("Turn off screen");
        case 128:
            return qsTr("Toggle screen on and off");
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
                readonly property var lidItems: root.makeItems(Logic.lidChoices(current.lid).map(c => ({
                            text: root.actionText(c),
                            value: c.value
                        })))
                readonly property var buttonItems: root.makeItems(Logic.powerButtonChoices(current.powerButton).map(c => ({
                            text: root.actionText(c),
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
                    subtext: section.modelData.hint ?? qsTr("Used while on this power source")
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
                    label: qsTr("Suspend after")
                    menuItems: section.suspendItems
                    active: section.suspendItems.find(i => i.value === section.suspendNow) ?? null
                    fallbackText: qsTr("Never")
                    onSelected: item => PowerSettings.setDelay(section.modelData.id, "suspend", item.value)
                }

                SelectRow {
                    visible: UPower.displayDevice.isLaptopBattery
                    label: qsTr("When the lid is closed")
                    subtext: qsTr("Ignored while an external monitor is connected")
                    menuItems: section.lidItems
                    active: section.lidItems.find(i => i.value === section.current.lid) ?? null
                    fallbackText: qsTr("Sleep")
                    onSelected: item => PowerSettings.setLidAction(section.modelData.id, item.value)
                }

                SelectRow {
                    last: true
                    label: qsTr("When the power button is pressed")
                    menuItems: section.buttonItems
                    active: section.buttonItems.find(i => i.value === section.current.powerButton) ?? null
                    fallbackText: qsTr("Show logout dialog")
                    onSelected: item => PowerSettings.setPowerButtonAction(section.modelData.id, item.value)
                }
            }
        }
    }
}

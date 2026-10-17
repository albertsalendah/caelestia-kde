pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common
import "../../../utils/scripts/splash.js" as Logic

PageBase {
    id: root

    title: qsTr("Splash")

    // The theme picked in the list but not applied yet. Applying rebuilds the boot image, so
    // choosing alone changes nothing on the machine.
    property string pendingTheme: ""
    readonly property string chosenTheme: root.pendingTheme !== "" ? root.pendingTheme : SplashSettings.currentTheme
    // The Caelestia design needs its own QML; a Plasma theme needs ksplashqml.
    readonly property bool loginPreviewReady: SplashSettings.settings.plasmaTheme === "" ? SplashSettings.splashInstalled : SplashSettings.ksplashAvailable
    readonly property bool busy: SplashSettings.bootState === "applying"

    function errorText(code: string): string {
        return qsTr("The splash settings could not be saved.");
    }

    function bootStateText(state: string): string {
        switch (state) {
        case "applying":
            return qsTr("Rebuilding the boot image. This can take a minute or more: do not switch the machine off.");
        case "done":
            return qsTr("Done. The new boot splash shows from the next start.");
        case "cancelled":
            return qsTr("Cancelled. Nothing was changed.");
        case "failed":
            return qsTr("The theme could not be applied. Run \"sudo plymouth-set-default-theme -R <theme>\" in a terminal to see why.");
        default:
            return "";
        }
    }

    function makeItems(entries: var): var {
        return entries.map(e => itemComp.createObject(root, {
                text: e.text,
                value: e.value
            }));
    }

    readonly property var minItems: root.makeItems(Logic.minChoices(SplashSettings.settings.minSeconds).map(c => ({
                text: c.label,
                value: c.value
            })))
    readonly property var loginItems: root.makeItems(Logic.loginChoices(SplashSettings.plasmaThemes).map(c => ({
                text: c.label,
                value: c.value
            })))
    readonly property var themeItems: root.makeItems(SplashSettings.themes.map(t => ({
                text: t,
                value: t
            })))

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
            visible: SplashSettings.error !== ""
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.padding.small
            Layout.bottomMargin: Tokens.spacing.extraSmall
            text: root.errorText(SplashSettings.error)
            color: Colours.palette.m3error
            font: Tokens.font.body.small
            wrapMode: Text.WordWrap
        }

        SectionHeader {
            first: true
            text: qsTr("Login splash")
        }

        ToggleRow {
            first: true
            text: qsTr("Show a splash while logging in")
            subtext: qsTr("Covers the screen until the shell has loaded. Needs the session program from this version: run scripts/setup.sh once.")
            checked: SplashSettings.settings.enabled
            onToggled: SplashSettings.setEnabled(checked)
        }

        SelectRow {
            label: qsTr("Style")
            subtext: SplashSettings.ksplashAvailable ? qsTr("Caelestia, or one of the Plasma splash screens") : qsTr("Plasma splash screens need ksplashqml, which comes with plasma-workspace")
            menuItems: root.loginItems
            active: root.loginItems.find(i => i.value === SplashSettings.settings.plasmaTheme) ?? null
            fallbackText: qsTr("Caelestia")
            onSelected: item => SplashSettings.setPlasmaTheme(item.value)
        }

        ToggleRow {
            visible: SplashSettings.settings.plasmaTheme === ""
            text: qsTr("Show the logo")
            checked: SplashSettings.settings.showLogo
            onToggled: SplashSettings.setShowLogo(checked)
        }

        SelectRow {
            label: qsTr("Show for at least")
            menuItems: root.minItems
            active: root.minItems.find(i => i.value === SplashSettings.settings.minSeconds) ?? null
            fallbackText: qsTr("2 s")
            onSelected: item => SplashSettings.setMinSeconds(item.value)
        }

        RowButton {
            last: true
            icon: "play_arrow"
            text: qsTr("Preview the splash")
            subtext: root.loginPreviewReady ? qsTr("Shows it now for a few seconds") : qsTr("Not available: run Install Updates, or install plasma-workspace for a Plasma splash")
            disabled: !root.loginPreviewReady
            onClicked: SplashSettings.preview()
        }

        SectionHeader {
            text: qsTr("Boot splash")
        }

        InfoRow {
            first: true
            last: !SplashSettings.plymouthAvailable
            label: qsTr("Current theme")
            subtext: SplashSettings.plymouthAvailable ? "" : qsTr("Plymouth is not installed, so there is no boot splash to set up.")
            value: SplashSettings.plymouthAvailable ? SplashSettings.currentTheme : ""
        }

        SelectRow {
            visible: SplashSettings.plymouthAvailable
            label: qsTr("Theme")
            menuItems: root.themeItems
            active: root.themeItems.find(i => i.value === root.chosenTheme) ?? null
            fallbackText: SplashSettings.currentTheme
            onSelected: item => root.pendingTheme = item.value
        }

        RowButton {
            visible: SplashSettings.plymouthAvailable
            icon: "play_arrow"
            text: qsTr("Preview this theme")
            subtext: qsTr("Close to the real boot, not the same: a theme made of a program is shown as the Caelestia design")
            disabled: !SplashSettings.splashInstalled || root.chosenTheme === ""
            onClicked: SplashSettings.previewTheme(root.chosenTheme)
        }

        RowButton {
            visible: SplashSettings.plymouthAvailable
            last: true
            icon: "restart_alt"
            text: qsTr("Apply the theme and rebuild the boot image")
            subtext: qsTr("Asks for your password. Take a Snapper snapshot first.")
            disabled: root.busy || root.chosenTheme === SplashSettings.currentTheme
            onClicked: SplashSettings.applyTheme(root.chosenTheme)
        }

        StyledText {
            visible: SplashSettings.bootState !== "idle"
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.padding.small
            Layout.topMargin: Tokens.spacing.extraSmall
            text: root.bootStateText(SplashSettings.bootState)
            color: SplashSettings.bootState === "failed" ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.small
            wrapMode: Text.WordWrap
        }
    }
}

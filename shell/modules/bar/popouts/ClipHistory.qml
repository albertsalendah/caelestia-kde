pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.launcher.services

// Clipboard popout: the most recent clips from the history the launcher also
// shows. A click copies a clip, the header button clears the history.
ColumnLayout {
    id: root

    required property PopoutState popouts

    property real scaleOffset: 1.0
    property real fontScale: 1.0

    // Set while the "clear everything?" question is up, when the launcher's
    // confirm setting is on.
    property bool confirming: false

    readonly property int maxClips: Math.max(1, Config.bar.status.clipboardEntries)
    readonly property var recent: Clipboard.getSortedItems().slice(0, root.maxClips)

    function copyClip(clip: var): void {
        root.popouts.hasCurrent = false;

        if (clip.isPinned)
            Clipboard.copyPinned(clip.pinId);
        else
            Quickshell.execDetached(["sh", "-c", "cliphist decode " + clip.id + " | wl-copy"]);

        if (GlobalConfig.utilities.toasts.clipboardChanged) {
            const preview = clip.preview.length > 30 ? clip.preview.slice(0, 30) + "..." : clip.preview;
            Toaster.toast(qsTr("Copied to clipboard"), preview, "content_paste");
        }
    }

    function requestClear(): void {
        if (GlobalConfig.launcher.confirmClearClipboard)
            root.confirming = true;
        else
            root.clearNow();
    }

    function clearNow(): void {
        root.confirming = false;
        Clipboard.clearHistory();
    }

    // The history is read again each time the popout opens, so a clip copied a
    // moment ago is already in it.
    Component.onCompleted: Clipboard.reload()

    width: 320 * scaleOffset
    implicitWidth: 320 * scaleOffset
    spacing: Tokens.spacing.medium * scaleOffset

    // The launcher reports the result of a clear while it is loaded; this only
    // covers a bar that runs with the launcher turned off.
    Connections {
        function onClearHistoryFinished(success: bool): void {
            if (success) {
                if (GlobalConfig.utilities.toasts.clipboardChanged)
                    Toaster.toast(qsTr("Clipboard history cleared"), "", "delete");
            } else {
                Toaster.toast(qsTr("Failed to clear clipboard history"), "", "error");
            }
        }

        enabled: !Config.launcher.enabled
        target: Clipboard
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: Tokens.padding.medium * root.scaleOffset
        Layout.leftMargin: Tokens.padding.small * root.scaleOffset
        spacing: Tokens.spacing.small * root.scaleOffset

        StyledText {
            Layout.fillWidth: true
            text: qsTr("Clipboard")
            font.weight: 500
            font.pointSize: Tokens.font.title.small.pointSize * root.fontScale
        }

        IconButton {
            visible: root.recent.length > 0 && !root.confirming
            icon: "delete_sweep"
            font: Tokens.font.icon.medium
            type: IconButton.Tonal
            isRound: true
            inactiveColour: Colours.tPalette.m3surfaceContainerHigh
            inactiveOnColour: Colours.palette.m3onSurfaceVariant
            onClicked: root.requestClear()
        }
    }

    StyledRect {
        Layout.fillWidth: true
        implicitWidth: cardLayout.implicitWidth + Tokens.padding.medium * 2 * root.scaleOffset
        implicitHeight: cardLayout.implicitHeight + Tokens.padding.medium * 2 * root.scaleOffset
        radius: Tokens.rounding.medium * root.scaleOffset
        color: Colours.tPalette.m3surfaceContainer
        clip: true

        ColumnLayout {
            id: cardLayout

            width: parent.width - Tokens.padding.medium * 2 * root.scaleOffset
            x: Tokens.padding.medium * root.scaleOffset
            y: Tokens.padding.medium * root.scaleOffset
            spacing: Tokens.spacing.small * root.scaleOffset

            RowLayout {
                Layout.fillWidth: true
                visible: root.confirming
                spacing: Tokens.spacing.small * root.scaleOffset

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Clear all clipboard history?")
                    font.pointSize: Tokens.font.body.medium.pointSize * root.fontScale
                }

                TextButton {
                    text: qsTr("Cancel")
                    type: TextButton.Text
                    onClicked: root.confirming = false
                }

                TextButton {
                    text: qsTr("Clear")
                    type: TextButton.Tonal
                    onClicked: root.clearNow()
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.recent.length === 0
                text: Clipboard.available ? qsTr("Nothing copied yet") : qsTr("Clipboard history needs cliphist")
                color: Colours.palette.m3onSurfaceVariant
                font.pointSize: Tokens.font.body.small.pointSize * root.fontScale
            }

            Repeater {
                model: ScriptModel {
                    values: root.recent
                }

                delegate: StyledRect {
                    id: clipRow

                    required property var modelData

                    Layout.fillWidth: true
                    implicitHeight: rowLayout.implicitHeight + Tokens.padding.small * 2 * root.scaleOffset
                    radius: Tokens.rounding.small * root.scaleOffset
                    color: "transparent"

                    StateLayer {
                        radius: clipRow.radius
                        onClicked: root.copyClip(clipRow.modelData)
                    }

                    RowLayout {
                        id: rowLayout

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: Tokens.padding.small * root.scaleOffset
                        anchors.rightMargin: Tokens.padding.small * root.scaleOffset
                        spacing: Tokens.spacing.small * root.scaleOffset

                        MaterialIcon {
                            text: clipRow.modelData.isPinned ? "keep" : clipRow.modelData.isImage ? "image" : "content_paste"
                            color: Colours.palette.m3onSurfaceVariant
                            fontStyle.pointSize: Tokens.font.icon.medium.pointSize * root.fontScale
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: clipRow.modelData.preview
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            font.pointSize: Tokens.font.body.medium.pointSize * root.fontScale
                        }
                    }
                }
            }
        }
    }
}

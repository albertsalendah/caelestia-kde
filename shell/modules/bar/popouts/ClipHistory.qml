pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.images
import qs.services
import qs.modules.launcher.services
import "../../../utils/scripts/clipfiles.js" as ClipFiles

// Clipboard popout: the clipboard history the launcher also shows, newest
// first, in a list that scrolls. A click copies a clip, the header button
// clears the history. Text is one line, images show a thumbnail and copied
// files show a thumbnail or icon and the name of each file, in a strip that
// scrolls sideways when it does not fit.
ColumnLayout {
    id: root

    required property PopoutState popouts

    property real scaleOffset: 1.0
    property real fontScale: 1.0

    // Set while the "clear everything?" question is up, when the launcher's
    // confirm setting is on.
    property bool confirming: false

    readonly property int visibleRows: Math.max(1, Config.bar.status.clipboardEntries)
    readonly property var clips: Clipboard.getSortedItems()
    readonly property real rowHeight: 40 * scaleOffset
    readonly property real imageRowHeight: 76 * scaleOffset
    readonly property real fileRowHeight: 56 * scaleOffset
    // A clip of hundreds of files shows this many chips.
    readonly property int maxChips: 50
    readonly property real rowSpacing: Tokens.spacing.small * scaleOffset
    // The list grows to this many text rows and scrolls after that.
    readonly property real maxListHeight: visibleRows * rowHeight + (visibleRows - 1) * rowSpacing

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
            visible: root.clips.length > 0 && !root.confirming
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

            // The question has a line of its own so it never runs into the buttons.
            ColumnLayout {
                Layout.fillWidth: true
                visible: root.confirming
                spacing: Tokens.spacing.small * root.scaleOffset

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Clear all clipboard history?")
                    wrapMode: Text.WordWrap
                    font.pointSize: Tokens.font.body.medium.pointSize * root.fontScale
                }

                RowLayout {
                    Layout.alignment: Qt.AlignRight
                    spacing: Tokens.spacing.small * root.scaleOffset

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
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.clips.length === 0
                text: Clipboard.available ? qsTr("Nothing copied yet") : qsTr("Clipboard history needs cliphist")
                color: Colours.palette.m3onSurfaceVariant
                font.pointSize: Tokens.font.body.small.pointSize * root.fontScale
            }

            ListView {
                id: clipList

                Layout.fillWidth: true
                visible: root.clips.length > 0
                implicitHeight: Math.min(contentHeight, root.maxListHeight)
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                spacing: root.rowSpacing
                model: ScriptModel {
                    values: root.clips
                }

                StyledScrollBar.vertical: StyledScrollBar {
                    flickable: clipList
                }

                delegate: StyledRect {
                    id: clipRow

                    required property var modelData

                    readonly property bool isImage: modelData.isImage ?? false
                    readonly property bool isPinned: modelData.isPinned ?? false
                    // cliphist cuts its preview, so a file clip is read in full when it
                    // can be (a pinned clip has no cliphist entry to read).
                    property string fullText: ""
                    readonly property string clipText: fullText.length > 0 ? fullText : (modelData.preview ?? "")
                    readonly property bool isFiles: !isImage && ClipFiles.isFileClip(modelData.preview ?? "")
                    readonly property var fileEntries: isFiles ? ClipFiles.fileEntries(clipText) : []
                    property string imagePath: ""

                    function updateImage(): void {
                        if (!clipRow.isImage)
                            clipRow.imagePath = "";
                        else if (clipRow.isPinned)
                            clipRow.imagePath = clipRow.modelData.imagePath ?? "";
                        else if (Clipboard.isImageCached(clipRow.modelData.id))
                            clipRow.imagePath = Clipboard.getImagePath(clipRow.modelData.id);
                        else
                            clipRow.imagePath = "";
                    }

                    function refresh(): void {
                        clipRow.fullText = "";
                        clipRow.updateImage();
                        if (clipRow.isFiles && !clipRow.isPinned)
                            decodeProc.running = true;
                    }

                    width: clipList.width
                    height: isImage ? root.imageRowHeight : isFiles ? root.fileRowHeight : root.rowHeight
                    radius: Tokens.rounding.small * root.scaleOffset
                    color: "transparent"

                    onModelDataChanged: refresh()
                    Component.onCompleted: refresh()

                    Connections {
                        function onImageReady(id: int, path: string): void {
                            if (clipRow.isImage && id === clipRow.modelData.id)
                                clipRow.imagePath = path;
                        }

                        target: Clipboard
                    }

                    Process {
                        id: decodeProc

                        command: ["cliphist", "decode", String(clipRow.modelData.id)]
                        stdout: StdioCollector {
                            onStreamFinished: clipRow.fullText = text
                        }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Tokens.padding.small * root.scaleOffset
                        anchors.rightMargin: Tokens.padding.small * root.scaleOffset
                        spacing: Tokens.spacing.small * root.scaleOffset

                        MaterialIcon {
                            visible: !clipRow.isImage
                            text: clipRow.isPinned ? "keep" : clipRow.isFiles ? (clipRow.fileEntries.length > 1 ? "file_copy" : ClipFiles.iconFor(clipRow.fileEntries[0]?.kind)) : "content_paste"
                            color: Colours.palette.m3onSurfaceVariant
                            fontStyle.pointSize: Tokens.font.icon.medium.pointSize * root.fontScale
                        }

                        // Image: a thumbnail, as the launcher shows.
                        StyledRect {
                            visible: clipRow.isImage
                            Layout.preferredWidth: 96 * root.scaleOffset
                            Layout.preferredHeight: root.imageRowHeight - Tokens.padding.small * 2 * root.scaleOffset
                            radius: Tokens.rounding.small * root.scaleOffset
                            color: Colours.tPalette.m3surfaceContainerHigh
                            clip: true

                            CachingImage {
                                anchors.fill: parent
                                path: clipRow.imagePath
                            }
                        }

                        // Files: one chip per file, in a strip that moves sideways.
                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            visible: clipRow.isFiles
                            clip: true

                            Flickable {
                                id: filesFlick

                                anchors.fill: parent
                                interactive: false
                                boundsBehavior: Flickable.StopAtBounds
                                contentWidth: chipRow.implicitWidth
                                contentHeight: height

                                Row {
                                    id: chipRow

                                    height: filesFlick.height
                                    spacing: Tokens.spacing.small * root.scaleOffset

                                    Repeater {
                                        model: clipRow.fileEntries.slice(0, root.maxChips)

                                        delegate: StyledRect {
                                            id: chip

                                            required property var modelData

                                            anchors.verticalCenter: parent.verticalCenter
                                            implicitWidth: chipLayout.implicitWidth + Tokens.padding.small * 2 * root.scaleOffset
                                            implicitHeight: 44 * root.scaleOffset
                                            radius: Tokens.rounding.small * root.scaleOffset
                                            color: Colours.tPalette.m3surfaceContainerHigh

                                            RowLayout {
                                                id: chipLayout

                                                anchors.centerIn: parent
                                                spacing: Tokens.spacing.small * root.scaleOffset

                                                FileThumb {
                                                    entry: chip.modelData
                                                    side: 32 * root.scaleOffset
                                                }

                                                StyledText {
                                                    Layout.preferredWidth: Math.min(implicitWidth, 130 * root.scaleOffset)
                                                    text: chip.modelData.name
                                                    elide: Text.ElideRight
                                                    font.pointSize: Tokens.font.body.small.pointSize * root.fontScale
                                                }
                                            }
                                        }
                                    }

                                    StyledText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: clipRow.fileEntries.length > root.maxChips
                                        text: qsTr("+%1 more").arg(clipRow.fileEntries.length - root.maxChips)
                                        color: Colours.palette.m3onSurfaceVariant
                                        font.pointSize: Tokens.font.body.small.pointSize * root.fontScale
                                    }
                                }
                            }
                        }

                        // Text, and the label next to an image: one line with an ellipsis.
                        StyledText {
                            Layout.fillWidth: true
                            visible: !clipRow.isFiles
                            text: clipRow.modelData.preview
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            color: clipRow.isImage ? Colours.palette.m3onSurfaceVariant : Colours.palette.m3onSurface
                            font.pointSize: (clipRow.isImage ? Tokens.font.body.small : Tokens.font.body.medium).pointSize * root.fontScale
                        }
                    }

                    // On top of the content, so a click anywhere on the row copies it
                    // and the file strip never takes the click.
                    StateLayer {
                        z: 1
                        radius: clipRow.radius
                        onClicked: root.copyClip(clipRow.modelData)
                        onWheel: wheel => {
                            // Sideways scrolling (a touchpad, or Shift with the wheel) moves
                            // the file strip when it overflows; anything else is left to
                            // the list.
                            const dx = wheel.angleDelta.x !== 0 ? wheel.angleDelta.x : (wheel.modifiers & Qt.ShiftModifier ? wheel.angleDelta.y : 0);
                            const room = filesFlick.contentWidth - filesFlick.width;
                            if (!clipRow.isFiles || dx === 0 || room <= 0) {
                                wheel.accepted = false;
                                return;
                            }
                            filesFlick.contentX = Math.max(0, Math.min(room, filesFlick.contentX - dx));
                        }
                    }
                }
            }
        }
    }

    // One copied file: the picture itself for an image, the file manager's
    // cached preview for a video (freedesktop thumbnail cache, named by the md5
    // of the file's URL), and an icon for the kind of file when there is none.
    component FileThumb: Item {
        id: thumb

        required property var entry
        required property real side
        property int attempt: 0

        readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/thumbnails"
        readonly property string cacheName: Qt.md5(entry.url) + ".png"
        readonly property string source: {
            if (entry.kind === "image")
                return entry.url;
            if (entry.kind !== "video")
                return "";
            if (attempt === 0)
                return "file://" + cacheDir + "/large/" + cacheName;
            if (attempt === 1)
                return "file://" + cacheDir + "/normal/" + cacheName;
            return "";
        }

        implicitWidth: side
        implicitHeight: side

        StyledRect {
            anchors.fill: parent
            radius: Tokens.rounding.small * root.scaleOffset
            color: Colours.tPalette.m3surfaceContainer
            clip: true

            Image {
                id: thumbImage

                anchors.fill: parent
                source: thumb.source
                asynchronous: true
                fillMode: Image.PreserveAspectCrop
                sourceSize: Qt.size(thumb.side * 2, thumb.side * 2)
                visible: status === Image.Ready
                onStatusChanged: {
                    // A video with no cached preview there falls through to the next
                    // size and then to the icon.
                    if (status === Image.Error && thumb.entry.kind === "video")
                        thumb.attempt++;
                }
            }

            MaterialIcon {
                anchors.centerIn: parent
                visible: thumbImage.status !== Image.Ready
                text: ClipFiles.iconFor(thumb.entry.kind)
                color: Colours.palette.m3onSurfaceVariant
                fontStyle.pointSize: Tokens.font.icon.medium.pointSize * root.fontScale
            }
        }
    }
}

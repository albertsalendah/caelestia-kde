pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.services

ColumnLayout {
    id: root

    // What `caelestia scheme palettes` printed: the cards, and the position of the one in effect
    // (-1 when none of them is, for a variant that has no card).
    property var palettes: []
    property int selected: -1
    property bool loading: false
    // Asked again while a run was going: run once more when it ends.
    property bool stale: false

    function refresh(): void {
        if (paletteProc.running) {
            root.stale = true;
            return;
        }
        root.loading = true;
        paletteProc.running = true;
    }

    function parse(json: string): void {
        try {
            const data = JSON.parse(json);
            root.palettes = data.palettes ?? [];
            root.selected = data.selected ?? -1;
        } catch (e) {
            root.palettes = [];
            root.selected = -1;
        }
    }

    // A card is a color of the wallpaper and a variant. Choosing one makes the scheme dynamic,
    // which is what the cards are for whatever scheme is in effect now.
    function apply(entry: var): void {
        Quickshell.execDetached(["caelestia", "scheme", "set", "-n", "dynamic", "-s", String(entry.source), "-v", entry.variant, ...Colours.smartArg]);
    }

    Layout.fillWidth: true
    spacing: Tokens.spacing.medium

    Component.onCompleted: root.refresh()

    StyledText {
        text: qsTr("Wallpaper palettes")
        font: Tokens.font.title.medium
    }

    StyledText {
        Layout.fillWidth: true
        text: root.palettes.length > 0 ? qsTr("Colors found in your wallpaper, then variants of the first. The first one is the default.") : root.loading ? qsTr("Reading the wallpaper...") : qsTr("No colors could be read from the wallpaper.")
        font: Tokens.font.body.medium
        color: Colours.palette.m3onSurfaceVariant
        wrapMode: Text.Wrap
    }

    GridLayout {
        Layout.fillWidth: true
        visible: root.palettes.length > 0
        columns: 3
        rowSpacing: Tokens.spacing.medium
        columnSpacing: Tokens.spacing.medium

        Repeater {
            model: root.palettes

            PaletteCard {}
        }
    }

    Process {
        id: paletteProc

        command: ["caelestia", "scheme", "palettes"]
        stdout: StdioCollector {
            onStreamFinished: root.parse(text)
        }
        onExited: {
            root.loading = false;
            if (root.stale) {
                root.stale = false;
                root.refresh();
            }
        }
    }

    // The row follows the scheme in effect, and a wallpaper that changes under a scheme that is not
    // dynamic has no scheme change to follow.
    Connections {
        function onSchemeApplied(): void {
            root.refresh();
        }

        target: Colours
    }

    Connections {
        function onActualCurrentChanged(): void {
            root.refresh();
        }

        target: Wallpapers
    }

    component PaletteCard: StyledRect {
        id: card

        required property var modelData
        required property int index

        readonly property bool isSelected: Colours.scheme === "dynamic" && card.index === root.selected
        readonly property var colours: card.modelData?.colours ?? ({})

        Layout.fillWidth: true
        Layout.preferredWidth: 1
        implicitHeight: dial.height + Tokens.padding.large * 2
        radius: Tokens.rounding.large
        color: isSelected ? Colours.palette.m3secondaryContainer : Colours.tPalette.m3surfaceContainer
        border.width: isSelected ? 2 : 1
        border.color: isSelected ? Colours.palette.m3secondary : Colours.palette.m3surfaceVariant

        StateLayer {
            radius: parent.radius
            onClicked: root.apply(card.modelData)
        }

        // One circle in four quarters: the accent colors and the surface, like the palette
        // circles of a phone's wallpaper settings. A quarter is a clipped view of the whole circle.
        Item {
            id: dial

            anchors.centerIn: parent
            width: Tokens.sizes.launcher.itemHeight * 1.6
            height: width

            Repeater {
                model: [
                    { role: "primary", column: 0, row: 0 },
                    { role: "secondary", column: 1, row: 0 },
                    { role: "tertiary", column: 0, row: 1 },
                    { role: "surface", column: 1, row: 1 }
                ]

                Item {
                    id: quarter

                    required property var modelData

                    x: modelData.column * dial.width / 2
                    y: modelData.row * dial.height / 2
                    width: dial.width / 2
                    height: dial.height / 2
                    clip: true

                    StyledRect {
                        x: -quarter.x
                        y: -quarter.y
                        width: dial.width
                        height: dial.height
                        radius: Tokens.rounding.full
                        color: `#${card.colours[quarter.modelData.role] ?? "000000"}`
                    }
                }
            }

            StyledRect {
                anchors.fill: parent
                color: "transparent"
                radius: Tokens.rounding.full
                border.width: 1
                border.color: Qt.alpha(Colours.palette.m3outline, 0.5)
            }

            StyledRect {
                anchors.centerIn: parent
                visible: card.isSelected
                width: Tokens.sizes.launcher.itemHeight * 0.6
                height: width
                radius: Tokens.rounding.full
                color: Colours.palette.m3secondaryContainer

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "check"
                    color: Colours.palette.m3onSecondaryContainer
                    fontStyle: Tokens.font.icon.large
                }
            }
        }
    }
}

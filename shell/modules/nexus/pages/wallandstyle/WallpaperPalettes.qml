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

    // What `caelestia scheme palettes` printed: the cards, the position of the one in effect (-1
    // when none of them is, for a variant that has no card), and the Custom card's palette.
    property var palettes: []
    property int selected: -1
    property var custom: ({ active: false, hex: "", colours: ({}) })
    property bool loading: false
    // Asked again while a run was going: run once more when it ends.
    property bool stale: false

    readonly property real dialSize: Tokens.sizes.launcher.itemHeight * 1.6

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
            root.custom = data.custom ?? ({ active: false, hex: "", colours: ({}) });
        } catch (e) {
            root.palettes = [];
            root.selected = -1;
            root.custom = ({ active: false, hex: "", colours: ({}) });
        }
    }

    // A card is a color of the wallpaper and a variant. Choosing one makes the scheme dynamic,
    // which is what the cards are for whatever scheme is in effect now.
    function apply(entry: var): void {
        Quickshell.execDetached(["caelestia", "scheme", "set", "-n", "dynamic", "-s", String(entry.source), "-v", entry.variant, ...Colours.smartArg]);
    }

    // The Custom card builds the palette from a color picked on the screen. The variant is stated:
    // the wallpaper's own choice can be a grey one, which would take the color out of it.
    function applyCustom(hex: string): void {
        Quickshell.execDetached(["caelestia", "scheme", "set", "-n", "dynamic", "--seed", hex, "-v", "tonalspot", ...Colours.smartArg]);
    }

    function pickCustom(): void {
        if (!eyedropper.running)
            eyedropper.running = true;
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
        text: root.palettes.length > 0 ? qsTr("Colors found in your wallpaper, then variants of the first. The last card builds a palette from any color you pick on the screen.") : root.loading ? qsTr("Reading the wallpaper...") : qsTr("No colors could be read from the wallpaper.")
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

        CustomCard {}
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

    // KWin's own eyedropper, the one the Quick Toggles use: it answers with the color as a number,
    // and with 0 when it was cancelled.
    Process {
        id: eyedropper

        command: ["dbus-send", "--session", "--print-reply", "--dest=org.kde.KWin", "/ColorPicker", "org.kde.kwin.ColorPicker.pick"]
        stdout: StdioCollector {
            onStreamFinished: {
                const match = text.match(/uint32\s+(\d+)/);
                const value = match ? parseInt(match[1]) & 0xFFFFFF : 0;
                if (value !== 0)
                    root.applyCustom(`#${value.toString(16).padStart(6, "0")}`);
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

    // One circle in four quarters: three accents and the tinted container of the first, like the
    // palette circles of a phone's wallpaper settings. A quarter is a clipped view of the whole circle.
    component Dial: Item {
        id: dial

        required property var colours
        property bool checked: false

        width: root.dialSize
        height: width

        Repeater {
            model: [
                { role: "primary", column: 0, row: 0 },
                { role: "secondary", column: 1, row: 0 },
                { role: "tertiary", column: 0, row: 1 },
                { role: "primary_container", column: 1, row: 1 }
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
                    color: `#${dial.colours[quarter.modelData.role] ?? "000000"}`
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
            visible: dial.checked
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

    component CardFrame: StyledRect {
        id: frame

        property bool isSelected: false

        Layout.fillWidth: true
        Layout.preferredWidth: 1
        implicitHeight: root.dialSize + Tokens.padding.large * 2
        radius: Tokens.rounding.large
        color: isSelected ? Colours.palette.m3secondaryContainer : Colours.tPalette.m3surfaceContainer
        border.width: isSelected ? 2 : 1
        border.color: isSelected ? Colours.palette.m3secondary : Colours.palette.m3surfaceVariant
    }

    component PaletteCard: CardFrame {
        id: card

        required property var modelData
        required property int index

        isSelected: Colours.scheme === "dynamic" && card.index === root.selected

        StateLayer {
            radius: parent.radius
            onClicked: root.apply(card.modelData)
        }

        Dial {
            anchors.centerIn: parent
            colours: card.modelData?.colours ?? ({})
            checked: card.isSelected
        }
    }

    // Empty until a color is picked: an eyedropper in a plain circle. Picked, it shows the palette
    // that color gave, and a click picks another.
    component CustomCard: CardFrame {
        id: customCard

        isSelected: Colours.scheme === "dynamic" && root.custom.active

        StateLayer {
            radius: parent.radius
            onClicked: root.pickCustom()
        }

        Dial {
            anchors.centerIn: parent
            visible: root.custom.active
            colours: root.custom.colours ?? ({})
            checked: customCard.isSelected
        }

        StyledRect {
            anchors.centerIn: parent
            visible: !root.custom.active
            width: root.dialSize
            height: width
            radius: Tokens.rounding.full
            color: Colours.palette.m3surfaceContainerHighest
            border.width: 1
            border.color: Qt.alpha(Colours.palette.m3outline, 0.5)

            MaterialIcon {
                anchors.centerIn: parent
                text: "colorize"
                color: Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.large
            }
        }
    }
}

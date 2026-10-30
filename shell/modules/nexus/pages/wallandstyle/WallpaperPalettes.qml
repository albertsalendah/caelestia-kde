pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import "../../../../utils/scripts/hexcolor.js" as HexColor

ColumnLayout {
    id: root

    // What `caelestia scheme palettes` printed: the cards, the position of the one in effect (-1
    // when none of them is, for a variant that has no card), and the Custom card's palette: the four
    // colors it shows, and the slots, which hold a #color for each quarter that was picked.
    property var palettes: []
    property int selected: -1
    property var custom: ({ active: false, slots: ({}), colours: ({}) })
    property string pendingSlot: "primary"
    // The slot whose color is being typed, "" when no editor is open.
    property string editing: ""
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
            root.custom = data.custom ?? ({ active: false, slots: ({}), colours: ({}) });
        } catch (e) {
            root.palettes = [];
            root.selected = -1;
            root.custom = ({ active: false, slots: ({}), colours: ({}) });
        }
    }

    // A card is a color of the wallpaper and a variant. Choosing one makes the scheme dynamic,
    // which is what the cards are for whatever scheme is in effect now.
    function apply(entry: var): void {
        Quickshell.execDetached(["caelestia", "scheme", "set", "-n", "dynamic", "-s", String(entry.source), "-v", entry.variant, ...Colours.smartArg]);
    }

    // The Custom card is four key colors, a quarter each, and a click on a quarter picks that one on
    // the screen. The others stay as they were: derived from the primary, or picked before. The
    // variant is stated: the wallpaper's own choice can be a grey one, which would take the color
    // out of what was picked.
    function applyCustom(slot: string, hex: string): void {
        const option = slot === "primary" ? "--seed" : `--${slot}`;
        Quickshell.execDetached(["caelestia", "scheme", "set", "-n", "dynamic", option, hex, "-v", "tonalspot", ...Colours.smartArg]);
    }

    function slotLabel(slot: string): string {
        switch (slot) {
        case "primary":
            return qsTr("Primary");
        case "secondary":
            return qsTr("Secondary");
        case "tertiary":
            return qsTr("Tertiary");
        default:
            return qsTr("Neutral");
        }
    }

    function slotHint(slot: string): string {
        switch (slot) {
        case "primary":
            return qsTr("The main color. The rest of the palette is built from it unless you pick them too.");
        case "secondary":
            return qsTr("The quieter accent, for containers and secondary buttons.");
        case "tertiary":
            return qsTr("The contrasting accent.");
        default:
            return qsTr("Tints the background and the surfaces. A muted color works best.");
        }
    }

    // Opens the editor on a slot, with the color it has now: the one that was picked, or the one it
    // shows because the primary gave it.
    function startEdit(slot: string): void {
        const picked = root.custom.slots?.[slot] ?? "";
        const shown = root.custom.colours?.[slot] ?? "";
        hexField.text = picked.startsWith("#") ? picked : shown ? `#${shown}` : "";
        root.editing = slot;
    }

    function commitEdit(): void {
        const hex = HexColor.normalise(hexField.text);
        if (root.editing === "" || hex === "")
            return;
        root.applyCustom(root.editing, hex);
        root.editing = "";
    }

    function pickCustom(slot: string): void {
        if (eyedropper.running)
            return;
        root.pendingSlot = slot;
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
        text: root.palettes.length > 0 ? qsTr("Colors found in your wallpaper, then variants of the first. On the last card, click a quarter to type a hex color for it: primary, secondary, tertiary and the neutral that tints the background.") : root.loading ? qsTr("Reading the wallpaper...") : qsTr("No colors could be read from the wallpaper.")
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

    // The color of the quarter that was clicked, typed as hex or taken from the screen.
    StyledRect {
        Layout.fillWidth: true
        visible: root.editing !== ""
        implicitHeight: editor.implicitHeight + Tokens.padding.large * 2
        radius: Tokens.rounding.large
        color: Colours.tPalette.m3surfaceContainer

        ColumnLayout {
            id: editor

            anchors.fill: parent
            anchors.margins: Tokens.padding.large
            spacing: Tokens.spacing.medium

            StyledText {
                text: qsTr("%1 color").arg(root.slotLabel(root.editing))
                font: Tokens.font.title.small
            }

            StyledText {
                Layout.fillWidth: true
                text: root.slotHint(root.editing)
                font: Tokens.font.body.small
                color: Colours.palette.m3onSurfaceVariant
                wrapMode: Text.Wrap
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.medium

                StyledRect {
                    implicitWidth: hexField.implicitHeight * 0.7
                    implicitHeight: implicitWidth
                    radius: Tokens.rounding.full
                    color: HexColor.normalise(hexField.text) || Colours.palette.m3surfaceContainerHighest
                    border.width: 1
                    border.color: Qt.alpha(Colours.palette.m3outline, 0.5)
                }

                StyledTextField {
                    id: hexField

                    Layout.fillWidth: true
                    placeholderText: qsTr("#6b5d00")
                    leadingIcon: "tag"
                    errorText: qsTr("Enter a hex color like #6b5d00 or #6b0")
                    inputMethodHints: Qt.ImhNoPredictiveText
                    validate: text => HexColor.normalise(text) !== ""
                    onAccepted: root.commitEdit()
                    Keys.onEscapePressed: root.editing = ""
                }

                IconButton {
                    icon: "colorize"
                    type: IconButton.Tonal
                    onClicked: root.pickCustom(root.editing)
                }
            }

            RowLayout {
                Layout.alignment: Qt.AlignRight
                spacing: Tokens.spacing.medium

                TextButton {
                    text: qsTr("Cancel")
                    type: TextButton.Text
                    onClicked: root.editing = ""
                }

                TextButton {
                    text: qsTr("Apply")
                    type: TextButton.Filled
                    disabled: HexColor.normalise(hexField.text) === ""
                    onClicked: root.commitEdit()
                }
            }
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

    // KWin's own eyedropper, the one the Quick Toggles use: it answers with the color as a number,
    // and with 0 when it was cancelled.
    Process {
        id: eyedropper

        command: ["dbus-send", "--session", "--print-reply", "--dest=org.kde.KWin", "/ColorPicker", "org.kde.kwin.ColorPicker.pick"]
        stdout: StdioCollector {
            onStreamFinished: {
                const match = text.match(/uint32\s+(\d+)/);
                const value = match ? parseInt(match[1]) & 0xFFFFFF : 0;
                if (value !== 0) {
                    root.applyCustom(root.pendingSlot, `#${value.toString(16).padStart(6, "0")}`);
                    root.editing = "";
                }
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

    // One circle in four quarters, like the palette circles of a phone's wallpaper settings: for a
    // wallpaper card the three accents and the tinted container of the first, for the Custom card
    // the four key colors. A quarter is a clipped view of the whole circle.
    component Dial: Item {
        id: dial

        required property var colours
        property var roles: ["primary", "secondary", "tertiary", "primary_container"]
        // The Custom card: a quarter takes a click, and says whether its color was picked.
        property bool interactive: false
        property var picked: [false, false, false, false]
        // Nothing to show yet: the quarters are empty, with an eyedropper to say what they do.
        property bool empty: false
        property bool checked: false

        signal quarterClicked(int position)

        width: root.dialSize
        height: width

        Repeater {
            model: [
                { column: 0, row: 0 },
                { column: 1, row: 0 },
                { column: 0, row: 1 },
                { column: 1, row: 1 }
            ]

            Item {
                id: quarter

                required property var modelData
                required property int index

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
                    color: dial.empty ? Colours.palette.m3surfaceContainerHighest : `#${dial.colours[dial.roles[quarter.index]] ?? "000000"}`
                }

                MaterialIcon {
                    anchors.centerIn: parent
                    visible: dial.empty
                    text: "colorize"
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.small
                }

                // A color that was picked, as against one the primary gave.
                StyledRect {
                    anchors.centerIn: parent
                    visible: dial.picked[quarter.index] ?? false
                    width: Tokens.sizes.launcher.itemHeight * 0.2
                    height: width
                    radius: Tokens.rounding.full
                    color: Colours.palette.m3surface
                    border.width: 2
                    border.color: Colours.palette.m3onSurface
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: dial.interactive
                    cursorShape: dial.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: dial.quarterClicked(quarter.index)
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

    // Empty until a color is picked, with an eyedropper in every quarter. Then it shows the palette the
    // picked colors gave, a dot marks a quarter that was picked, and a click on a quarter picks again.
    component CustomCard: CardFrame {
        id: customCard

        isSelected: Colours.scheme === "dynamic" && root.custom.active

        StateLayer {
            radius: parent.radius
        }

        Dial {
            anchors.centerIn: parent
            colours: root.custom.colours ?? ({})
            roles: ["primary", "secondary", "tertiary", "neutral"]
            interactive: true
            empty: !root.custom.active
            checked: customCard.isSelected
            picked: ["primary", "secondary", "tertiary", "neutral"].map(slot => (root.custom.slots?.[slot] ?? "").startsWith("#"))
            onQuarterClicked: position => root.startEdit(["primary", "secondary", "tertiary", "neutral"][position])
        }
    }
}

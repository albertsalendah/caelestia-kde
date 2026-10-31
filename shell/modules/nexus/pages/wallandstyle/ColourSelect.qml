pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.launcher.services
import qs.modules.nexus.common
import "../../../../utils/scripts/variantcolours.js" as VariantColours

PageBase {
    id: root

    property var lightSchemes: []
    property var darkSchemes: []
    // The colors each variant gives, for the swatches: {variant: colours}, read on the first look at
    // the section and again when what a preview derives from changes.
    property var variantColours: ({})
    property string variantsLoadedKey: ""
    property bool variantsStale: false

    // A preview derives from the wallpaper for a dynamic scheme, from the shipped colors otherwise,
    // in the light or the dark mode, so these are what it depends on. A variant that is chosen is not.
    readonly property string variantKey: `${Schemes.currentScheme}|${Colours.currentLight}|${Wallpapers.actualCurrent}|${Colours.smartArg.join(" ")}`

    function parseSchemeList(json: string): void {
        const light = [];
        const dark = [];
        try {
            const entries = JSON.parse(json);
            for (const s of entries) {
                const entry = { name: s.name, flavour: s.flavour, mode: s.mode, colours: s.colours };
                if (String(s.mode).toLowerCase().includes("light"))
                    light.push(entry);
                else
                    dark.push(entry);
            }
        } catch (e) {
        }
        root.lightSchemes = light;
        root.darkSchemes = dark;
    }

    // One run for all of them, one after another: a preview is written to a single file.
    function loadVariants(): void {
        if (variantProc.running) {
            root.variantsStale = true;
            return;
        }
        root.variantsLoadedKey = root.variantKey;
        variantProc.command = ["sh", "-c",
            'smart="$1"; shift; for v in "$@"; do printf "%s\\t" "$v"; caelestia scheme set --preview -v "$v" $smart | tr -d "\\n"; printf "\\n"; done',
            "--", Colours.smartArg.join(" "), ...M3Variants.list.map(v => v.variant)];
        variantProc.running = true;
    }

    title: qsTr("Colors")
    isSubPage: true

    onVariantKeyChanged: {
        if (variantsSection.expanded)
            root.loadVariants();
    }

    Component.onCompleted: {
        Schemes.reload();
        schemeListProc.running = true;
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.large

        StyledRect {
            id: dynamicCard

            readonly property bool isSelected: Colours.scheme === "dynamic"

            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.medium
            implicitHeight: dynamicRow.implicitHeight + Tokens.padding.large * 2
            radius: Tokens.rounding.large
            color: isSelected ? Colours.palette.m3secondaryContainer : Colours.tPalette.m3surfaceContainer
            border.width: isSelected ? 2 : 1
            border.color: isSelected ? Colours.palette.m3secondary : Colours.palette.m3surfaceVariant

            StateLayer {
                radius: parent.radius
                onClicked: {
                    const wall = Wallpapers.actualCurrent || Wallpapers.fallback;
                    const smartArg = Colours.smartArg.join(" ");
                    Quickshell.execDetached(["sh", "-c",
                        `caelestia wallpaper -f "$1" ${smartArg} >/dev/null 2>&1; caelestia scheme set ${smartArg} -n dynamic`,
                        "--", wall]);
                }
            }

            RowLayout {
                id: dynamicRow

                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.large

                StyledRect {
                    Layout.preferredWidth: Tokens.sizes.launcher.itemHeight
                    Layout.preferredHeight: Tokens.sizes.launcher.itemHeight

                    border.width: 1
                    border.color: Qt.alpha(Colours.palette.m3outline, 0.5)
                    color: Colours.palette.m3surface
                    radius: Tokens.rounding.full

                    Item {
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.right: parent.right

                        width: parent.width / 2
                        clip: true

                        StyledRect {
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.right: parent.right

                            width: parent.width
                            color: Colours.palette.m3primary
                            radius: Tokens.rounding.full
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.extraSmall

                    StyledText {
                        Layout.fillWidth: true
                        text: qsTr("Dynamic")
                        font: Tokens.font.title.small
                        color: dynamicCard.isSelected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: qsTr("Colors that follow your wallpaper")
                        font: Tokens.font.body.medium
                        color: dynamicCard.isSelected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                    }
                }

                MaterialIcon {
                    Layout.alignment: Qt.AlignVCenter
                    visible: dynamicCard.isSelected
                    text: "check"
                    color: Colours.palette.m3onSecondaryContainer
                    fontStyle: Tokens.font.icon.large
                }

                IconButton {
                    id: settingsBtn

                    Layout.alignment: Qt.AlignVCenter
                    icon: "settings"
                    type: IconButton.Tonal
                    onClicked: root.nState.openSubPage(10)
                }
            }
        }

        CollapsibleSection {
            id: variantsSection

            title: qsTr("Variants")

            onExpandedChanged: {
                if (expanded && root.variantsLoadedKey !== root.variantKey)
                    root.loadVariants();
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                rowSpacing: Tokens.spacing.medium
                columnSpacing: Tokens.spacing.medium

                Repeater {
                    model: M3Variants.list

                    StyledRect {
                        id: varDelegateRect

                        required property var modelData

                        readonly property bool isSelected: modelData?.variant === Schemes.currentVariant

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredWidth: 1
                        implicitHeight: varCol.implicitHeight + Tokens.padding.large * 2
                        radius: Tokens.rounding.large
                        color: isSelected ? Colours.palette.m3secondaryContainer : Colours.tPalette.m3surfaceContainer
                        border.width: isSelected ? 2 : 1
                        border.color: isSelected ? Colours.palette.m3secondary : Colours.palette.m3surfaceVariant

                        StateLayer {
                            radius: parent.radius
                            onClicked: varDelegateRect.modelData?.onClicked(null)
                        }

                        RowLayout {
                            id: varCol

                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.margins: Tokens.padding.large
                            spacing: Tokens.spacing.large

                            StyledRect {
                                id: swatch

                                readonly property var colours: root.variantColours[varDelegateRect.modelData?.variant]

                                Layout.alignment: Qt.AlignTop
                                Layout.preferredWidth: Tokens.sizes.launcher.itemHeight
                                Layout.preferredHeight: Tokens.sizes.launcher.itemHeight

                                border.width: 1
                                border.color: Qt.alpha(colours ? `#${colours.outline}` : Colours.palette.m3outline, 0.5)
                                color: colours ? `#${colours.surface}` : Colours.palette.m3surfaceContainerHighest
                                radius: Tokens.rounding.full

                                Item {
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    anchors.right: parent.right

                                    width: parent.width / 2
                                    clip: true

                                    StyledRect {
                                        anchors.top: parent.top
                                        anchors.bottom: parent.bottom
                                        anchors.right: parent.right

                                        width: parent.width
                                        color: swatch.colours ? `#${swatch.colours.primary}` : Colours.palette.m3outlineVariant
                                        radius: Tokens.rounding.full
                                    }
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Tokens.spacing.extraSmall

                                StyledText {
                                    Layout.fillWidth: true
                                    text: varDelegateRect.modelData?.name ?? ""
                                    font: Tokens.font.title.small
                                    color: varDelegateRect.isSelected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: varDelegateRect.modelData?.description ?? ""
                                    font: Tokens.font.body.medium
                                    color: varDelegateRect.isSelected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                                    wrapMode: Text.Wrap
                                }
                            }
                        }
                    }
                }
            }
        }

        CollapsibleSection {
            id: lightSection

            title: qsTr("Light")

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                rowSpacing: Tokens.spacing.medium
                columnSpacing: Tokens.spacing.medium

                Repeater {
                    model: root.lightSchemes

                    PaletteCard {}
                }
            }
        }

        CollapsibleSection {
            id: darkSection

            title: qsTr("Dark")

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                rowSpacing: Tokens.spacing.medium
                columnSpacing: Tokens.spacing.medium

                Repeater {
                    model: root.darkSchemes

                    PaletteCard {}
                }
            }
        }

        Process {
            id: variantProc

            stdout: StdioCollector {
                onStreamFinished: root.variantColours = VariantColours.parse(text)
            }
            onExited: {
                if (root.variantsStale) {
                    root.variantsStale = false;
                    if (variantsSection.expanded && root.variantsLoadedKey !== root.variantKey)
                        root.loadVariants();
                }
            }
        }

        Process {
            id: schemeListProc

            command: ["caelestia", "scheme", "list", "--flat"]
            stdout: StdioCollector {
                onStreamFinished: root.parseSchemeList(text)
            }
        }
    }

    // A heading that opens and closes what is under it, closed to begin with. Whatever is put inside
    // goes under the heading.
    component CollapsibleSection: ColumnLayout {
        id: section

        property string title
        property bool expanded: false
        default property alias content: body.data

        Layout.fillWidth: true
        spacing: Tokens.spacing.medium

        StyledRect {
            Layout.fillWidth: true
            implicitHeight: headerRow.implicitHeight + Tokens.padding.large * 2
            radius: Tokens.rounding.large
            color: Colours.tPalette.m3surfaceContainer
            border.width: 1
            border.color: Colours.palette.m3surfaceVariant

            StateLayer {
                radius: parent.radius
                onClicked: section.expanded = !section.expanded
            }

            RowLayout {
                id: headerRow

                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.large

                StyledText {
                    Layout.fillWidth: true
                    text: section.title
                    font: Tokens.font.title.medium
                }

                MaterialIcon {
                    text: "expand_more"
                    rotation: section.expanded ? 180 : 0
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.large

                    Behavior on rotation {
                        Anim {
                            type: Anim.DefaultEffects
                        }
                    }
                }
            }
        }

        ColumnLayout {
            id: body

            Layout.fillWidth: true
            spacing: Tokens.spacing.medium
            visible: section.expanded
        }
    }

    component PaletteCard: StyledRect {
        id: card

        required property var modelData

        readonly property bool isSelected: `${modelData?.name} ${modelData?.flavour}` === Schemes.currentScheme && ((modelData?.mode === "light") === Colours.light)

        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredWidth: 1
        implicitHeight: cardRow.implicitHeight + Tokens.padding.large * 2
        radius: Tokens.rounding.large
        color: isSelected ? Colours.palette.m3secondaryContainer : Colours.tPalette.m3surfaceContainer
        border.width: isSelected ? 2 : 1
        border.color: isSelected ? Colours.palette.m3secondary : Colours.palette.m3surfaceVariant

        StateLayer {
            radius: parent.radius
            onClicked: {
                Colours.previewNamed(card.modelData.name, card.modelData.flavour, card.modelData.colours, card.modelData.mode === "light");
                setScheme.command = ["caelestia", "scheme", "set", "-n", card.modelData.name,
                    "-f", card.modelData.flavour, "-m", card.modelData.mode, ...Colours.smartArg];
                setScheme.running = true;
            }
        }

        Process {
            id: setScheme

            onExited: code => {
                if (code !== 0)
                    Colours.clearPreview();
            }
        }

        RowLayout {
            id: cardRow

            anchors.fill: parent
            anchors.margins: Tokens.padding.large
            spacing: Tokens.spacing.large

            StyledRect {
                Layout.preferredWidth: Tokens.sizes.launcher.itemHeight
                Layout.preferredHeight: Tokens.sizes.launcher.itemHeight

                border.width: 1
                border.color: Qt.alpha(`#${card.modelData?.colours?.outline}`, 0.5)
                color: `#${card.modelData?.colours?.surface}`
                radius: Tokens.rounding.full

                Item {
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.right: parent.right

                    width: parent.width / 2
                    clip: true

                    StyledRect {
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.right: parent.right

                        width: parent.width
                        color: `#${card.modelData?.colours?.primary}`
                        radius: Tokens.rounding.full
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.extraSmall

                StyledText {
                    Layout.fillWidth: true
                    text: card.modelData?.flavour ?? ""
                    font: Tokens.font.title.small
                    color: card.isSelected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
                }
                StyledText {
                    Layout.fillWidth: true
                    text: card.modelData?.name ?? ""
                    font: Tokens.font.body.medium
                    color: card.isSelected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                }
            }

            MaterialIcon {
                Layout.alignment: Qt.AlignVCenter
                visible: card.isSelected
                text: "check"
                color: Colours.palette.m3onSecondaryContainer
                fontStyle: Tokens.font.icon.large
            }
        }
    }
}

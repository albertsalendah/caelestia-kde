pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.services
import "../../../utils/scripts/displays.js" as Logic

// The arrangement of the monitors as rectangles in proportion, one per monitor that extends the
// desktop. Drag one and let go: it snaps to the nearest place where it touches another monitor
// (Logic.snapLayout) and `dropped` is emitted with where it ended up. The page applies it.
Item {
    id: root

    // Logic.layoutRects(...): {name, x, y, w, h} in logical pixels
    property var rects: []
    // {name: heading shown on the rectangle}
    property var titles: ({})
    property string primary: ""
    // {name, x, y}: a monitor that was just dropped, shown there until the layout is read again
    property var drop: null
    // How close (in canvas pixels) a drop has to be to the top, middle or bottom of another
    // monitor's edge to line up with it.
    property real snapDistance: 14

    signal dropped(name: string, x: real, y: real)

    readonly property var view: Logic.canvasView(rects)
    readonly property real fit: Logic.fitScale(view, width, height)
    readonly property real offsetX: (width - view.w * fit) / 2
    readonly property real offsetY: (height - view.h * fit) / 2

    // Logical pixels to canvas pixels.
    function px(x: real): real {
        return offsetX + (x - view.x) * fit;
    }

    function py(y: real): real {
        return offsetY + (y - view.y) * fit;
    }

    implicitHeight: 220
    clip: true

    StyledRect {
        anchors.fill: parent
        color: Colours.tPalette.m3surfaceContainer
        radius: Tokens.rounding.large
    }

    Repeater {
        model: root.rects

        StyledRect {
            id: tile

            required property var modelData

            // While it is dragged the rectangle follows the pointer; the position in the layout
            // only changes when the change has been applied.
            property real dragX: 0
            property real dragY: 0
            readonly property bool isPrimary: modelData.name === root.primary

            x: root.px(root.drop && root.drop.name === modelData.name ? root.drop.x : modelData.x) + dragX
            y: root.py(root.drop && root.drop.name === modelData.name ? root.drop.y : modelData.y) + dragY
            width: modelData.w * root.fit
            height: modelData.h * root.fit
            z: area.pressed ? 1 : 0
            radius: Tokens.rounding.small
            color: isPrimary ? Colours.palette.m3primaryContainer : Colours.palette.m3secondaryContainer

            Column {
                anchors.centerIn: parent
                width: parent.width - Tokens.padding.small * 2
                spacing: 0

                StyledText {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: root.titles[tile.modelData.name] ?? tile.modelData.name
                    color: tile.isPrimary ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSecondaryContainer
                    font: Tokens.font.body.small
                    elide: Text.ElideRight
                }

                StyledText {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: tile.isPrimary ? qsTr("%1 × %2 · primary").arg(tile.modelData.w).arg(tile.modelData.h) : qsTr("%1 × %2").arg(tile.modelData.w).arg(tile.modelData.h)
                    color: tile.isPrimary ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSecondaryContainer
                    font: Tokens.font.label.small
                    elide: Text.ElideRight
                }
            }

            MouseArea {
                id: area

                property real startX
                property real startY

                anchors.fill: parent
                // Not while a change is being applied: it would be ignored, and the monitor would
                // look as if it had not snapped.
                enabled: !Displays.busy
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                preventStealing: true

                onPressed: e => {
                    const p = mapToItem(root, e.x, e.y);
                    startX = p.x;
                    startY = p.y;
                }
                onPositionChanged: e => {
                    if (!pressed)
                        return;
                    const p = mapToItem(root, e.x, e.y);
                    tile.dragX = p.x - startX;
                    tile.dragY = p.y - startY;
                }
                onReleased: {
                    const x = tile.modelData.x + tile.dragX / root.fit;
                    const y = tile.modelData.y + tile.dragY / root.fit;
                    tile.dragX = 0;
                    tile.dragY = 0;
                    const snapped = Logic.snapLayout(root.rects, tile.modelData.name, x, y, root.snapDistance / root.fit);
                    if (snapped.changed)
                        root.dropped(tile.modelData.name, snapped.x, snapped.y);
                }
            }
        }
    }
}

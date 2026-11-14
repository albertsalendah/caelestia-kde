pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: root

    property bool expanded: false
    property int count: sessionModel ? sessionModel.count : 0
    property var items: []
    property int selectedIndex: 0
    property string currentText

    // Builds the list and the label from the sessions the instantiator has made so far. The
    // instantiator makes its items after this picker has completed (Qt 6.11 on Fedora 44), so
    // reading them once at completion found none, threw, and left the label and the list
    // empty. Every item calls this when it appears, so the last one has the full list.
    function refresh(): void {
        const sessions = sessionArray.sessions;
        const arr = [];
        for (let i = 0; i < sessions.length; i++) {
            arr.push(sessions[i].name ?? "");
        }
        root.items = arr;
        if (arr.length > 0)
            root.currentText = arr[Math.min(root.selectedIndex, arr.length - 1)];
    }

    Component.onCompleted: root.refresh()
    onSelectedIndexChanged: root.refresh()

    width: labelRect.width + expandBtn.width
    height: 40
    opacity: root.count > 0 ? 1 : 0
    enabled: root.count > 0

    Instantiator {
        id: sessionArray
        model: sessionModel
        property var sessions: []

        delegate: Item {
            required property int index
            required property var model

            Component.onCompleted: {
                sessionArray.sessions.push({
                    index: index,
                    name: model.name
                });
                root.refresh();
            }
        }
    }

    Rectangle {
        id: labelRect

        radius: height / 2
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        topLeftRadius: height / 2
        bottomLeftRadius: height / 2
        topRightRadius: 5
        bottomRightRadius: 5
        color: Qt.alpha(config.text, 0.1)

        width: 210

        Text {
            id: labelIcon

            anchors.left: parent.left
            anchors.leftMargin: 15
            anchors.verticalCenter: parent.verticalCenter
            font.family: "Material Symbols Rounded"
            font.pointSize: 16
            text: "widgets"
            color: config.primary
        }

        Text {
            id: labelText

            anchors.left: labelIcon.right
            anchors.leftMargin: 6
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            renderType: Text.NativeRendering
            text: root.currentText
            color: config.text
            font.pixelSize: 14
            font.family: "Rubik"
            elide: Text.ElideRight
        }

        LayerState {
            anchors.fill: parent
            parentWidth: labelRect.width
            parentHeight: labelRect.height
            parentRadius: labelRect.radius
            disabled: true
            topRightradius: labelRect.topRightRadius
            bottomRightradius: labelRect.bottomRightRadius
        }
    }

    Rectangle {
        id: expandBtn

        property real rad: root.expanded ? height / 2 : 5

        radius: height / 2
        anchors.left: labelRect.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        topLeftRadius: rad
        bottomLeftRadius: rad
        color: config.primary

        width: height

        Behavior on topLeftRadius {
            NumberAnimation {
                duration: 200
                easing.type: Easing.InOutCubic
            }
        }

        Behavior on bottomLeftRadius {
            NumberAnimation {
                duration: 200
                easing.type: Easing.InOutCubic
            }
        }

        Text {
            id: expandIcon

            anchors.centerIn: expandBtn
            anchors.horizontalCenterOffset: root.expanded ? 0 : -2
            font.family: "Material Symbols Rounded"
            font.pointSize: 18
            text: "expand_more"
            color: config.onPrimary
            rotation: root.expanded ? 180 : 0

            Behavior on anchors.horizontalCenterOffset {
                NumberAnimation {
                    duration: 200
                    easing.type: Easing.InOutCubic
                }
            }

            Behavior on rotation {
                NumberAnimation {
                    duration: 200
                    easing.type: Easing.InOutCubic
                }
            }
        }

        LayerState {
            anchors.fill: parent
            parentWidth: expandBtn.width
            parentHeight: expandBtn.height
            parentRadius: expandBtn.radius
            onClicked: root.expanded = !root.expanded
        }
    }

    Rectangle {
        id: menuRect

        visible: root.expanded
        // The list opens over other boxes, so it stays solid.
        color: config.surfaceContainerHigh
        radius: 8
        border.color: config.outline
        border.width: 1

        anchors.top: labelRect.bottom
        anchors.topMargin: 4
        anchors.left: labelRect.left
        anchors.leftMargin: -10
        width: 260
        height: Math.min(200, root.count * 36)

        clip: true

        opacity: root.expanded ? 1 : 0
        transform: Translate {
            y: root.expanded ? 0 : -10
        }

        Behavior on opacity {
            NumberAnimation {
                duration: 150
                easing.type: Easing.InOutCubic
            }
        }

        Behavior on y {
            NumberAnimation {
                duration: 150
                easing.type: Easing.InOutCubic
            }
        }

        ListView {
            id: sessionList

            anchors.fill: parent
            anchors.margins: 4
            model: root.items
            currentIndex: root.selectedIndex
            clip: true
            boundsBehavior: ListView.StopAtBounds
            contentHeight: root.count * 32
            implicitHeight: contentHeight

            delegate: Rectangle {
                id: delegateItem

                required property int index

                width: parent.width
                height: 32
                radius: 4
                color: index === ListView.view.currentIndex ? config.primary : "transparent"
                opacity: index === ListView.view.currentIndex ? 0.2 : 1

                Behavior on color {
                    ColorAnimation {
                        duration: 100
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.selectedIndex = delegateItem.index;
                        root.currentText = root.items[delegateItem.index];
                        root.expanded = false;
                    }
                }

                Text {
                    renderType: Text.NativeRendering
                    anchors.centerIn: parent
                    text: root.items[delegateItem.index]
                    color: config.text
                    font.pixelSize: 13
                    font.family: "Rubik"
                    elide: Text.ElideRight
                    leftPadding: 4
                    rightPadding: 4
                }
            }
        }
    }

    MouseArea {
        id: dismissArea

        anchors.fill: root
        z: -1
        enabled: root.expanded
        onClicked: root.expanded = false
    }
}

import QtQuick

QtObject {
    property string text: ""
    property string icon
    property string trailingIcon
    property string activeIcon: icon
    property string activeText: text
    property bool visible: true
    // A row that opens another menu keeps this one open when it is clicked.
    property bool keepOpen: false
    property var value

    signal clicked
}

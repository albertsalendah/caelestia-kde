// X-Caelestia-Managed=true
// Stand-in for TaskManager.ScreencastingRequest (plasma-workspace, libtaskmanager). The portal's
// picker sets outputName or uuid and reads objectSerial to draw a live thumbnail. This one never
// opens a stream, so objectSerial stays 0 and the picker shows the application icon instead.
import QtQuick

QtObject {
    property string outputName
    property string uuid
    property var objectSerial: 0
    property int nodeId: 0
}

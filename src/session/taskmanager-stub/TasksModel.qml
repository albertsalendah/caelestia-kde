// X-Caelestia-Managed=true
// Stand-in for TaskManager.TasksModel (plasma-workspace, libtaskmanager). The portal's picker lists
// the windows on each screen as small icons under the screen's name. This model is always empty, so
// the picker shows "No windows open" next to every screen name; sharing a screen is not affected.
import QtQuick

ListModel {
    enum SortMode {
        SortLastActivated
    }

    property bool filterByScreen: false
    property rect screenGeometry
    property int sortMode: 0
}

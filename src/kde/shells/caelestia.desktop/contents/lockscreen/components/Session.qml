
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasma5support as Plasma5Support
import ".."
import "../LockScreenHelpers.js" as Helpers

Item {
    id: root

    implicitWidth: visibleActions.length > 0 ? contentCol.implicitWidth : 0
    implicitHeight: visibleActions.length > 0 ? (actionsRow.height + Math.max(12, Math.round(14 * root.centerScale)) + contentCol.spacing) : 0
    width: implicitWidth
    height: implicitHeight

    property bool isAuthenticating: false
    property real centerScale: 1.0

    property color clPrimary
    property color clSurfaceVariantFg
    property color clSurfaceFg: clPrimary

    property var customIcons: ({})

    property bool showSleep: true
    property bool showHibernate: false
    property bool showSwitchUser: true
    property bool showLogout: true
    property bool showReboot: false
    property bool showShutdown: false

    property string hoveredAction: ""
    property string hoveredLabel: ""

    signal actionTriggered(string action)
    signal aboutToSuspend()

    // What the system allows, asked of logind and the display manager at start (the defaults hold
    // until it answers). These replace org.kde.plasma.private.sessions, which only plasma-workspace has.
    readonly property string capabilitiesCommand: "for m in CanSuspend CanHibernate CanReboot CanPowerOff; do printf '%s=%s\\n' \"$m\" \"$(busctl --system call org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager \"$m\" 2>/dev/null | cut -d'\"' -f2)\"; done; if busctl --system introspect org.freedesktop.DisplayManager \"${XDG_SEAT_PATH:-/org/freedesktop/DisplayManager/Seat0}\" org.freedesktop.DisplayManager.Seat >/dev/null 2>&1; then echo SwitchUser=yes; else echo SwitchUser=no; fi"
    // Switch user asks the display manager for its greeter (SDDM and GDM answer on the system bus,
    // LightDM through dm-tool); the session stays logged in and the lock screen stays up.
    readonly property string switchUserCommand: "busctl --system call org.freedesktop.DisplayManager \"${XDG_SEAT_PATH:-/org/freedesktop/DisplayManager/Seat0}\" org.freedesktop.DisplayManager.Seat SwitchToGreeter 2>/dev/null || dm-tool switch-to-greeter 2>/dev/null"
    property bool canSuspend: true
    property bool canHibernate: false
    property bool canSwitchUser: false
    readonly property bool canLogout: true
    property bool canReboot: true
    property bool canShutdown: true

    readonly property var visibleActions: {
        var actions = [];

        if (root.showSleep && root.canSuspend) {
            actions.push({
                actionId: "suspend",
                icon: (root.customIcons && root.customIcons.suspend) ? root.customIcons.suspend : "bedtime",
                label: qsTr("Sleep"),
                trigger: () => root.suspend()
            });
        }

        if (root.showHibernate && root.canHibernate) {
            actions.push({
                actionId: "hibernate",
                icon: (root.customIcons && root.customIcons.hibernate) ? root.customIcons.hibernate : "mode_night",
                label: qsTr("Hibernate"),
                trigger: () => root.hibernate()
            });
        }

        if (root.showSwitchUser && root.canSwitchUser) {
            actions.push({
                actionId: "switchUser",
                icon: (root.customIcons && root.customIcons.switchUser) ? root.customIcons.switchUser : "manage_accounts",
                label: qsTr("Switch User"),
                trigger: () => root.switchUser()
            });
        }

        if (root.showLogout && root.canLogout) {
            actions.push({
                actionId: "logout",
                icon: (root.customIcons && root.customIcons.logout) ? root.customIcons.logout : "logout",
                label: qsTr("Log Out"),
                trigger: () => root.logout()
            });
        }

        if (root.showReboot && root.canReboot) {
            actions.push({
                actionId: "reboot",
                icon: (root.customIcons && root.customIcons.reboot) ? root.customIcons.reboot : "restart_alt",
                label: qsTr("Restart"),
                trigger: () => root.reboot()
            });
        }

        if (root.showShutdown && root.canShutdown) {
            actions.push({
                actionId: "shutdown",
                icon: (root.customIcons && root.customIcons.shutdown) ? root.customIcons.shutdown : "power_settings_new",
                label: qsTr("Shut Down"),
                trigger: () => root.shutdown()
            });
        }

        return actions;
    }

    visible: visibleActions.length > 0

    function suspend(): void {
        root.actionTriggered("suspend");
        root.aboutToSuspend();
        Qt.callLater(root.requestSuspend);
    }

    function requestSuspend(): void {
        sessionActionSource.connectSource("systemctl suspend 2>/dev/null");
    }

    function hibernate(): void {
        root.actionTriggered("hibernate");
        root.aboutToSuspend();
        sessionActionSource.connectSource("systemctl hibernate 2>/dev/null");
    }

    function switchUser(): void {
        root.actionTriggered("switchUser");
        sessionActionSource.connectSource(root.switchUserCommand);
    }

    function logout(): void {
        root.actionTriggered("logout");
        sessionActionSource.connectSource("qdbus6 org.kde.Shutdown /Shutdown org.kde.Shutdown.logout 2>/dev/null || systemctl --user stop caelestia-kwin.service");
    }

    function reboot(): void {
        root.actionTriggered("reboot");
        sessionActionSource.connectSource("qdbus6 org.kde.Shutdown /Shutdown org.kde.Shutdown.logoutAndReboot 2>/dev/null || systemctl reboot 2>/dev/null");
    }

    function shutdown(): void {
        root.actionTriggered("shutdown");
        sessionActionSource.connectSource("qdbus6 org.kde.Shutdown /Shutdown org.kde.Shutdown.logoutAndShutdown 2>/dev/null || systemctl poweroff 2>/dev/null");
    }

    function triggerAction(actionId: string): void {
        for (var i = 0; i < visibleActions.length; i++) {
            if (visibleActions[i].actionId === actionId) {
                visibleActions[i].trigger();
                return;
            }
        }
    }

    Component.onCompleted: capabilitiesSource.connectSource(root.capabilitiesCommand)

    Plasma5Support.DataSource {
        id: capabilitiesSource
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            const can = Helpers.parseCapabilities(data.stdout);
            root.canSuspend = can.suspend;
            root.canHibernate = can.hibernate;
            root.canReboot = can.reboot;
            root.canShutdown = can.shutdown;
            root.canSwitchUser = can.switchUser;
            disconnectSource(source);
        }
    }

    Plasma5Support.DataSource {
        id: sessionActionSource
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => disconnectSource(source)
    }

    Column {
        id: contentCol
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 2 * root.centerScale

        Row {
            id: actionsRow
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 6 * root.centerScale

            Repeater {
                model: root.visibleActions

                Item {
                    id: actionBtn
                    width: Math.max(26, Math.round(32 * root.centerScale))
                    height: width

                    readonly property var actionData: modelData
                    readonly property bool isHovered: btnMouse.containsMouse

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: actionBtn.isHovered ? Qt.rgba(root.clPrimary.r, root.clPrimary.g, root.clPrimary.b, 0.12) : "transparent"
                        scale: btnMouse.pressed ? 0.88 : actionBtn.isHovered ? 1.05 : 1.0

                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on scale { NumberAnimation { duration: 100 } }

                        Text {
                            anchors.centerIn: parent
                            text: actionBtn.actionData.icon
                            font.family: LockScreenConfig.fontIcon
                            font.pixelSize: Math.max(16, Math.round(20 * root.centerScale))
                            color: actionBtn.isHovered ? root.clPrimary : root.clSurfaceVariantFg

                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                    }

                    MouseArea {
                        id: btnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: {
                            root.hoveredAction = actionBtn.actionData.actionId;
                            root.hoveredLabel = actionBtn.actionData.label;
                        }
                        onExited: {
                            if (root.hoveredAction === actionBtn.actionData.actionId) {
                                root.hoveredAction = "";
                                root.hoveredLabel = "";
                            }
                        }
                        onClicked: actionBtn.actionData.trigger()
                    }
                }
            }
        }

        Item {
            id: labelContainer
            width: actionsRow.width
            height: Math.max(12, Math.round(14 * root.centerScale))
            anchors.horizontalCenter: parent.horizontalCenter

            Text {
                renderType: Text.NativeRendering
                anchors.centerIn: parent
                text: root.hoveredLabel
                font.family: LockScreenConfig.fontBody
                font.pixelSize: Math.max(10, Math.round(12 * root.centerScale))
                color: root.clPrimary
                opacity: root.hoveredLabel.length > 0 ? 1 : 0

                Behavior on opacity { NumberAnimation { duration: 150 } }
            }
        }
    }
}

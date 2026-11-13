import QtQuick

// Network status for the login screen. Nobody is logged in here, so there is no network service to
// ask: the kernel's own tables are read, which the greeter can do (the same way it loads the quote).
// "Connected" means a default route is up; it does not say that the internet answers.
Item {
    id: root

    // Polling runs only while the card is shown.
    property bool active: true
    property color color: "white"
    property color accent: "white"

    property string iface: ""
    // Wi-Fi link quality in percent, -1 when the interface is not wireless.
    property int signalPercent: -1
    // Bytes per second; -1 until two samples of the same interface exist.
    property real rxRate: -1
    property real txRate: -1

    readonly property bool connected: iface !== ""
    readonly property bool wireless: signalPercent >= 0
    readonly property string iconName: !connected ? "wifi_off" : !wireless ? "lan" : signalPercent >= 67 ? "wifi" : signalPercent >= 34 ? "wifi_2_bar" : "wifi_1_bar"

    property real _lastRx: 0
    property real _lastTx: 0
    property real _lastTime: 0

    // The interface of the default route with the lowest metric, or "" without one.
    function defaultInterface(routeText) {
        let best = "";
        let bestMetric = Infinity;
        const lines = routeText.split("\n");
        for (let i = 1; i < lines.length; i++) {
            const f = lines[i].trim().split(/\s+/);
            if (f.length < 8 || f[1] !== "00000000" || f[7] !== "00000000")
                continue;
            if ((parseInt(f[3], 16) & 1) === 0)
                continue;
            const metric = parseInt(f[6], 10);
            if (metric < bestMetric) {
                bestMetric = metric;
                best = f[0];
            }
        }
        return best;
    }

    // Link quality of a wireless interface in percent (the kernel reports it out of 70), -1 when the
    // interface is not in the table.
    function wirelessQuality(wirelessText, name) {
        const lines = wirelessText.split("\n");
        for (let i = 2; i < lines.length; i++) {
            const line = lines[i].trim();
            const colon = line.indexOf(":");
            if (colon < 0 || line.substring(0, colon) !== name)
                continue;
            const link = parseFloat(line.substring(colon + 1).trim().split(/\s+/)[1]);
            return isNaN(link) ? 0 : Math.max(0, Math.min(100, Math.round(link / 70 * 100)));
        }
        return -1;
    }

    // Received and sent bytes of an interface from /proc/net/dev, or null.
    function byteCounters(devText, name) {
        const lines = devText.split("\n");
        for (let i = 2; i < lines.length; i++) {
            const line = lines[i].trim();
            const colon = line.indexOf(":");
            if (colon < 0 || line.substring(0, colon) !== name)
                continue;
            const f = line.substring(colon + 1).trim().split(/\s+/);
            return {
                rx: parseFloat(f[0]),
                tx: parseFloat(f[8])
            };
        }
        return null;
    }

    function formatRate(bytesPerSecond) {
        const units = ["B/s", "KB/s", "MB/s", "GB/s"];
        let value = Math.max(0, bytesPerSecond);
        let unit = 0;
        while (value >= 1024 && unit < units.length - 1) {
            value /= 1024;
            unit++;
        }
        return (unit === 0 || value >= 100 ? Math.round(value) : value.toFixed(1)) + " " + units[unit];
    }

    function readFile(path, done) {
        const xhr = new XMLHttpRequest();
        xhr.open("GET", "file://" + path);
        xhr.onreadystatechange = function () {
            if (xhr.readyState === XMLHttpRequest.DONE)
                done(xhr.responseText);
        };
        xhr.send();
    }

    function sample() {
        readFile("/proc/net/route", route => {
            const name = defaultInterface(route);
            if (name === "") {
                root.iface = "";
                root.signalPercent = -1;
                root.rxRate = -1;
                root.txRate = -1;
                root._lastTime = 0;
                return;
            }
            readFile("/proc/net/wireless", wireless => {
                readFile("/proc/net/dev", dev => {
                    const now = Date.now();
                    const counters = byteCounters(dev, name);
                    if (counters && root._lastTime > 0 && name === root.iface) {
                        const seconds = (now - root._lastTime) / 1000;
                        root.rxRate = (counters.rx - root._lastRx) / seconds;
                        root.txRate = (counters.tx - root._lastTx) / seconds;
                    } else {
                        root.rxRate = -1;
                        root.txRate = -1;
                    }
                    root._lastRx = counters ? counters.rx : 0;
                    root._lastTx = counters ? counters.tx : 0;
                    root._lastTime = counters ? now : 0;
                    root.signalPercent = wirelessQuality(wireless, name);
                    root.iface = name;
                });
            });
        });
    }

    anchors.fill: parent

    Timer {
        interval: 2000
        repeat: true
        running: root.active
        triggeredOnStart: true
        onTriggered: root.sample()
    }

    Column {
        anchors.centerIn: parent
        spacing: 14

        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 80
            height: 80

            Text {
                anchors.centerIn: parent
                text: root.iconName
                color: root.connected ? root.accent : root.color
                opacity: root.connected ? 1 : 0.5
                font.family: "Material Symbols Rounded"
                font.pointSize: 54
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            renderType: Text.NativeRendering
            text: root.connected ? "Connected" : "Offline"
            color: root.color
            font.family: "Rubik"
            font.pointSize: 22
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            renderType: Text.NativeRendering
            text: !root.connected ? "No network connection" : (root.wireless ? "Wi-Fi" : "Ethernet") + " \u00b7 " + root.iface
            color: root.color
            opacity: 0.7
            font.family: "Rubik"
            font.pointSize: 12
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.wireless
            renderType: Text.NativeRendering
            text: "Signal " + root.signalPercent + "%"
            color: root.color
            opacity: 0.7
            font.family: "Rubik"
            font.pointSize: 12
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.rxRate >= 0
            spacing: 18

            Row {
                spacing: 4

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "arrow_downward"
                    color: root.accent
                    font.family: "Material Symbols Rounded"
                    font.pointSize: 14
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    renderType: Text.NativeRendering
                    text: root.formatRate(root.rxRate)
                    color: root.color
                    font.family: "Rubik"
                    font.pointSize: 12
                }
            }

            Row {
                spacing: 4

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "arrow_upward"
                    color: root.accent
                    font.family: "Material Symbols Rounded"
                    font.pointSize: 14
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    renderType: Text.NativeRendering
                    text: root.formatRate(root.txRate)
                    color: root.color
                    font.family: "Rubik"
                    font.pointSize: 12
                }
            }
        }
    }
}

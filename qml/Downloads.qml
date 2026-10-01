// Downloads: a drawer from the right, newest first, with progress; click a
// finished one to open it, or its folder.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtWebEngine

Drawer {
    id: root
    property var model
    edge: Qt.RightEdge
    width: 420
    height: parent ? parent.height : 600
    background: Rectangle { color: Theme.panel; Rectangle { width: 1; height: parent.height; color: Theme.line } }
    ColumnLayout {
        anchors.fill: parent; anchors.margins: 16; spacing: 10
        Text { text: "Downloads"; color: Theme.text; font.family: Theme.sans; font.pixelSize: 16; font.weight: Font.DemiBold }
        Text { visible: root.model.count === 0; text: "Nothing downloaded yet."; color: Theme.dim; font.family: Theme.sans; font.pixelSize: 13 }
        ListView {
            Layout.fillWidth: true; Layout.fillHeight: true
            model: root.model; spacing: 8; clip: true
            delegate: Rectangle {
                id: d
                required property var item
                required property string name
                required property string dir
                readonly property bool done: item && item.state === WebEngineDownloadRequest.DownloadCompleted
                readonly property bool failed: item && (item.state === WebEngineDownloadRequest.DownloadInterrupted || item.state === WebEngineDownloadRequest.DownloadCancelled)
                width: ListView.view.width; height: 58; radius: 10
                color: Theme.raised
                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 10; spacing: 4
                    Text { Layout.fillWidth: true; text: d.name; elide: Text.ElideMiddle; color: Theme.text; font.family: Theme.sans; font.pixelSize: 13 }
                    Rectangle {
                        Layout.fillWidth: true; height: 3; radius: 1.5; color: Theme.line; visible: !d.done && !d.failed
                        Rectangle { height: parent.height; radius: 1.5; color: Theme.mint
                                    width: d.item && d.item.totalBytes > 0 ? parent.width * d.item.receivedBytes / d.item.totalBytes : 0 }
                    }
                    Text {
                        text: d.failed ? "failed" : d.done ? "done · click to open · right-click for the folder"
                              : (d.item ? Math.round(d.item.receivedBytes / 1048576) + " / " + Math.round(Math.max(0, d.item.totalBytes) / 1048576) + " MiB" : "")
                        color: d.failed ? Theme.danger : Theme.dim; font.family: Theme.sans; font.pixelSize: 11
                    }
                }
                MouseArea {
                    anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: (m) => { if (d.done) Qt.openUrlExternally("file://" + (m.button === Qt.RightButton ? d.dir : d.dir + "/" + d.name)) }
                }
            }
        }
    }
}

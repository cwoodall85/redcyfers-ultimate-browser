// This workspace's bookmarks, in a row under the address bar. Click opens,
// middle-click opens in a new tab, right-click removes.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root
    property string workspace: ""
    property var items: []
    signal open(string url, bool newTab)
    function reload() { items = Library.bookmarks(workspace) }
    onWorkspaceChanged: reload()
    Component.onCompleted: reload()
    Connections { target: Library; function onBookmarksChanged(ws) { if (ws === root.workspace) root.reload() } }
    visible: items.length > 0
    height: visible ? 32 : 0
    color: Theme.panel
    ListView {
        anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8
        orientation: ListView.Horizontal; spacing: 2; clip: true
        model: root.items
        delegate: Rectangle {
            required property var modelData
            height: 26; anchors.verticalCenter: parent ? parent.verticalCenter : undefined
            width: Math.min(200, row.implicitWidth + 16); radius: 6
            color: m.containsMouse ? Theme.raised : "transparent"
            Row {
                id: row; anchors.verticalCenter: parent.verticalCenter; x: 8; spacing: 6
                Image { width: 14; height: 14; anchors.verticalCenter: parent.verticalCenter
                        source: "image://favicon/" + modelData.url; sourceSize: Qt.size(28, 28) }
                Text { width: Math.min(implicitWidth, 160); elide: Text.ElideRight; text: modelData.title || modelData.url
                       color: Theme.dim; font.family: Theme.sans; font.pixelSize: 12 }
            }
            MouseArea {
                id: m; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                onClicked: (e) => {
                    if (e.button === Qt.RightButton) menu.popup()
                    else root.open(modelData.url, e.button === Qt.MiddleButton)
                }
            }
            ToolTip.visible: m.containsMouse; ToolTip.delay: 700; ToolTip.text: modelData.url
            Menu { id: menu; MenuItem { text: "Open in new tab"; onTriggered: root.open(modelData.url, true) }
                   MenuItem { text: "Remove bookmark"; onTriggered: Library.removeBookmark(modelData.id) } }
        }
    }
    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
}

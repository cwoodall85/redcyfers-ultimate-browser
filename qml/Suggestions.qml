// What the address bar suggests while you type: bookmarks (★) and history,
// best first. Up/Down move, Enter opens.
import QtQuick
import QtQuick.Controls

Popup {
    id: root
    property var items: []
    property int current: -1
    signal pick(string url)
    padding: 4
    background: Rectangle { color: Theme.raised; radius: 10; border.color: Theme.line }
    visible: items.length > 0 && opened
    implicitHeight: list.contentHeight + 8
    function move(d) { current = Math.max(-1, Math.min(items.length - 1, current + d)) }
    ListView {
        id: list
        anchors.fill: parent
        interactive: false
        model: root.items
        delegate: Rectangle {
            required property var modelData
            required property int index
            width: list.width; height: 34; radius: 6
            color: index === root.current || m.containsMouse ? Qt.rgba(0, 1, 0.66, 0.10) : "transparent"
            Row {
                anchors.verticalCenter: parent.verticalCenter; x: 10; spacing: 10
                Text { text: modelData.starred ? "★" : "↺"; color: modelData.starred ? Theme.mint : Theme.dim; font.pixelSize: 12 }
                Text { width: list.width * 0.45; elide: Text.ElideRight; text: modelData.title || modelData.url
                       color: Theme.text; font.family: Theme.sans; font.pixelSize: 13 }
                Text { width: list.width * 0.45; elide: Text.ElideMiddle; text: modelData.url
                       color: Theme.dim; font.family: Theme.sans; font.pixelSize: 12 }
            }
            MouseArea { id: m; anchors.fill: parent; hoverEnabled: true; onClicked: root.pick(modelData.url) }
        }
    }
}

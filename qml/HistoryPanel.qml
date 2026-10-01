// History for this workspace (Ctrl+H): newest first, searchable.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Drawer {
    id: root
    property string workspace: ""
    property var items: []
    signal open(string url)
    edge: Qt.RightEdge
    width: 520; height: parent ? parent.height : 600
    onOpened: { search.text = ""; reload(); search.forceActiveFocus() }
    function reload() { items = Library.history(workspace, search.text, 400) }
    background: Rectangle { color: Theme.panel; Rectangle { width: 1; height: parent.height; color: Theme.line } }
    ColumnLayout {
        anchors.fill: parent; anchors.margins: 16; spacing: 10
        RowLayout {
            Text { text: "History · " + root.workspace; color: Theme.text; font.family: Theme.sans; font.pixelSize: 16; font.weight: Font.DemiBold; Layout.fillWidth: true }
            Button { text: "Clear all"; flat: true; onClicked: clearConfirm.open() }
        }
        TextField { id: search; Layout.fillWidth: true; placeholderText: "Search history"; onTextChanged: root.reload() }
        ListView {
            Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: 2
            model: root.items
            ScrollBar.vertical: ScrollBar {}
            delegate: Rectangle {
                required property var modelData
                width: ListView.view.width; height: 44; radius: 8
                color: m.containsMouse ? Theme.raised : "transparent"
                ColumnLayout {
                    anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; spacing: 0
                    Text { Layout.fillWidth: true; elide: Text.ElideRight; text: modelData.title || modelData.url; color: Theme.text; font.family: Theme.sans; font.pixelSize: 13 }
                    Text { Layout.fillWidth: true; elide: Text.ElideMiddle; text: modelData.when + "  ·  " + modelData.url; color: Theme.dim; font.family: Theme.sans; font.pixelSize: 11 }
                }
                MouseArea {
                    id: m; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: (e) => { if (e.button === Qt.RightButton) { Library.forget(root.workspace, modelData.url); root.reload() } else { root.open(modelData.url); root.close() } }
                }
            }
        }
        Text { text: "Right-click an entry to forget it."; color: Theme.dim; font.family: Theme.sans; font.pixelSize: 11 }
    }
    Dialog {
        id: clearConfirm; anchors.centerIn: parent; modal: true
        title: "Clear all history in " + root.workspace + "?"
        standardButtons: Dialog.Yes | Dialog.No
        onAccepted: { Library.clearHistory(root.workspace); root.reload() }
    }
}

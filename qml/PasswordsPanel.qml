// Saved logins for this workspace: site and username only. A password is
// fetched from the keyring only when you copy it or the browser fills it.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Drawer {
    id: root
    property string workspace: ""
    property var items: []
    property string filter: ""
    property int copyRequest: -1
    edge: Qt.RightEdge
    width: 520; height: parent ? parent.height : 600
    onOpened: { search.text = ""; reload() }
    function reload() {
        items = Library.logins(workspace).filter(l => !filter || (l.origin + " " + l.username).toLowerCase().indexOf(filter.toLowerCase()) >= 0)
    }
    Connections { target: Library; function onLoginsChanged(ws) { if (ws === root.workspace && root.opened) root.reload() } }
    Connections {
        target: Library
        function onPasswordReady(req, pw, err) {
            if (req !== root.copyRequest) return
            root.copyRequest = -1
            if (err) { status.text = "Couldn't read the keyring: " + err; return }
            clip.text = pw; clip.selectAll(); clip.copy(); clip.text = ""
            status.text = "Password copied. It stays on the clipboard until you copy something else."
        }
    }
    TextEdit { id: clip; visible: false }
    background: Rectangle { color: Theme.panel; Rectangle { width: 1; height: parent.height; color: Theme.line } }
    ColumnLayout {
        anchors.fill: parent; anchors.margins: 16; spacing: 10
        Text { text: "Passwords · " + root.workspace + "  (" + root.items.length + ")"; color: Theme.text; font.family: Theme.sans; font.pixelSize: 16; font.weight: Font.DemiBold }
        Text { Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.dim; font.family: Theme.sans; font.pixelSize: 11
               text: "Kept in your desktop keyring (KWallet), not in the browser's files. Filled in automatically on each site's login page." }
        TextField { id: search; Layout.fillWidth: true; placeholderText: "Search sites and usernames"; onTextChanged: { root.filter = text; root.reload() } }
        ListView {
            Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: 2
            model: root.items
            ScrollBar.vertical: ScrollBar {}
            delegate: Rectangle {
                required property var modelData
                width: ListView.view.width; height: 44; radius: 8
                color: m.containsMouse ? Theme.raised : "transparent"
                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 6; spacing: 8
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 0
                        Text { Layout.fillWidth: true; elide: Text.ElideRight; text: modelData.origin.replace(/^https?:\/\//, ""); color: Theme.text; font.family: Theme.sans; font.pixelSize: 13 }
                        Text { Layout.fillWidth: true; elide: Text.ElideRight; text: modelData.username || "(no username)"; color: Theme.dim; font.family: Theme.sans; font.pixelSize: 11 }
                    }
                    Button { text: "Copy password"; flat: true; onClicked: root.copyRequest = Library.fetchPassword(modelData.id) }
                    Button { text: "✕"; flat: true; onClicked: { Library.removeLogin(modelData.id) } }
                }
                MouseArea { id: m; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
            }
        }
        Text { id: status; Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.mint; font.family: Theme.sans; font.pixelSize: 11 }
    }
}

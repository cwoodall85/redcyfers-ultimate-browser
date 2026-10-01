// Import from Chrome: read, review the workspace split site by site, import.
// Chrome itself is left exactly as it is. Passwords come from the CSV that
// Chrome exports; this screen only ever shows sites and usernames, and the
// CSV is overwritten and deleted once the passwords are in the keyring.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Popup {
    id: root
    property var result: null       // scan()
    property var done: null         // apply()
    property var overrides: ({})
    property string csv: ""
    property string filter: ""
    readonly property var wss: Importer.workspaces()
    anchors.centerIn: Overlay.overlay
    width: Math.min(980, parent ? parent.width - 80 : 900)
    height: Math.min(760, parent ? parent.height - 80 : 700)
    modal: true; focus: true
    closePolicy: Popup.CloseOnEscape
    background: Rectangle { color: Theme.panel; radius: 14; border.color: Theme.line }
    onOpened: { result = null; done = null; overrides = ({}); csv = Importer.findExport() }
    onClosed: if (!done) Importer.cancel()

    function wsOf(site) { return overrides[site.host] || site.ws }
    function totals() {
        const t = {}
        for (const w of wss) t[w] = { bookmarks: 0, pages: 0, logins: 0 }
        if (!result) return t
        for (const s of result.sites) { const w = wsOf(s); if (!t[w]) t[w] = { bookmarks: 0, pages: 0, logins: 0 }
            t[w].bookmarks += s.bookmarks; t[w].pages += s.pages; t[w].logins += s.logins }
        return t
    }

    ColumnLayout {
        anchors.fill: parent; anchors.margins: 20; spacing: 12
        Text { text: "Import from Chrome"; color: Theme.text; font.family: Theme.sans; font.pixelSize: 18; font.weight: Font.DemiBold }

        // step 1: what to read
        ColumnLayout {
            visible: !root.result && !root.done; spacing: 10; Layout.fillWidth: true
            Text {
                Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.dim; font.family: Theme.sans; font.pixelSize: 13
                text: "Bookmarks and history are read from Chrome's profile (" + Importer.profileDir + "); Chrome is not changed.\n"
                    + "Passwords come from Chrome's export file. After import they live in your desktop keyring and the file is erased."
            }
            RowLayout {
                Layout.fillWidth: true
                Text { text: "Passwords file:"; color: Theme.text; font.family: Theme.sans; font.pixelSize: 13 }
                TextField { id: csvField; Layout.fillWidth: true; text: root.csv; placeholderText: "none (skip passwords)"; onTextChanged: root.csv = text }
            }
            Button { text: "Read Chrome"; highlighted: true; onClicked: root.result = Importer.scan(root.csv) }
        }

        // step 2: review
        ColumnLayout {
            visible: !!root.result && !root.done; spacing: 10; Layout.fillWidth: true; Layout.fillHeight: true
            RowLayout {
                spacing: 10; Layout.fillWidth: true
                Repeater {
                    model: root.wss
                    Rectangle {
                        required property string modelData
                        readonly property var t: root.totals()[modelData] || { bookmarks: 0, pages: 0, logins: 0 }
                        Layout.fillWidth: true; height: 64; radius: 10; color: Theme.raised
                        border.width: 1; border.color: Theme.wsColor(modelData)
                        Column {
                            anchors.centerIn: parent; spacing: 2
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: parent.parent.modelData; color: Theme.wsColor(parent.parent.modelData); font.family: Theme.sans; font.pixelSize: 14; font.weight: Font.DemiBold }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; color: Theme.dim; font.family: Theme.sans; font.pixelSize: 11
                                   text: parent.parent.t.bookmarks + " bookmarks · " + parent.parent.t.logins + " passwords · " + parent.parent.t.pages + " pages" }
                        }
                    }
                }
            }
            Text { visible: root.result && root.result.errors.length > 0; color: Theme.danger; font.family: Theme.sans; font.pixelSize: 12
                   text: root.result ? root.result.errors.join(" · ") : "" }
            RowLayout {
                Layout.fillWidth: true
                Text { Layout.fillWidth: true; color: Theme.dim; font.family: Theme.sans; font.pixelSize: 12
                       text: "Each site is sorted by your rules. Change any that are wrong; it moves its bookmarks, passwords and history together." }
                TextField { Layout.preferredWidth: 240; placeholderText: "Find a site"; onTextChanged: root.filter = text }
            }
            ListView {
                id: sites
                Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: 2
                model: root.result ? root.result.sites.filter(s => !root.filter || s.host.indexOf(root.filter) >= 0) : []
                ScrollBar.vertical: ScrollBar {}
                delegate: Rectangle {
                    required property var modelData
                    width: sites.width; height: 36; radius: 6; color: m.containsMouse ? Theme.raised : "transparent"
                    MouseArea { id: m; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 6; spacing: 10
                        Text { Layout.fillWidth: true; elide: Text.ElideRight; text: modelData.host || "(no host)"; color: Theme.text; font.family: Theme.sans; font.pixelSize: 13 }
                        Text { Layout.preferredWidth: 260; horizontalAlignment: Text.AlignRight; color: Theme.dim; font.family: Theme.sans; font.pixelSize: 11
                               text: [modelData.bookmarks ? modelData.bookmarks + " ★" : "", modelData.logins ? modelData.logins + " 🔑" : "", modelData.pages ? modelData.pages + " pages" : ""].filter(x => x).join("   ") }
                        ComboBox {
                            Layout.preferredWidth: 150
                            model: root.wss
                            currentIndex: root.wss.indexOf(root.wsOf(modelData))
                            onActivated: (i) => { const o = root.overrides; o[modelData.host] = root.wss[i]; root.overrides = o }
                        }
                    }
                }
            }
            RowLayout {
                Layout.alignment: Qt.AlignRight
                Button { text: "Cancel"; onClicked: root.close() }
                Button { text: "Import"; highlighted: true; onClicked: root.done = Importer.apply(root.overrides) }
            }
        }

        // step 3: done
        ColumnLayout {
            visible: !!root.done; spacing: 10
            Text { color: Theme.mint; font.family: Theme.sans; font.pixelSize: 15
                   text: root.done ? "Imported " + root.done.bookmarks + " bookmarks, " + root.done.logins + " passwords and " + root.done.pages + " history pages." : "" }
            Text { color: root.done && root.done.csv && !root.done.csvRemoved ? Theme.danger : Theme.dim; font.family: Theme.sans; font.pixelSize: 13
                   text: !root.done || !root.done.csv ? "" : root.done.csvRemoved ? "The passwords file was erased and deleted." : "Couldn't delete " + root.done.csv + ": delete it yourself." }
            Button { text: "Close"; highlighted: true; onClicked: root.close() }
        }
    }
}

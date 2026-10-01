// A bar over the page for logins: "Fill as …" when several are saved for
// the site, or "Save password for … ?" after you sign in somewhere new.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root
    property string mode: ""            // "choose" | "save"
    property var choices: []            // for choose: [{id, username}]
    property string origin: ""
    property string username: ""
    property string password: ""        // for save, held only until answered
    property bool update: false         // the saved password changed
    signal fill(int loginId)
    signal save()
    function hide() { mode = ""; password = "" }
    visible: mode !== ""
    height: visible ? 44 : 0
    color: Theme.raised
    z: 10
    RowLayout {
        anchors.fill: parent; anchors.leftMargin: 16; anchors.rightMargin: 12; spacing: 8
        Text { text: "🔑"; font.pixelSize: 14 }
        Text {
            Layout.fillWidth: true; elide: Text.ElideRight
            color: Theme.text; font.family: Theme.sans; font.pixelSize: 13
            text: root.mode === "save" ? (root.update ? "Update the saved password for " : "Save the password for ") + (root.username || "this login") + " on " + root.origin.replace(/^https?:\/\//, "") + "?"
                                       : "Sign in to " + root.origin.replace(/^https?:\/\//, "") + " as:"
        }
        Repeater {
            model: root.mode === "choose" ? root.choices.slice(0, 4) : []
            Button { required property var modelData; text: modelData.username || "(no username)"; onClicked: { root.fill(modelData.id); root.hide() } }
        }
        Button { visible: root.mode === "save"; text: root.update ? "Update" : "Save"; highlighted: true; onClicked: { root.save(); root.hide() } }
        Button { text: root.mode === "save" ? "Not now" : "✕"; flat: true; onClicked: root.hide() }
    }
}

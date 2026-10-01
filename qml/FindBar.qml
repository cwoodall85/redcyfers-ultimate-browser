// Find in page (Ctrl+F): Enter / Shift+Enter for next / previous, Esc closes.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root
    property var view: null
    property int matches: 0
    property int at: 0
    function open() { visible = true; field.forceActiveFocus(); field.selectAll() }
    function close() { if (view) view.findText(""); visible = false; if (view) view.forceActiveFocus() }
    function find(back) {
        if (!view) return
        view.findText(field.text, back ? WebEngineView.FindBackward : 0)
    }
    visible: false
    height: visible ? 40 : 0
    color: Theme.panel
    Connections {
        target: root.view
        ignoreUnknownSignals: true
        function onFindTextFinished(result) { root.matches = result.numberOfMatches; root.at = result.activeMatch }
    }
    RowLayout {
        anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12; spacing: 8
        TextField {
            id: field
            Layout.preferredWidth: 320
            placeholderText: "Find in page"
            onTextChanged: root.find(false)
            Keys.onReturnPressed: (e) => root.find(e.modifiers & Qt.ShiftModifier)
            Keys.onEscapePressed: root.close()
        }
        Text {
            text: field.text ? (root.matches ? root.at + " of " + root.matches : "no matches") : ""
            color: root.matches || !field.text ? Theme.dim : Theme.danger
            font.family: Theme.sans; font.pixelSize: 12
        }
        Item { Layout.fillWidth: true }
        Button { text: "✕"; flat: true; onClicked: root.close() }
    }
    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
}

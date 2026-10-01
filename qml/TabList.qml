// The left column: workspace switcher on top (each workspace its own colour),
// then this workspace's tabs, top to bottom, and "+ New tab".
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root
    property var model
    property var workspaces: []
    property string workspace: ""
    property int currentTab: -1
    signal activate(int tid)
    signal close(int tid)
    signal newTab()
    signal switchWorkspace(string ws)
    signal addWorkspace(string name)
    color: Theme.panel

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // workspaces: chips in a wrapping row
        Flow {
            Layout.fillWidth: true
            Layout.margins: 10
            spacing: 6
            Repeater {
                model: root.workspaces
                Rectangle {
                    required property string modelData
                    required property int index
                    readonly property bool on: modelData === root.workspace
                    readonly property color c: Theme.wsColor(modelData)
                    width: wsText.implicitWidth + 22; height: 26; radius: 13
                    color: on ? Qt.rgba(c.r, c.g, c.b, 0.18) : (wsMouse.containsMouse ? Theme.raised : "transparent")
                    border.width: 1; border.color: on ? c : Theme.line
                    Text {
                        id: wsText; anchors.centerIn: parent
                        text: parent.modelData
                        color: parent.on ? parent.c : Theme.dim
                        font.family: Theme.sans; font.pixelSize: 12; font.weight: parent.on ? Font.DemiBold : Font.Normal
                    }
                    MouseArea { id: wsMouse; anchors.fill: parent; hoverEnabled: true; onClicked: root.switchWorkspace(parent.modelData) }
                    ToolTip.visible: wsMouse.containsMouse; ToolTip.delay: 600
                    ToolTip.text: "Alt+" + (index + 1) + " · own logins and cookies"
                }
            }
            Rectangle {
                width: 26; height: 26; radius: 13; color: addMouse.containsMouse ? Theme.raised : "transparent"
                border.width: 1; border.color: Theme.line
                Text { anchors.centerIn: parent; text: "+"; color: Theme.dim; font.pixelSize: 15 }
                MouseArea { id: addMouse; anchors.fill: parent; hoverEnabled: true; onClicked: newWs.open() }
            }
        }
        Rectangle { Layout.fillWidth: true; height: 2; color: Theme.wsColor(root.workspace); opacity: 0.6 }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: 6
            clip: true
            model: root.model
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}
            delegate: Item {
                id: row
                required property int tid
                required property string ws
                required property string title
                required property string url
                required property string icon
                required property bool loading
                readonly property bool mine: ws === root.workspace
                readonly property bool on: tid === root.currentTab
                width: list.width
                height: mine ? 34 : 0
                visible: mine
                Rectangle {
                    anchors.fill: parent; anchors.leftMargin: 6; anchors.rightMargin: 6
                    radius: 8
                    color: row.on ? Theme.raised : (rowMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.03) : "transparent")
                    Rectangle {   // the current tab's rail, in the workspace colour
                        visible: row.on; width: 3; radius: 1.5
                        anchors { left: parent.left; top: parent.top; bottom: parent.bottom; margins: 7 }
                        color: Theme.wsColor(row.ws)
                    }
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 6; spacing: 8
                        Item {
                            Layout.preferredWidth: 16; Layout.preferredHeight: 16
                            Image { anchors.fill: parent; source: row.icon; visible: !row.loading && row.icon !== ""; sourceSize: Qt.size(32, 32) }
                            BusyIndicator { anchors.fill: parent; running: row.loading; visible: row.loading; padding: 0 }
                            Rectangle { anchors.fill: parent; radius: 4; visible: !row.loading && row.icon === ""; color: Theme.line }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: row.title || row.url
                            elide: Text.ElideRight
                            color: row.on ? Theme.text : Theme.dim
                            font.family: Theme.sans; font.pixelSize: 13
                        }
                        Rectangle {
                            Layout.preferredWidth: 20; Layout.preferredHeight: 20; radius: 5
                            visible: rowMouse.containsMouse || row.on
                            color: closeMouse.containsMouse ? Theme.line : "transparent"
                            Text { anchors.centerIn: parent; text: "✕"; color: Theme.dim; font.pixelSize: 11 }
                            MouseArea { id: closeMouse; anchors.fill: parent; hoverEnabled: true; onClicked: root.close(row.tid) }
                        }
                    }
                    MouseArea {
                        id: rowMouse; anchors.fill: parent; hoverEnabled: true; z: -1
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                        onClicked: (m) => m.button === Qt.MiddleButton ? root.close(row.tid) : root.activate(row.tid)
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true; Layout.margins: 8; height: 34; radius: 8
            color: newMouse.containsMouse ? Theme.raised : "transparent"
            Text { anchors.verticalCenter: parent.verticalCenter; x: 14; text: "+  New tab"; color: Theme.dim; font.family: Theme.sans; font.pixelSize: 13 }
            Text { anchors.verticalCenter: parent.verticalCenter; anchors.right: parent.right; anchors.rightMargin: 10; text: "Ctrl+T"; color: Theme.line; font.family: Theme.mono; font.pixelSize: 11 }
            MouseArea { id: newMouse; anchors.fill: parent; hoverEnabled: true; onClicked: root.newTab() }
        }
    }

    Popup {
        id: newWs
        x: 10; y: 44; width: root.width - 20
        modal: true; focus: true
        background: Rectangle { color: Theme.raised; radius: 10; border.color: Theme.line }
        onOpened: nameField.forceActiveFocus()
        ColumnLayout {
            anchors.fill: parent; spacing: 8
            Text { text: "New workspace (its own logins and cookies)"; color: Theme.text; font.family: Theme.sans; font.pixelSize: 12; wrapMode: Text.Wrap; Layout.fillWidth: true }
            TextField {
                id: nameField; Layout.fillWidth: true; placeholderText: "Name"
                onAccepted: { root.addWorkspace(text.trim()); text = ""; newWs.close() }
            }
        }
    }
}

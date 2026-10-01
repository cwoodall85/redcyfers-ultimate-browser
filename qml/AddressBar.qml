// Back / forward / reload, the address (the host stands out; the rest is
// dim until you edit), the tracker shield with its count, send-to-phone,
// downloads and the Claude button.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root
    property var view: null
    property color wsColor: Theme.mint
    property int blockedCount: 0
    property bool claudeOpen: false
    signal go(string text)
    signal toggleClaude()
    signal sendToPhone()
    signal showDownloads()
    signal showMenu()
    property string workspace: ""
    // bookmark state of the current page
    property int bookmarkId: 0
    function refreshBookmark() { bookmarkId = view ? Library.bookmarkId(workspace, view.url.toString()) : 0 }
    function toggleBookmark() {
        if (!view) return
        if (bookmarkId) Library.removeBookmark(bookmarkId)
        else Library.addBookmark(workspace, view.title || view.url.toString(), view.url.toString())
        refreshBookmark()
    }
    onViewChanged: refreshBookmark()
    onWorkspaceChanged: refreshBookmark()
    Connections { target: root.view; ignoreUnknownSignals: true; function onUrlChanged() { root.refreshBookmark() } }
    Connections { target: Library; function onBookmarksChanged(ws) { root.refreshBookmark() } }
    function focusAddress() { field.forceActiveFocus(); field.selectAll() }
    height: 48
    color: Theme.panel

    component IconBtn: Rectangle {
        property string glyph
        property string tip
        property bool active: false
        property color activeColor: Theme.mint
        signal clicked()
        width: 32; height: 32; radius: 8
        color: active ? Qt.rgba(activeColor.r, activeColor.g, activeColor.b, 0.16) : (m.containsMouse ? Theme.raised : "transparent")
        opacity: enabled ? 1 : 0.35
        Text { anchors.centerIn: parent; text: parent.glyph; color: parent.active ? parent.activeColor : Theme.text; font.pixelSize: 15; font.family: Theme.sans }
        MouseArea { id: m; anchors.fill: parent; hoverEnabled: true; onClicked: parent.clicked() }
        ToolTip.visible: m.containsMouse && tip !== ""; ToolTip.delay: 500; ToolTip.text: tip
    }

    RowLayout {
        anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8; spacing: 4
        IconBtn { glyph: "←"; tip: "Back (Alt+Left)"; enabled: root.view && root.view.canGoBack; onClicked: root.view.goBack() }
        IconBtn { glyph: "→"; tip: "Forward (Alt+Right)"; enabled: root.view && root.view.canGoForward; onClicked: root.view.goForward() }
        IconBtn {
            glyph: root.view && root.view.loading ? "✕" : "↻"; tip: "Reload (Ctrl+R)"
            onClicked: root.view && (root.view.loading ? root.view.stop() : root.view.reload())
        }

        Rectangle {
            Layout.fillWidth: true; Layout.leftMargin: 6; Layout.rightMargin: 6
            height: 34; radius: 10
            color: Theme.raised
            border.width: 1; border.color: field.activeFocus ? root.wsColor : Theme.line
            // page-load progress, as a thin line along the bottom
            Rectangle {
                anchors { left: parent.left; bottom: parent.bottom; margins: 1 }
                height: 2; radius: 1
                width: root.view && root.view.loading ? (parent.width - 2) * root.view.loadProgress / 100 : 0
                color: root.wsColor
            }
            RowLayout {
                anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 6; spacing: 6
                Text {   // padlock / warning
                    readonly property string u: root.view ? root.view.url.toString() : ""
                    text: u.startsWith("https://") ? "🔒" : (u.startsWith("http://") ? "⚠" : "")
                    color: u.startsWith("http://") ? Theme.danger : Theme.dim
                    font.pixelSize: 12
                }
                TextField {
                    id: field
                    Layout.fillWidth: true
                    background: null
                    color: Theme.text
                    selectionColor: Qt.rgba(root.wsColor.r, root.wsColor.g, root.wsColor.b, 0.35)
                    font.family: Theme.sans; font.pixelSize: 14
                    placeholderText: "Search or type an address"
                    placeholderTextColor: Theme.dim
                    text: activeFocus ? text : (root.view ? root.view.url.toString() : "")
                    onAccepted: {
                        const pick = suggestions.current >= 0 ? suggestions.items[suggestions.current].url : text
                        suggestions.close(); root.go(pick)
                    }
                    Keys.onEscapePressed: {
                        if (suggestions.opened) { suggestions.close(); return }
                        text = root.view ? root.view.url.toString() : ""; if (root.view) root.view.forceActiveFocus()
                    }
                    Keys.onDownPressed: suggestions.move(1)
                    Keys.onUpPressed: suggestions.move(-1)
                    onTextEdited: {
                        suggestions.items = Library.suggest(root.workspace, text, 8)
                        suggestions.current = -1
                        if (suggestions.items.length) suggestions.open(); else suggestions.close()
                    }
                    onActiveFocusChanged: if (!activeFocus) suggestions.close()
                    Suggestions {
                        id: suggestions
                        y: parent.height + 8; x: -30
                        width: field.width + 60
                        onPick: (url) => { close(); root.go(url) }
                    }
                }
                // tracker shield: how many requests were blocked on this site
                Rectangle {
                    height: 22; radius: 11
                    width: shieldText.implicitWidth + 16
                    color: Blocker.enabled ? Qt.rgba(0, 1, 0.66, 0.10) : Theme.line
                    Text {
                        id: shieldText; anchors.centerIn: parent
                        text: "🛡 " + (Blocker.enabled ? root.blockedCount : "off")
                        color: Blocker.enabled ? Theme.mint : Theme.dim
                        font.family: Theme.mono; font.pixelSize: 11
                    }
                    MouseArea { anchors.fill: parent; hoverEnabled: true; id: shieldMouse; onClicked: shieldMenu.open() }
                    ToolTip.visible: shieldMouse.containsMouse; ToolTip.delay: 400
                    ToolTip.text: root.blockedCount + " trackers and ads blocked on this site (" + Blocker.listed + " hosts listed)"
                    Menu {
                        id: shieldMenu
                        readonly property string host: { try { return root.view ? new URL(root.view.url.toString()).hostname : "" } catch (e) { return "" } }
                        MenuItem {
                            text: Blocker.siteAllowed(shieldMenu.host) ? "Block trackers on " + shieldMenu.host : "Allow everything on " + shieldMenu.host
                            onTriggered: { Blocker.allowSite(shieldMenu.host, !Blocker.siteAllowed(shieldMenu.host)); root.view.reload() }
                        }
                        MenuItem {
                            text: Blocker.enabled ? "Turn blocking off everywhere" : "Turn blocking on"
                            onTriggered: { Blocker.enabled = !Blocker.enabled; root.view.reload() }
                        }
                    }
                }
            }
        }

        IconBtn { glyph: root.bookmarkId ? "★" : "☆"; tip: root.bookmarkId ? "Remove bookmark (Ctrl+D)" : "Bookmark this page (Ctrl+D)"
                  active: root.bookmarkId > 0; activeColor: root.wsColor; onClicked: root.toggleBookmark() }
        IconBtn { glyph: "📱"; tip: "Send this page to your phone (Ctrl+Shift+S)"; onClicked: root.sendToPhone() }
        IconBtn { glyph: "⤓"; tip: "Downloads (Ctrl+Shift+Y)"; onClicked: root.showDownloads() }
        IconBtn { glyph: "✦"; tip: "Claude (Ctrl+J)"; active: root.claudeOpen; activeColor: Theme.coral; onClicked: root.toggleClaude() }
        IconBtn { glyph: "⋯"; tip: "History, passwords, import from Chrome"; onClicked: root.showMenu() }
    }
    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
}

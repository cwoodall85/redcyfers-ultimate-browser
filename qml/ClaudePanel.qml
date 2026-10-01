// Claude, beside the page (Ctrl+J). It is the Claude bar's own backend
// (ultimate-claude-bar): the same conversation, the same Allow prompts
// (here, in the bar's pop-up and in the Chat thread on the phone), the
// same history and mirror to Chat. What this adds is the page: each
// question carries the tab you're on, and Claude's browser tools can read
// it and act in it.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root
    property string pageTitle: ""
    property string pageUrl: ""
    property int tab: -1
    property string workspace: ""
    property var run: ({})
    property var history: []
    readonly property bool busy: run.status === "thinking" || run.status === "listening"
    readonly property var pending: run.pending || null
    function focusInput() { input.forceActiveFocus() }
    color: Theme.panel

    // ---- talking to the backend -------------------------------------------
    function bar(tag, args) { Proc.run(tag, ["ultimate-claude-bar"].concat(args), 15000) }
    function ask(text) {
        text = text.trim()
        if (!text) return
        const ctx = root.pageUrl ? "\n\n[From Ultimate Browser: Chris is looking at \"" + root.pageTitle + "\" " + root.pageUrl
                  + " (tab " + root.tab + ", workspace " + root.workspace + "). The browser_* tools read and act on its tabs.]" : ""
        bar("ask", ["ask", "--", text + ctx])
        run = { status: "thinking", prompt: text, steps: [] }
        input.text = ""
    }
    function shown(p) { return String(p || "").split("\n\n[From Ultimate Browser:")[0] }
    Connections {
        target: Proc
        function onFinished(tag, code, out, err) {
            try {
                if (tag === "state") root.run = JSON.parse(out || "{}")
                else if (tag === "history") root.history = JSON.parse(out || "[]")
                else if (tag === "mode") root.mode = out.trim()
            } catch (e) {}
        }
    }
    property string mode: "ask"
    Timer {
        interval: root.busy ? 500 : 2000; running: root.visible; repeat: true; triggeredOnStart: true
        onTriggered: root.bar("state", ["state"])
    }
    onVisibleChanged: if (visible) { bar("history", ["history", "20"]); bar("mode", ["mode"]) }
    property string lastStatus: ""
    onRunChanged: {
        if (run.mode) mode = run.mode
        if (lastStatus === "thinking" && run.status !== "thinking") bar("history", ["history", "20"])
        lastStatus = run.status || ""
        Qt.callLater(() => convo.positionViewAtEnd())
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // header
        RowLayout {
            Layout.fillWidth: true; Layout.margins: 12; spacing: 8
            Rectangle { width: 8; height: 8; radius: 4; color: Theme.coral; opacity: root.busy ? (blink.on ? 1 : 0.3) : 0.9
                        Timer { id: blink; property bool on: true; interval: 600; repeat: true; running: root.busy; onTriggered: on = !on } }
            Text { text: "Claude"; color: Theme.text; font.family: Theme.sans; font.pixelSize: 15; font.weight: Font.DemiBold }
            Item { Layout.fillWidth: true }
            // Ask (read-only) or Assistant (acts, asking first) -- the bar's mode
            Rectangle {
                height: 24; width: modeText.implicitWidth + 18; radius: 12
                color: root.mode === "assistant" ? Qt.rgba(1, 0.56, 0.42, 0.16) : Theme.raised
                border.width: 1; border.color: root.mode === "assistant" ? Theme.coral : Theme.line
                Text { id: modeText; anchors.centerIn: parent; text: root.mode === "assistant" ? "Assistant: can act" : "Ask: read-only"
                       color: root.mode === "assistant" ? Theme.coral : Theme.dim; font.family: Theme.sans; font.pixelSize: 11 }
                MouseArea { anchors.fill: parent; onClicked: { root.mode = root.mode === "assistant" ? "ask" : "assistant"; root.bar("mode", ["mode", root.mode]) } }
            }
        }
        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.coral; opacity: 0.4 }

        // conversation: earlier answers, then the current run
        ListView {
            id: convo
            Layout.fillWidth: true; Layout.fillHeight: true
            clip: true; spacing: 14
            topMargin: 12; bottomMargin: 12
            ScrollBar.vertical: ScrollBar {}
            model: {
                const items = root.history.slice(-10).map(h => ({ prompt: h.prompt, text: h.error ? "⚠ " + h.error : h.text, steps: [], live: false }))
                if (root.run.prompt && (!root.history.length || root.history[root.history.length - 1].id !== root.run.id))
                    items.push({ prompt: root.run.prompt, text: root.run.error ? "⚠ " + root.run.error : (root.run.text || ""),
                                 steps: (root.run.steps || []).map(s => s.name), live: root.busy })
                return items
            }
            delegate: ColumnLayout {
                required property var modelData
                width: convo.width - 24; x: 12; spacing: 6
                Rectangle {   // the question, as a bubble on the right
                    Layout.alignment: Qt.AlignRight
                    Layout.maximumWidth: parent.width * 0.85
                    implicitWidth: q.implicitWidth + 20; implicitHeight: q.implicitHeight + 14
                    radius: 12; color: Qt.rgba(1, 0.56, 0.42, 0.14)
                    Text { id: q; x: 10; y: 7; width: Math.min(implicitWidth, parent.Layout.maximumWidth - 20)
                           text: root.shown(modelData.prompt); wrapMode: Text.Wrap; color: "#ffd6c6"; font.family: Theme.sans; font.pixelSize: 13 }
                }
                Text {
                    visible: modelData.steps.length > 0
                    Layout.fillWidth: true
                    text: modelData.steps.slice(-4).map(s => "▸ " + s + "()").join("\n")
                    color: Theme.coral; opacity: 0.8; font.family: Theme.mono; font.pixelSize: 11
                }
                TextEdit {
                    Layout.fillWidth: true
                    readOnly: true; selectByMouse: true
                    wrapMode: TextEdit.Wrap; textFormat: TextEdit.MarkdownText
                    color: Theme.text; font.family: Theme.sans; font.pixelSize: 13
                    selectionColor: Qt.rgba(1, 0.56, 0.42, 0.4)
                    text: modelData.text || (modelData.live ? "_thinking…_" : "")
                    onLinkActivated: (link) => Qt.openUrlExternally(link)
                }
            }
        }

        // Claude's question, when it needs an OK
        Rectangle {
            Layout.fillWidth: true; Layout.margins: 10
            visible: !!root.pending
            implicitHeight: askCol.implicitHeight + 20
            radius: 10; color: Theme.raised; border.color: Theme.coral
            ColumnLayout {
                id: askCol; anchors.fill: parent; anchors.margins: 10; spacing: 6
                Text { Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.text; font.family: Theme.sans; font.pixelSize: 13; font.weight: Font.DemiBold
                       text: root.pending ? "Claude would like to: " + root.pending.title : "" }
                Text { Layout.fillWidth: true; wrapMode: Text.Wrap; maximumLineCount: 6; elide: Text.ElideRight
                       color: Theme.dim; font.family: Theme.mono; font.pixelSize: 11; text: root.pending ? root.pending.detail : "" }
                RowLayout {
                    Layout.alignment: Qt.AlignRight; spacing: 6
                    Button { text: "Deny"; onClicked: root.bar("answer", ["deny", root.pending.id]) }
                    Button { text: "Just this step"; visible: root.pending && !root.pending.risky; onClicked: root.bar("answer", ["allow-once", root.pending.id]) }
                    Button { text: "Allow"; highlighted: true; onClicked: root.bar("answer", ["allow", root.pending.id]) }
                }
            }
        }

        // quick asks about the page
        Flow {
            Layout.fillWidth: true; Layout.leftMargin: 10; Layout.rightMargin: 10; spacing: 6
            visible: !root.busy && root.pageUrl !== ""
            Repeater {
                model: ["Summarize this page", "What should I know here?", "Find the price / contact / hours", "Explain this simply"]
                Rectangle {
                    required property string modelData
                    width: chip.implicitWidth + 18; height: 26; radius: 13
                    color: chipMouse.containsMouse ? Theme.raised : "transparent"; border.color: Theme.line
                    Text { id: chip; anchors.centerIn: parent; text: parent.modelData; color: Theme.dim; font.family: Theme.sans; font.pixelSize: 11 }
                    MouseArea { id: chipMouse; anchors.fill: parent; hoverEnabled: true; onClicked: root.ask(parent.modelData) }
                }
            }
        }

        // input
        Rectangle {
            Layout.fillWidth: true; Layout.margins: 10
            implicitHeight: Math.min(160, input.implicitHeight + 20)
            radius: 12; color: Theme.raised; border.color: input.activeFocus ? Theme.coral : Theme.line
            ScrollView {
                anchors.fill: parent; anchors.margins: 6
                TextArea {
                    id: input
                    wrapMode: TextEdit.Wrap
                    background: null
                    color: Theme.text; font.family: Theme.sans; font.pixelSize: 13
                    placeholderText: root.pageUrl ? "Ask about this page, or tell Claude what to do…" : "Ask Claude…"
                    placeholderTextColor: Theme.dim
                    Keys.onReturnPressed: (e) => { if (e.modifiers & Qt.ShiftModifier) e.accepted = false; else root.ask(input.text) }
                    Keys.onEscapePressed: if (root.busy) root.bar("clear", ["clear"])
                }
            }
        }
        Text {
            Layout.leftMargin: 14; Layout.bottomMargin: 8
            text: root.busy ? "Esc stops · answers also go to Chat #claude" : "Enter to send · Shift+Enter for a new line · also in Chat #claude"
            color: Theme.dim; font.family: Theme.sans; font.pixelSize: 10
        }
    }
}

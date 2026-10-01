// Ultimate Browser's window.
//
//   [workspaces | vertical tabs] [address bar          ] [Claude]
//                                [page                  ] [panel ]
//
// Workspaces (Personal, plus any you add: Work, Projects ...) each have their own
// WebEngineProfile -- their own cookies, logins, cache and history -- and
// their own tabs. Every tab's WebEngineView stays alive (a Repeater over
// one tab model); only the current one is shown. The control socket's
// commands (Claude's browser tools) are answered here, since this file
// owns the tabs.
import QtCore
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtWebEngine
import QtWebChannel
import "Page.js" as Page

ApplicationWindow {
    id: win
    width: 1600; height: 1000
    visible: true
    title: (current ? (current.title || current.url) + " — " : "") + "Ultimate Browser"
    color: Theme.base

    // ---- state -----------------------------------------------------------
    property var workspaces: ["Personal"]
    property string workspace: "Personal"
    property int currentTab: -1               // tid
    property int nextTid: 1
    property var views: ({})                  // tid -> WebEngineView
    property var profiles: ({})               // workspace -> WebEngineProfile
    property var lastTabIn: ({})              // workspace -> tid
    readonly property var current: views[currentTab] || null
    property bool claudeOpen: false
    readonly property string home: "https://duckduckgo.com/"

    ListModel { id: tabs }                    // {tid, ws, url, title, icon, loading}
    ListModel { id: downloads }

    Settings {
        id: saved
        category: "session"
        property string workspacesJson: ""
        property string current: "Personal"
        property string tabsJson: ""
        property bool claudeOpen: false
    }

    // ---- profiles --------------------------------------------------------
    // Qt 6.9+: a disk-based profile is made from a prototype (storage name set
    // before the profile exists), then configured.
    Component {
        id: profileComp
        WebEngineProfilePrototype {}
    }
    function profileFor(ws) {
        if (!profiles[ws]) {
            const proto = profileComp.createObject(win, { storageName: "ws-" + ws.toLowerCase().replace(/[^a-z0-9]+/g, "-") })
            const p = proto.instance()
            p.persistentCookiesPolicy = WebEngineProfile.ForcePersistentCookies
            p.httpCacheType = WebEngineProfile.DiskHttpCache
            p.downloadRequested.connect((d) => win.startDownload(d))
            Blocker.attach(p)
            const m = profiles; m[ws] = p; profiles = m
        }
        return profiles[ws]
    }

    // ---- tabs ------------------------------------------------------------
    function openTab(url, ws, background) {
        ws = ws || workspace
        const tid = nextTid++
        tabs.append({ tid: tid, ws: ws, url: url || home, title: "", icon: "", loading: true })
        if (!background) { if (ws !== workspace) switchWorkspace(ws, tid); else currentTab = tid }
        saveSession()
        return tid
    }
    function indexOfTab(tid) {
        for (let i = 0; i < tabs.count; i++) if (tabs.get(i).tid === tid) return i
        return -1
    }
    function tabsIn(ws) {
        const out = []
        for (let i = 0; i < tabs.count; i++) if (tabs.get(i).ws === ws) out.push(tabs.get(i).tid)
        return out
    }
    function closeTab(tid) {
        const i = indexOfTab(tid)
        if (i < 0) return
        const ws = tabs.get(i).ws
        const mine = tabsIn(ws)
        const pos = mine.indexOf(tid)
        tabs.remove(i)
        const v = views; delete v[tid]; views = v
        if (tid === currentTab) {
            const left = tabsIn(ws)
            currentTab = left.length ? left[Math.min(pos, left.length - 1)] : openTab("", ws)
        }
        saveSession()
    }
    function cycleTab(step) {
        const mine = tabsIn(workspace)
        if (mine.length < 2) return
        currentTab = mine[(mine.indexOf(currentTab) + step + mine.length) % mine.length]
    }
    function switchWorkspace(ws, tid) {
        const m = lastTabIn; m[workspace] = currentTab; lastTabIn = m
        workspace = ws
        const mine = tabsIn(ws)
        currentTab = tid !== undefined ? tid : (mine.indexOf(lastTabIn[ws]) >= 0 ? lastTabIn[ws] : (mine.length ? mine[0] : openTab("", ws)))
        saveSession()
    }
    function setTab(tid, key, value) {
        const i = indexOfTab(tid)
        if (i >= 0 && tabs.get(i)[key] !== value) tabs.setProperty(i, key, value)
    }
    function navigate(text) {
        if (!current) return
        current.url = urlFor(text)
        current.forceActiveFocus()
    }
    // What was typed: an address, a host, or a search.
    function urlFor(text) {
        const t = text.trim()
        if (/^[a-z][a-z0-9+.-]*:/i.test(t) && !/^[^\s:]+:\d+$/.test(t) || t.startsWith("about:")) return t
        if (!/\s/.test(t) && (/^[\w-]+(\.[\w-]+)+(:\d+)?(\/.*)?$/.test(t) || /^localhost(:\d+)?/.test(t)
                               || /^\d{1,3}(\.\d{1,3}){3}(:\d+)?/.test(t)))
            return "https://" + t
        return "https://duckduckgo.com/?q=" + encodeURIComponent(t)
    }

    // ---- session ---------------------------------------------------------
    property bool restoring: true
    function saveSession() {
        if (restoring) return
        const list = []
        for (let i = 0; i < tabs.count; i++) {
            const t = tabs.get(i)
            list.push({ ws: t.ws, url: t.url, title: t.title, current: t.tid === currentTab || t.tid === lastTabIn[t.ws] })
        }
        saved.tabsJson = JSON.stringify(list)
        saved.workspacesJson = JSON.stringify(workspaces)
        saved.current = workspace
        saved.claudeOpen = claudeOpen
    }
    Timer { id: saveLater; interval: 1500; onTriggered: win.saveSession() }

    Component.onCompleted: {
        try { const w = JSON.parse(saved.workspacesJson || "null"); if (w && w.length) workspaces = w } catch (e) {}
        workspace = workspaces.indexOf(saved.current) >= 0 ? saved.current : workspaces[0]
        claudeOpen = saved.claudeOpen
        let list = []
        try { list = JSON.parse(saved.tabsJson || "[]") } catch (e) {}
        for (const t of list) {
            if (workspaces.indexOf(t.ws) < 0) continue
            const tid = openTab(t.url, t.ws, true)
            setTab(tid, "title", t.title || "")
            if (t.current) { const m = lastTabIn; m[t.ws] = tid; lastTabIn = m }
        }
        for (const u of StartUrls) openTab(urlFor(u), workspace, true)
        const mine = tabsIn(workspace)
        currentTab = StartUrls.length ? mine[mine.length - 1]
                   : (mine.indexOf(lastTabIn[workspace]) >= 0 ? lastTabIn[workspace] : (mine.length ? mine[0] : openTab("", workspace)))
        restoring = false
        saveSession()
    }
    onClosing: saveSession()

    // ---- downloads -------------------------------------------------------
    function startDownload(d) {
        d.downloadDirectory = StandardPaths.writableLocation(StandardPaths.DownloadLocation).toString().replace("file://", "")
        d.accept()
        downloads.insert(0, { name: d.downloadFileName, dir: d.downloadDirectory, state: "downloading", item: d })
        downloadsPanel.open()
    }

    // ---- layout ----------------------------------------------------------
    RowLayout {
        anchors.fill: parent
        spacing: 0

        TabList {
            id: tabList
            Layout.fillHeight: true
            Layout.preferredWidth: 260
            model: tabs
            workspaces: win.workspaces
            workspace: win.workspace
            currentTab: win.currentTab
            onActivate: (tid) => win.currentTab = tid
            onClose: (tid) => win.closeTab(tid)
            onNewTab: win.openTab("", win.workspace)
            onSwitchWorkspace: (ws) => win.switchWorkspace(ws)
            onAddWorkspace: (name) => {
                if (!name || win.workspaces.indexOf(name) >= 0) return
                win.workspaces = win.workspaces.concat([name]); win.switchWorkspace(name)
            }
        }
        Rectangle { Layout.fillHeight: true; width: 1; color: Theme.line }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            AddressBar {
                id: bar
                Layout.fillWidth: true
                view: win.current
                wsColor: Theme.wsColor(win.workspace)
                blockedCount: win.current ? win.blockedOnCurrent : 0
                claudeOpen: win.claudeOpen
                onGo: (text) => win.navigate(text)
                onToggleClaude: win.claudeOpen = !win.claudeOpen
                onSendToPhone: win.sendToPhone()
                onShowDownloads: downloadsPanel.open()
                workspace: win.workspace
                onShowMenu: mainMenu.popup(bar, bar.width - mainMenu.width - 8, bar.height)
            }
            BookmarksBar {
                id: bookmarksBar
                Layout.fillWidth: true
                workspace: win.workspace
                onOpen: (url, newTab) => newTab ? win.openTab(url, win.workspace, true) : win.navigate(url)
            }
            FindBar {
                id: findBar
                Layout.fillWidth: true
                view: win.current
            }
            SplitView {
              id: split
              Layout.fillWidth: true
              Layout.fillHeight: true
              orientation: Qt.Vertical
              handle: Rectangle { implicitHeight: 5; color: SplitHandle.pressed || SplitHandle.hovered ? Theme.mint : Theme.line }
              Item {
                id: pages
                SplitView.fillHeight: true
                Repeater {
                    model: tabs
                    delegate: WebEngineView {
                        id: v
                        required property int tid
                        required property string ws
                        required property var model      // model.url: "url" itself is WebEngineView's
                        anchors.fill: parent
                        visible: tid === win.currentTab
                        profile: win.profileFor(ws)
                        settings.fullScreenSupportEnabled: true
                        settings.pluginsEnabled: true
                        settings.pdfViewerEnabled: true
                        settings.dnsPrefetchEnabled: false
                        settings.scrollAnimatorEnabled: true
                        Component.onCompleted: {
                            const m = win.views; m[tid] = v; win.views = m
                            v.url = model.url
                        }
                        onTitleChanged: win.setTab(tid, "title", title)
                        onUrlChanged: { win.setTab(tid, "url", v.url.toString()); saveLater.restart() }
                        onIconChanged: win.setTab(tid, "icon", icon.toString())
                        onLoadingChanged: (r) => {
                            win.setTab(tid, "loading", v.loading)
                            if (r.status === WebEngineView.LoadSucceededStatus)
                                Library.recordVisit(ws, v.url.toString(), v.title)
                        }
                        // autofill: our script runs in an isolated world and talks to `bridge`
                        webChannel: channel
                        webChannelWorld: WebEngineScript.ApplicationWorld
                        userScripts.collection: [
                            { name: "qwebchannel", sourceUrl: "qrc:///qtwebchannel/qwebchannel.js",
                              injectionPoint: WebEngineScript.DocumentCreation, worldId: WebEngineScript.ApplicationWorld },
                            { name: "ub-autofill", sourceUrl: "qrc:///ub/scripts/autofill.js",
                              injectionPoint: WebEngineScript.DocumentReady, worldId: WebEngineScript.ApplicationWorld },
                            // drop-down lists drawn in the page (Chromium's pop-up closes at once under Wayland)
                            { name: "ub-select", sourceUrl: "qrc:///ub/scripts/select.js", runsOnSubFrames: true,
                              injectionPoint: WebEngineScript.DocumentCreation, worldId: WebEngineScript.ApplicationWorld }
                        ]
                        WebChannel { id: channel; registeredObjects: [bridge] }
                        QtObject {
                            id: bridge
                            WebChannel.id: "ub"
                            function loginForm(origin) { win.offerLogins(v, ws, origin) }
                            function submitted(origin, username, password) { win.offerSave(v, ws, origin, username, password) }
                        }
                        onNewWindowRequested: (request) => {
                            if (!Opener.isWeb(String(request.requestedUrl))) { Opener.openUrl(request.requestedUrl); return }
                            const bg = request.destination === WebEngineNewWindowRequest.InNewBackgroundTab
                            const n = win.openTab("about:blank", ws, bg)
                            win.views[n].acceptAsNewWindow(request)
                        }
                        onWindowCloseRequested: win.closeTab(tid)
                        onFullScreenRequested: (r) => { r.accept(); r.toggleOn ? win.showFullScreen() : win.showNormal() }
                        onFeaturePermissionRequested: (origin, feature) => permission.ask(v, origin, feature)
                    }
                }
                PermissionPrompt { id: permission }
                LoginBar {
                    id: loginBar
                    anchors { top: parent.top; left: parent.left; right: parent.right }
                    property var view: null
                    property string ws: ""
                    onFill: (id) => win.fillLogin(view, id)
                    onSave: {
                        Library.saveLogin(ws, origin, username, password)
                        toast.show((update ? "Password updated" : "Password saved") + " for " + (username || "this site") + " (in your keyring)")
                    }
                }
              }
              // Chromium's own DevTools (Console, Network, Application, Elements,
              // Sources, Performance...), docked under the page, for the current tab.
              WebEngineView {
                  id: devtools
                  visible: win.devOpen
                  SplitView.preferredHeight: Math.round(win.height * 0.38)
                  SplitView.minimumHeight: 140
                  onLoadingChanged: (r) => { if (r.status === WebEngineView.LoadSucceededStatus && win.devPanel) win.showDevPanel(win.devPanel) }
              }
            }
        }

        Rectangle { Layout.fillHeight: true; width: 1; color: Theme.line; visible: win.claudeOpen }
        ClaudePanel {
            id: claude
            visible: win.claudeOpen
            Layout.fillHeight: true
            Layout.preferredWidth: 420
            pageTitle: win.current ? win.current.title : ""
            pageUrl: win.current ? win.current.url.toString() : ""
            tab: win.currentTab
            workspace: win.workspace
        }
    }

    Downloads { id: downloadsPanel; model: downloads }
    HistoryPanel { id: historyPanel; workspace: win.workspace; onOpen: (url) => win.navigate(url) }
    PasswordsPanel { id: passwordsPanel; workspace: win.workspace }
    ImportDialog { id: importDialog }
    // ---- developer tools -----------------------------------------------------
    property bool devOpen: false
    property string devPanel: ""
    function setDevTools(open, panel) {
        devPanel = panel || ""
        for (const tid in views) if (views[tid] && views[tid].devToolsView) views[tid].devToolsView = null
        devOpen = open
        if (open && current) current.devToolsView = devtools
        if (open && devPanel) showDevPanel(devPanel)
    }
    // Ask the DevTools front end to show a panel (console, network, resources = Application).
    // Its internals move between Chromium versions, so this is best-effort: if it
    // fails, DevTools simply opens on the panel it showed last.
    function showDevPanel(panel) {
        devPanelTries = 0
        devPanelTimer.panel = panel
        devPanelTimer.restart()
    }
    property int devPanelTries: 0
    Timer {
        id: devPanelTimer
        property string panel: ""
        interval: 400; repeat: false
        // The front end builds its views after the page loads: start the switch,
        // read its outcome on the next tick (runJavaScript can't wait for a
        // promise), and try again a few times until it says ok.
        property bool checking: false
        onTriggered: {
            if (!checking) {
                devtools.runJavaScript("(window.__ubPanel = undefined, import('devtools://devtools/bundled/ui/legacy/legacy.js')"
                    + ".then(UI => UI.ViewManager.ViewManager.instance().showView(" + JSON.stringify(panel) + "))"
                    + ".then(() => window.__ubPanel = 'ok', e => window.__ubPanel = String(e)), 'started')")
                checking = true
                restart()
                return
            }
            checking = false
            devtools.runJavaScript("window.__ubPanel", (r) => {
                if (r === "ok") { console.info("devtools: opened the " + panel + " panel"); return }
                if (++win.devPanelTries < 8) devPanelTimer.restart()
                else console.warn("devtools: couldn't open the " + panel + " panel: " + r)
            })
        }
    }

    Menu {
        id: mainMenu
        MenuItem { text: "History  (Ctrl+H)"; onTriggered: historyPanel.open() }
        MenuItem { text: "Passwords"; onTriggered: passwordsPanel.open() }
        MenuItem { text: "Downloads  (Ctrl+Shift+Y)"; onTriggered: downloadsPanel.open() }
        MenuSeparator {}
        MenuItem { text: "Import from Chrome…"; onTriggered: importDialog.open() }
        MenuSeparator {}
        Menu {
            title: "Developer"
            MenuItem { text: win.devOpen ? "Close developer tools  (F12)" : "Developer tools  (F12)"; onTriggered: win.setDevTools(!win.devOpen, "") }
            MenuItem { text: "Console  (Ctrl+Shift+J)"; onTriggered: win.setDevTools(true, "console") }
            MenuItem { text: "Network  (Ctrl+Shift+E)"; onTriggered: win.setDevTools(true, "network") }
            MenuItem { text: "Application: storage, cookies, workers"; onTriggered: win.setDevTools(true, "resources") }
            MenuItem { text: "Inspect element  (Ctrl+Shift+C)"; onTriggered: { win.setDevTools(true, ""); if (win.current) win.current.triggerWebAction(WebEngineView.InspectElement) } }
            MenuSeparator {}
            MenuItem { text: "View page source  (Ctrl+U)"; onTriggered: if (win.current) win.openTab("view-source:" + win.current.url, win.workspace) }
            MenuItem { text: "Reload, skipping the cache  (Ctrl+Shift+R)"; onTriggered: if (win.current) win.current.reloadAndBypassCache() }
        }
        MenuSeparator {}
        MenuItem { text: "Ultimate Browser " + AppVersion; enabled: false }
    }

    // ---- logins: fill and save ------------------------------------------------
    property var fillRequests: ({})            // keyring request -> view
    function offerLogins(v, ws, origin) {
        const saved = Library.logins(ws, origin)
        if (!saved.length) return
        if (saved.length === 1) return fillLogin(v, saved[0].id)
        loginBar.view = v; loginBar.ws = ws; loginBar.origin = origin
        loginBar.choices = saved; loginBar.mode = "choose"
    }
    function fillLogin(v, loginId) {
        const login = Library.logins(tabs_ws_of_view(v)).find(l => l.id === loginId)
        const req = Library.fetchPassword(loginId)
        const m = fillRequests; m[req] = { view: v, username: login ? login.username : "" }; fillRequests = m
    }
    function tabs_ws_of_view(v) { for (const tid in views) if (views[tid] === v) return tabs_ws(Number(tid)); return workspace }
    Connections {
        target: Library
        function onPasswordReady(req, pw, err) {
            const c = win.checkRequests[req]
            if (c) {
                const m = win.checkRequests; delete m[req]; win.checkRequests = m
                if (err || pw !== c.password) win.showSave(c, true)    // missing from the keyring, or changed
                return
            }
            const r = win.fillRequests[req]
            if (!r) return
            const m = win.fillRequests; delete m[req]; win.fillRequests = m
            if (err || !r.view) return
            r.view.runJavaScript("__ubFill(" + JSON.stringify(r.username) + ", " + JSON.stringify(pw) + ")", WebEngineScript.ApplicationWorld)
        }
    }
    // After a sign-in: offer to save a new login, or to update a saved one
    // whose password changed (checked against the keyring; nothing shown if
    // it's the same).
    property var checkRequests: ({})           // keyring request -> {view, ws, origin, username, password}
    property double lastOffer: 0
    function offerSave(v, ws, origin, username, password) {
        if (Date.now() - lastOffer < 1500 && loginBar.mode === "save") return    // submit + click fire together
        const same = Library.logins(ws, origin).find(l => l.username === username)
        const pending = { view: v, ws: ws, origin: origin, username: username, password: password }
        if (!same) return showSave(pending, false)
        const req = Library.fetchPassword(same.id)
        const m = checkRequests; m[req] = pending; checkRequests = m
    }
    function showSave(p, update) {
        lastOffer = Date.now()
        loginBar.view = p.view; loginBar.ws = p.ws; loginBar.origin = p.origin
        loginBar.username = p.username; loginBar.password = p.password
        loginBar.update = update; loginBar.mode = "save"
    }

    // blocked-request count for the address bar's shield
    property int blockedOnCurrent: 0
    function updateBlocked() {
        let host = ""
        try { host = current ? new URL(current.url.toString()).hostname : "" } catch (e) {}
        blockedOnCurrent = host ? Blocker.blockedOn(host) : 0
    }
    onCurrentChanged: { updateBlocked(); if (devOpen) setDevTools(true, "") }
    Connections {
        target: Blocker
        function onBlocked(host, n) { win.updateBlocked() }
    }

    // ---- links for other apps (mailto: etc.): see src/opener.h ----------------
    Connections {
        target: Opener
        function onOpened(url, app, ok) {
            toast.show(ok ? "Opening " + app : "Couldn't open " + app)
        }
    }

    // ---- send to phone ---------------------------------------------------
    function sendToPhone() {
        if (!current) return
        const t = current.title || current.url.toString()
        // Posted as Claude (the desktop agent's token), not as Chris: the chat
        // server never pushes a person's own messages to their phone.
        Proc.run("send", ["python3", "-c",
            "import sys\nfrom ultimate_claude import chatapi\n"
            + "chatapi.post(sys.argv[1], attrs={'title': sys.argv[2], 'notify': 'normal', 'source': 'ultimate-browser', 'url': sys.argv[3]})",
            "📱 **" + t + "**\n\n" + current.url.toString(), "From the browser: " + t.slice(0, 120), current.url.toString()])
    }
    Connections {
        target: Proc
        function onFinished(tag, code, out, err) {
                        if (tag === "send") toast.show(code === 0 ? "Sent to your phone (Chat #claude)" : "Couldn't send: " + (err || out).trim().split("\n").pop().slice(0, 140))
        }
    }
    Toast { id: toast }

    // ---- the control socket: Claude's browser tools ------------------------
    function tabInfo(tid) {
        const i = indexOfTab(tid), t = tabs.get(i)
        return { id: t.tid, workspace: t.ws, title: t.title, url: t.url, active: t.tid === currentTab }
    }
    Connections {
        target: BrowserControl
        function onCommand(req, cmd, args) {
            const tid = args.tab !== undefined ? Number(args.tab) : win.currentTab
            const v = win.views[tid]
            const js = (script) => {
                if (!v) return BrowserControl.fail(req, "no tab " + tid)
                v.runJavaScript(script, (r) => BrowserControl.reply(req, r === undefined ? null : r))
            }
            switch (cmd) {
            case "tabs": {
                const out = []
                for (let i = 0; i < tabs.count; i++) out.push(win.tabInfo(tabs.get(i).tid))
                return BrowserControl.reply(req, { workspace: win.workspace, current: win.currentTab, tabs: out })
            }
            case "read": return js(Page.read(args.max || 20000))
            case "elements": return js(Page.elements())
            case "click": return js(Page.click(args.element))
            case "fill": return js(Page.fill(args.element, args.value || "", !!args.submit))
            case "navigate":
                if (!v) return BrowserControl.fail(req, "no tab " + tid)
                v.url = win.urlFor(String(args.url || ""))
                return BrowserControl.reply(req, win.tabInfo(tid))
            case "open": {
                const ws = args.workspace && win.workspaces.indexOf(args.workspace) >= 0 ? args.workspace : win.workspace
                const n = win.openTab(win.urlFor(String(args.url || "")), ws, !!args.background)
                return BrowserControl.reply(req, win.tabInfo(n))
            }
            case "activate":
                if (args.tab === undefined) { win.raise(); win.requestActivate(); return BrowserControl.reply(req, "raised") }
                if (win.indexOfTab(tid) < 0) return BrowserControl.fail(req, "no tab " + tid)
                win.switchWorkspace(win.tabs_ws(tid), tid)
                win.raise(); win.requestActivate()
                return BrowserControl.reply(req, win.tabInfo(tid))
            case "back": if (v) v.goBack(); return BrowserControl.reply(req, v ? win.tabInfo(tid) : null)
            case "close": win.closeTab(tid); return BrowserControl.reply(req, "closed")
            case "eval":
                if (!DebugEval) return BrowserControl.fail(req, "eval is for test builds only (UB_DEBUG_EVAL=1)")
                return js(String(args.script || ""))
            case "devtools":
                win.setDevTools(args.open !== false, String(args.panel || ""))
                return BrowserControl.reply(req, { open: win.devOpen, panel: win.devPanel })
            default: return BrowserControl.fail(req, "unknown command " + cmd)
            }
        }
    }
    function tabs_ws(tid) { const i = indexOfTab(tid); return i >= 0 ? tabs.get(i).ws : workspace }

    // ---- keys --------------------------------------------------------------
    Shortcut { sequences: [StandardKey.AddTab]; onActivated: { win.openTab("", win.workspace); bar.focusAddress() } }
    Shortcut { sequences: [StandardKey.Close]; onActivated: win.closeTab(win.currentTab) }
    Shortcut { sequences: ["Ctrl+L", "Alt+D", "F6"]; onActivated: bar.focusAddress() }
    Shortcut { sequence: "Ctrl+Tab"; onActivated: win.cycleTab(1) }
    Shortcut { sequence: "Ctrl+Shift+Tab"; onActivated: win.cycleTab(-1) }
    Shortcut { sequences: [StandardKey.Refresh, "Ctrl+R"]; onActivated: if (win.current) win.current.reload() }
    Shortcut { sequences: [StandardKey.Back]; onActivated: if (win.current) win.current.goBack() }
    Shortcut { sequences: [StandardKey.Forward]; onActivated: if (win.current) win.current.goForward() }
    Shortcut { sequences: [StandardKey.Find]; onActivated: findBar.open() }
    Shortcut { sequence: "Ctrl+J"; onActivated: { win.claudeOpen = !win.claudeOpen; if (win.claudeOpen) claude.focusInput() } }
    Shortcut { sequence: "Ctrl+Shift+S"; onActivated: win.sendToPhone() }
    Shortcut { sequence: "Ctrl+Shift+Y"; onActivated: downloadsPanel.open() }
    Shortcut { sequence: "Ctrl+H"; onActivated: historyPanel.open() }
    Shortcut { sequence: "Ctrl+D"; onActivated: bar.toggleBookmark() }
    Shortcut { sequences: ["F12", "Ctrl+Shift+I"]; onActivated: win.setDevTools(!win.devOpen, "") }
    Shortcut { sequence: "Ctrl+Shift+J"; onActivated: win.setDevTools(true, "console") }
    Shortcut { sequence: "Ctrl+Shift+E"; onActivated: win.setDevTools(true, "network") }
    Shortcut { sequence: "Ctrl+Shift+C"; onActivated: { win.setDevTools(true, ""); if (win.current) win.current.triggerWebAction(WebEngineView.InspectElement) } }
    Shortcut { sequence: "Ctrl+U"; onActivated: if (win.current) win.openTab("view-source:" + win.current.url, win.workspace) }
    Shortcut { sequence: "Ctrl+Shift+R"; onActivated: if (win.current) win.current.reloadAndBypassCache() }
    Shortcut { sequences: ["Ctrl+=", "Ctrl++"]; onActivated: if (win.current) win.current.zoomFactor = Math.min(3, win.current.zoomFactor + 0.1) }
    Shortcut { sequence: "Ctrl+-"; onActivated: if (win.current) win.current.zoomFactor = Math.max(0.3, win.current.zoomFactor - 0.1) }
    Shortcut { sequence: "Ctrl+0"; onActivated: if (win.current) win.current.zoomFactor = 1 }
    Repeater {
        model: 9
        Item {
            required property int index
            Shortcut {
                sequence: "Alt+" + (index + 1)
                onActivated: if (index < win.workspaces.length) win.switchWorkspace(win.workspaces[index])
            }
        }
    }

    // ---- small pieces --------------------------------------------------------
    component Toast: Rectangle {
        id: t
        function show(msg) { label.text = msg; opacity = 1; hide.restart() }
        parent: Overlay.overlay
        anchors.horizontalCenter: parent ? parent.horizontalCenter : undefined
        y: parent ? parent.height - height - 32 : 0
        width: label.implicitWidth + 32; height: 36; radius: 10
        color: Theme.raised; border.color: Theme.line
        opacity: 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
        Text { id: label; anchors.centerIn: parent; color: Theme.text; font.family: Theme.sans; font.pixelSize: 13 }
        Timer { id: hide; interval: 3000; onTriggered: t.opacity = 0 }
    }

    // Site permissions (camera, mic, location, notifications, screen share):
    // asked in a bar at the top of the page, never granted silently.
    component PermissionPrompt: Rectangle {
        id: pp
        property var view: null
        property url origin
        property int feature: 0
        function ask(v, o, f) { view = v; origin = o; feature = f; visible = true }
        function answer(yes) {
            if (view) view.grantFeaturePermission(origin, feature, yes)
            visible = false
        }
        readonly property var names: ({
            [WebEngineView.MediaAudioCapture]: "use your microphone",
            [WebEngineView.MediaVideoCapture]: "use your camera",
            [WebEngineView.MediaAudioVideoCapture]: "use your camera and microphone",
            [WebEngineView.Geolocation]: "know your location",
            [WebEngineView.Notifications]: "show notifications",
            [WebEngineView.DesktopVideoCapture]: "see your screen",
            [WebEngineView.DesktopAudioVideoCapture]: "see and hear your screen"
        })
        visible: false
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: 44; color: Theme.raised
        z: 10
        RowLayout {
            anchors.fill: parent; anchors.leftMargin: 16; anchors.rightMargin: 12; spacing: 10
            Text {
                Layout.fillWidth: true; elide: Text.ElideRight
                text: (function () { try { return new URL(pp.origin.toString()).hostname } catch (e) { return String(pp.origin) } })() + " wants to " + (pp.names[pp.feature] || "use a device")
                color: Theme.text; font.family: Theme.sans; font.pixelSize: 13
            }
            Button { text: "Block"; onClicked: pp.answer(false) }
            Button { text: "Allow"; highlighted: true; onClicked: pp.answer(true) }
        }
    }
}

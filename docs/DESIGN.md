# Ultimate Browser — design

Chris's own web browser for Ultimate Linux. Decided 2026-09-30:

- **Engine: Chromium via QtWebEngine** (Qt 6.11.2, built natively as
  `packages/qt6-webengine` in ultimate-linux). Chrome-grade compatibility,
  Qt/KDE-native, Chromium security fixes arrive with Qt updates.
  *Fallback if Chris doesn't like it:* rewrite the shell on GTK4 + WebKitGTK 6
  in Python, the codebase Ultimate Mail and Ultimate SSH use.
- **All four feature areas in v1:** Claude built in; vertical tabs and
  workspaces; privacy by default; phone + Chat.
- Chrome stays installed for things that need real Chrome extensions
  (Chrome Remote Desktop).

## Shape

C++ core + QML UI, one binary `ultimate-browser`.

```
src/main.cpp          app start: QtWebEngineQuick::initialize, Chromium flags, QML engine
src/workspaces.*      Workspace = one persistent QQuickWebEngineProfile (own cookies,
                      logins, cache, history) + its tab list; saved/restored
src/blocker.*         QWebEngineUrlRequestInterceptor: blocks ad/tracker hosts
                      (domain lists in data/, suffix match), counts per tab
src/control.*         local control socket ($XDG_RUNTIME_DIR/ultimate/browser.sock),
                      JSON lines: tabs, read, open, navigate, click, fill, ...
                      QML registers each tab's WebEngineView with it
src/sendto.*          "send to phone": post the page to Ultimate Chat
qml/Main.qml          window: workspace switcher, vertical tabs, address bar,
                      page stack, Claude panel, find bar, downloads
mcp/browser_tools.py  Claude's tools: talks to the control socket
```

### Workspaces
Personal by default (user can add). Each is a named
off-the-record=false profile under `~/.local/share/ultimate-browser/<name>`,
so logins never leak between them. Tabs are per workspace; switching
workspace swaps the tab list. Session restore per workspace
(`~/.local/state/ultimate-browser/session.json`).

### Privacy by default
- Request interceptor blocks hosts on the tracker/ad lists (host-suffix
  match on a hash set, O(labels)). Lists ship in data/, updatable.
- No telemetry: QtWebEngine has none; Safe Browsing isn't in it either.
- DNS: the system resolver (a network-wide filter such as AdGuard keeps
  working) — no DoH override that would bypass it.
- Third-party cookies blocked (profile setting), HTTPS-first upgrade in the
  interceptor for plain http top-level loads where the host has HSTS lists
  (later).

### Claude built in
- A side panel (Ctrl+J) that drives the **Claude bar backend**
  (`ultimate-claude-bar ask/state/allow/deny`): one conversation, one
  approval path (bar pop-up + Chat thread), answers mirrored to #claude,
  history kept. The panel adds context: "Chris is looking at <title> <url>
  in tab <id>".
- Claude's browser tools come from the control socket:
  read-only (`browser_tabs`, `browser_read`) as an mcp.d drop-in, so the bar
  can always see what's open; acting tools (`browser_open`, `browser_navigate`,
  `browser_click`, `browser_fill`) go through the assistant's approval, like
  every other change.

### Phone and Chat
- "Send to phone" (Ctrl+Shift+S): posts title + URL to Ultimate Chat
  #notes with the desktop token (`ultimate-mail chat post`), which buzzes
  the phone.
- Tab sync through your own server: phase 2 (needs a small store there;
  the workspaces' tab lists are already JSON).

## Build and package
`cmake -B build -G Ninja -DCMAKE_PREFIX_PATH=/opt/qt6 && cmake --build build`.
Packaged in ultimate-linux as `packages/ultimate-browser` from a git snapshot,
like ultimate-mail/ultimate-ssh. Source: GitHub `cwoodall85/redcyfers-ultimate-browser`.

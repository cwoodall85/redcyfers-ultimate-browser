# Ultimate Browser

Chris's web browser for Ultimate Linux: Chromium (QtWebEngine) in a QML
shell, with Claude built in, workspaces with separate logins, tracker
blocking, and a line to the phone through Ultimate Chat.

- **Workspaces** (Personal, plus any you add): each its own
  cookies, logins, cache and history; each has its own tabs and colour.
  Alt+1..9 to switch.
- **Vertical tabs** on the left; session restored on start.
- **Claude** (Ctrl+J): the Claude bar's backend beside the page, knowing
  which tab you're on; answers and Allow prompts also in Chat #claude.
  Claude's tools: browser_tabs / browser_read / browser_elements (look),
  browser_open / navigate / click / fill (act, with your OK).
- **Privacy**: ad/tracker hosts blocked (🛡 in the address bar: count,
  per-site allow), no telemetry, DNS through the system (Shield).
- **Phone**: Ctrl+Shift+S sends the page to Chat #notes.

Build: `cmake -B build -G Ninja -DCMAKE_PREFIX_PATH=/opt/qt6 && cmake --build build && ./build/ultimate-browser`
Needs QtWebEngine 6.8+ (ultimate-linux `packages/qt6-webengine`). Design: docs/DESIGN.md.

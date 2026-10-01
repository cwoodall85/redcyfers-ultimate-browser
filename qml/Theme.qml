// Ultimate Browser's look: the Ultimate Linux dark palette, one accent per
// area (Chris's rule): mint for the browser chrome, coral for Claude, and
// a colour per workspace so you always know whose logins you're in.
pragma Singleton
import QtQuick

QtObject {
    readonly property color base: "#0a0f0d"        // window
    readonly property color panel: "#0f1613"       // sidebar, bars
    readonly property color raised: "#16201c"      // fields, hovered rows
    readonly property color line: "#1f2d27"
    readonly property color text: "#dff3e6"
    readonly property color dim: "#7fa593"
    readonly property color mint: "#00ffa8"
    readonly property color coral: "#ff8f6b"
    readonly property color danger: "#ff5d73"
    readonly property string mono: "JetBrains Mono"
    readonly property string sans: "Inter"
    // workspace colours: Personal is blue; any other name gets a colour
    // from this set, always the same one for the same name
    readonly property var wsPalette: ["#f5c542", "#ff5d73", "#b48cff", "#ff8f6b", "#5fd4c4", "#8fd14f"]
    function wsColor(name) {
        if (name === "Personal") return "#4fb3ff"
        let h = 0
        for (let i = 0; i < name.length; i++) h = (h * 31 + name.charCodeAt(i)) >>> 0
        return wsPalette[h % wsPalette.length]
    }
}

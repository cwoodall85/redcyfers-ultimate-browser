// Drop-down lists (<select>) drawn inside the page.
//
// Chromium shows a <select>'s list as a separate pop-up window. Under
// Wayland, in a Qt Quick window, that pop-up is closed by the compositor the
// moment it appears (it flashes as an empty box). So this script, in the
// browser's own isolated world, opens its own list instead: positioned under
// the field, in a shadow root the page's CSS can't touch. Choosing an option
// sets the field and fires input + change, exactly as the native list does.
// Keys: Up/Down, PageUp/PageDown, Home/End, Enter/Space, Esc, Tab, typing
// jumps to an option. Multi-selects and list boxes (size > 1) are drawn in
// the page already and are left alone.
(function () {
    let host = null, root = null, list = null, current = null, index = -1, typed = "", typedAt = 0;

    function eligible(s) { return s && s.tagName === "SELECT" && !s.multiple && !(s.size > 1) && !s.disabled; }

    function close(refocus) {
        if (host) host.remove();
        host = root = list = null;
        if (refocus && current) current.focus();
        current = null; index = -1;
        window.removeEventListener("scroll", onScroll, true);
        window.removeEventListener("resize", onResize, true);
    }
    function onScroll(e) { if (!host || !host.contains(e.target)) close(false); }
    function onResize() { close(false); }

    function choose(i) {
        const s = current;
        if (!s || i < 0) return close(true);
        const opt = s.options[i];
        if (opt && !opt.disabled && s.selectedIndex !== i) {
            s.selectedIndex = i;
            s.dispatchEvent(new Event("input", { bubbles: true }));
            s.dispatchEvent(new Event("change", { bubbles: true }));
        }
        close(true);
    }

    function highlight(i, scroll) {
        if (!list) return;
        const items = list.querySelectorAll(".opt");
        items.forEach((el) => el.classList.toggle("hi", Number(el.dataset.i) === i));
        index = i;
        if (scroll) { const el = list.querySelector('.opt[data-i="' + i + '"]'); if (el) el.scrollIntoView({ block: "nearest" }); }
    }
    function step(d) {
        const s = current; if (!s) return;
        let i = index;
        for (let n = 0; n < s.options.length; n++) {
            i = Math.max(0, Math.min(s.options.length - 1, i + d));
            if (!s.options[i].disabled && !s.options[i].hidden) break;
        }
        highlight(i, true);
    }

    function open(s) {
        close(false);
        current = s;
        host = document.createElement("ub-select-list");
        root = host.attachShadow({ mode: "closed" });
        const r = s.getBoundingClientRect();
        const below = window.innerHeight - r.bottom, above = r.top;
        const maxH = Math.max(120, Math.min(360, Math.max(below, above) - 12));
        const openUp = below < 200 && above > below;
        root.innerHTML = `<style>
            .box { position: fixed; z-index: 2147483647; left: ${Math.max(4, r.left)}px;
                   ${openUp ? `bottom: ${window.innerHeight - r.top + 2}px;` : `top: ${r.bottom + 2}px;`}
                   min-width: ${Math.max(120, r.width)}px; max-width: ${Math.max(r.width, 520)}px; max-height: ${maxH}px;
                   overflow: auto; background: #16201c; color: #dff3e6; border: 1px solid #2c3d35; border-radius: 8px;
                   box-shadow: 0 8px 28px rgba(0,0,0,.45); padding: 4px; box-sizing: border-box;
                   font: 14px/1.3 Inter, system-ui, sans-serif; }
            .opt { padding: 6px 10px; border-radius: 6px; cursor: default; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
            .opt.sel { color: #00ffa8; }
            .opt.hi { background: rgba(0,255,168,.16); }
            .opt.dis { opacity: .4; }
            .grp { padding: 6px 10px 2px; font-size: 12px; color: #7fa593; font-weight: 600; }
            .grp ~ .opt.ingrp { padding-left: 20px; }
        </style><div class="box" role="listbox"></div>`;
        list = root.querySelector(".box");
        let lastGroup = null;
        [...s.options].forEach((o, i) => {
            if (o.hidden) return;
            const g = o.parentElement && o.parentElement.tagName === "OPTGROUP" ? o.parentElement : null;
            if (g && g !== lastGroup) {
                const h = document.createElement("div"); h.className = "grp"; h.textContent = g.label; list.appendChild(h);
            }
            lastGroup = g;
            const d = document.createElement("div");
            d.className = "opt" + (i === s.selectedIndex ? " sel" : "") + (o.disabled || (g && g.disabled) ? " dis" : "") + (g ? " ingrp" : "");
            d.dataset.i = i;
            d.textContent = o.label || o.text || " ";
            d.setAttribute("role", "option");
            d.addEventListener("mousemove", () => highlight(i, false));
            d.addEventListener("mousedown", (e) => { e.preventDefault(); e.stopPropagation(); if (!d.classList.contains("dis")) choose(i); });
            list.appendChild(d);
        });
        list.addEventListener("mousedown", (e) => { e.preventDefault(); e.stopPropagation(); });
        document.documentElement.appendChild(host);
        highlight(s.selectedIndex, true);
        window.addEventListener("scroll", onScroll, true);
        window.addEventListener("resize", onResize, true);
    }

    // Open on a click of the field (instead of Chromium's pop-up).
    document.addEventListener("mousedown", (e) => {
        if (e.button !== 0) return;
        if (host && e.composedPath().includes(host)) return;
        const s = e.target.closest ? e.target.closest("select") : null;
        if (host) { const was = current; close(false); if (s === was) { e.preventDefault(); return; } }
        if (!eligible(s)) return;
        e.preventDefault();
        s.focus();
        open(s);
    }, true);

    document.addEventListener("keydown", (e) => {
        const s = e.target;
        if (host) {
            const k = e.key;
            if (k === "ArrowDown") step(1);
            else if (k === "ArrowUp") step(-1);
            else if (k === "PageDown") step(8);
            else if (k === "PageUp") step(-8);
            else if (k === "Home") { highlight(-1); step(1); }
            else if (k === "End") { highlight(current.options.length); step(-1); }
            else if (k === "Enter" || k === " ") choose(index);
            else if (k === "Escape") close(true);
            else if (k === "Tab") { choose(index); return; }
            else if (k.length === 1) {
                const now = Date.now(); typed = (now - typedAt > 800 ? "" : typed) + k.toLowerCase(); typedAt = now;
                const i = [...current.options].findIndex((o) => !o.disabled && (o.label || o.text).toLowerCase().startsWith(typed));
                if (i >= 0) highlight(i, true);
            } else return;
            e.preventDefault(); e.stopPropagation();
            return;
        }
        // keys that would open Chromium's pop-up open ours instead
        if (eligible(s) && (e.key === " " || e.key === "F4" || (e.altKey && (e.key === "ArrowDown" || e.key === "ArrowUp")))) {
            e.preventDefault(); e.stopPropagation();
            open(s);
        }
    }, true);

    document.addEventListener("focusout", (e) => { if (host && e.target === current) setTimeout(() => { if (host && document.activeElement !== current) close(false); }, 0); }, true);
})();

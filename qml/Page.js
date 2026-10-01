// Scripts run inside pages for Claude's browser tools (via the control
// socket). Each returns a JS source string for WebEngineView.runJavaScript;
// what the script returns is what the tool gets back. They run in the
// page's own world only to read and to click/fill what Claude was allowed to.
.pragma library

// Title, address and the visible text, trimmed to `max` characters.
function read(max) {
    return "(() => { const t = (document.body ? document.body.innerText : '') || '';" +
           " return { title: document.title, url: location.href, length: t.length," +
           " text: t.slice(0, " + (max | 0 || 20000) + ") }; })()"
}

// The interactive elements (links, buttons, fields), numbered. The number is
// stamped on the element (data-ub-id) so click/fill can find it again.
function elements() {
    return "(() => { const out = []; let n = 0;" +
        " const sel = 'a[href], button, input:not([type=hidden]), select, textarea, [role=button], [role=link], [contenteditable=true]';" +
        " for (const e of document.querySelectorAll(sel)) {" +
        "   const r = e.getBoundingClientRect(); if (!r.width || !r.height) continue;" +
        "   const st = getComputedStyle(e); if (st.visibility === 'hidden' || st.display === 'none') continue;" +
        "   n++; e.setAttribute('data-ub-id', n);" +
        "   const label = (e.innerText || e.value || e.placeholder || e.getAttribute('aria-label') || e.title || e.name || '').trim().replace(/\\s+/g, ' ').slice(0, 80);" +
        "   out.push({ id: n, tag: e.tagName.toLowerCase(), type: e.type || '', label: label, href: e.href || '' });" +
        "   if (n >= 300) break; }" +
        " return out; })()"
}

function click(id) {
    return "(() => { const e = document.querySelector('[data-ub-id=\"" + (id | 0) + "\"]');" +
           " if (!e) return 'no element " + (id | 0) + ": list the elements again';" +
           " e.scrollIntoView({ block: 'center' }); e.focus(); e.click(); return 'clicked'; })()"
}

// Set a field's value the way typing would (input + change events), then
// optionally submit its form.
function fill(id, value, submit) {
    return "(() => { const e = document.querySelector('[data-ub-id=\"" + (id | 0) + "\"]');" +
           " if (!e) return 'no element " + (id | 0) + ": list the elements again';" +
           " e.scrollIntoView({ block: 'center' }); e.focus();" +
           " const v = " + JSON.stringify(String(value)) + ";" +
           " if (e.isContentEditable) e.innerText = v; else {" +
           "   const set = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(e), 'value');" +
           "   if (set && set.set) set.set.call(e, v); else e.value = v; }" +
           " e.dispatchEvent(new Event('input', { bubbles: true }));" +
           " e.dispatchEvent(new Event('change', { bubbles: true }));" +
           (submit ? " if (e.form) { e.form.requestSubmit ? e.form.requestSubmit() : e.form.submit(); return 'filled and submitted'; }" : "") +
           " return 'filled'; })()"
}

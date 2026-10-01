// Ultimate Browser autofill: runs in the browser's own isolated JS world
// (WebEngineScript.ApplicationWorld), so the page's scripts can't see or
// call any of this. It talks to the browser over a WebChannel object "ub":
//   ub.loginForm(origin)                       a login form is on the page
//   ub.submitted(origin, username, password)   one was just submitted
// and the browser fills a form by running __ubFill(username, password) here.
(function () {
    if (window.top !== window) return;              // top-level pages only
    let ub = null;
    new QWebChannel(qt.webChannelTransport, (ch) => { ub = ch.objects.ub; scan(); });

    const passwordField = () => [...document.querySelectorAll("input[type=password]")]
        .find((e) => e.offsetParent !== null && !e.disabled) || null;
    function usernameFor(pw) {
        const form = pw.form || document;
        const inputs = [...form.querySelectorAll("input")].filter((e) => e.offsetParent !== null);
        const i = inputs.indexOf(pw);
        const before = inputs.slice(0, i < 0 ? inputs.length : i).reverse();
        return before.find((e) => /^(email|text|tel)$/.test(e.type) || /user|email|login/i.test(e.autocomplete + e.name + e.id)) || null;
    }
    function set(el, v) {
        const proto = Object.getPrototypeOf(el);
        const d = Object.getOwnPropertyDescriptor(proto, "value");
        if (d && d.set) d.set.call(el, v); else el.value = v;
        el.dispatchEvent(new Event("input", { bubbles: true }));
        el.dispatchEvent(new Event("change", { bubbles: true }));
    }
    window.__ubFill = function (user, pass) {
        const pw = passwordField();
        const u = pw ? usernameFor(pw) : document.querySelector("input[type=email], input[autocomplete=username]");
        if (u && user) set(u, user);
        if (pw) set(pw, pass);
        return pw ? "filled" : (u ? "filled username" : "no login form");
    };

    // Announce each login field once (not once per page): two-step sign-ins
    // (username, then password on the next screen of the same page) need a
    // second fill when the password field appears.
    const announced = new WeakSet();
    function scan() {
        if (!ub) return;
        const field = passwordField() || document.querySelector("input[autocomplete=username], input[type=email]");
        if (field && !announced.has(field)) {
            announced.add(field);
            ub.loginForm(location.origin);
        }
    }
    // Remember the username typed on a first step, for saving at the password step.
    const USER_KEY = "__ub_login_user";
    document.addEventListener("change", (e) => {
        const el = e.target;
        if (el && el.tagName === "INPUT" && (/^(email|text|tel)$/.test(el.type)) && el.value
            && /user|email|login|account|identifier/i.test((el.autocomplete || "") + (el.name || "") + (el.id || "") + el.type)) {
            try { sessionStorage.setItem(USER_KEY, el.value); } catch (x) {}
        }
    }, true);
    // single-page apps draw their login form late
    new MutationObserver(scan).observe(document.documentElement, { childList: true, subtree: true });

    function capture() {
        const pw = passwordField();
        if (!ub || !pw || !pw.value) return;
        const u = usernameFor(pw);
        let user = u && u.value ? u.value : "";
        if (!user) { try { user = sessionStorage.getItem(USER_KEY) || ""; } catch (x) {} }
        ub.submitted(location.origin, user, pw.value);
    }
    document.addEventListener("submit", capture, true);
    document.addEventListener("click", (e) => {
        const b = e.target.closest && e.target.closest("button, input[type=submit], [role=button]");
        if (b && passwordField()) capture();
    }, true);
    document.addEventListener("keydown", (e) => { if (e.key === "Enter" && e.target.type === "password") capture(); }, true);
})();

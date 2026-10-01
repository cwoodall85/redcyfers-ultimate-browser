"""Ultimate Browser, for Claude: what's open and what's on a page.
Read-only (the mcp.d contract): acting in tabs -- open, navigate, click,
fill -- is the assistant's, behind its approval. Installed to
/usr/lib/ultimate/mcp.d/ by the browser package; talks to the browser's
control socket through ultimate_claude.browser.
"""

from ultimate_claude import browser

INSTRUCTIONS = ("Ultimate Browser is Chris's web browser. browser_tabs shows what's open "
                "(and which tab he's looking at); browser_read gets a page's text; "
                "browser_elements numbers the links, buttons and fields for the "
                "assistant's browser_click / browser_fill.")


def _ask(cmd, **args):
    try:
        return browser.text(browser.call(cmd, **args))
    except browser.BrowserError as e:
        return str(e)


def browser_tabs() -> str:
    """List Ultimate Browser's open tabs: id, workspace, title, address, and
    which one Chris is looking at."""
    return _ask("tabs")


def browser_read(tab: int = -1, max_chars: int = 20000) -> str:
    """Read a page in Ultimate Browser: its title, address and visible text.

    Args:
        tab: the tab id from browser_tabs; -1 for the tab Chris is looking at
        max_chars: at most this much text (default 20000)
    """
    return _ask("read", tab=None if tab < 0 else tab, max=max_chars)


def browser_elements(tab: int = -1) -> str:
    """Number the links, buttons and form fields on a page in Ultimate Browser,
    with their labels, for clicking or filling. Numbers are only good until
    the page changes: list again after navigating.

    Args:
        tab: the tab id from browser_tabs; -1 for the tab Chris is looking at
    """
    return _ask("elements", tab=None if tab < 0 else tab)


TOOLS = [browser_tabs, browser_read, browser_elements]

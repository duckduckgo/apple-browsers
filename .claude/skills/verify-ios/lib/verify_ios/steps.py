"""Shared DuckDuckGo app steps for proofs: each one is a user action with the app's quirks handled once.

Every step uses only generic actions and the ids documented in ../../features/. Keep it that way: when the app gets
an XCUITest target, these port to Swift mechanically, from the feature map, not from this code.
"""
import time

from . import env
from .env import Failed

IDS = {
    "iphone": dict(dismiss="id=UnifiedToggleInput.Button.Dismiss", fire="id=Browser.Toolbar.Button.Fire",
                   aichat="id=Browser.OmniBar.Button.AIChat"),
    # iPad: the Fire button has no accessibility id; its label is the icon asset name.
    "ipad": dict(dismiss="id=Browser.OmniBar.Button.Dismiss", fire='label="Fire Solid 24"',
                 aichat="id=Browser.TabsBar.AIChatMenuButton"),
}
# The tab switcher ships in two layouts that alternate between runs.
NEW_TAB = ['role=button label="New Tab"', 'label="Add 24"']
DONE = ["id=TabSwitcher.Button.Done", 'role=button label="Done"']
FIXTURE_TAB = 'label="Open \\"verify-ios fixture\\" at 127.0.0.1" nth=0'


def ids(ios):
    return IDS[ios.device]


def tap_first_present(ios, locators, timeout=1.5):
    """Tap whichever of several alternative controls exists (for UI that ships in more than one layout)."""
    for loc in locators:
        if ios.exists(loc, timeout):
            return ios.tap(loc)
    raise Failed(f"none of {locators} present")


# ---------------------------------------------------------------- session and pages
def fresh_start(ios):
    """Known state: reinstalled app, onboarding skipped, pinned flags, default capture conditions (light, default text
    size, portrait, live status bar), one blank tab, address bar not focused.
    (A fresh tab sometimes opens with the bar focused and sometimes not; this always leaves it unfocused.)"""
    ios.reset()
    ios.default_capture_conditions()
    dismiss_address_bar(ios)
    ios.expect_keyboard(shown=False)


def open_url(ios, url, wait_for=None):
    """Type `url` into the address bar and submit (the user path), then wait until the tab shows that URL and it
    differs from what the tab showed before. Opening the URL the tab already shows can't be told apart: avoid it."""
    before = ios.page_url()
    ios.tap("id=searchEntry")
    ios.type("id=searchEntry", url, submit=True)
    want = url.split("://", 1)[-1].rstrip("/")
    ios.eventually(f"tab loaded {url}", lambda: (ios.page_url() or "") != (before or "") and want in (ios.page_url() or ""), 15)
    if wait_for:   # page text reaches the accessibility tree a moment after the URL changes
        ios.wait(wait_for, "exists", 10)


def open_fixture(ios, token):
    """Load the skill's fixture page with `token` through the address bar, and wait until its text is readable."""
    open_url(ios, ios.fixture_url(token), wait_for=f'label="token: {token}"')


def dismiss_address_bar(ios):
    """Leave address-bar editing if it is active (a new tab may open with it focused; on iPhone the keyboard then
    covers the toolbar). Does nothing when the bar isn't being edited."""
    if ios.exists(ids(ios)["dismiss"], 3):
        ios.tap(ids(ios)["dismiss"])


# ---------------------------------------------------------------- tabs
def tab_count(ios):
    """The number on the tab-switcher button: the numeric label right after it in the native tree (the button's own
    child). Raises if the button or its number isn't there, rather than guessing."""
    lines = ios.snapshot().get("tree", "").splitlines()
    for i, line in enumerate(lines):
        if "Browser.Toolbar.Button.TabSwitcher" in line:
            for nxt in lines[i + 1:i + 4]:
                label = nxt.split("label=")[1].split(" value=")[0].strip("'\"") if "label=" in nxt else ""
                if label.isdigit():
                    return int(label)
            raise Failed("tab-switcher button found, but no tab-count label right after it in the tree")
    raise Failed("no tab-switcher button (Browser.Toolbar.Button.TabSwitcher) in the tree")


def expect_tab_count(ios, n, timeout=8):
    return ios.eventually(f"tab count is {n}", lambda: tab_count(ios) == n and n, timeout)


def new_tab(ios):
    """Open a new tab the way a user does: cmd+t on iPad (hardware keyboard), tab switcher → New Tab on iPhone."""
    if ios.device == "ipad":
        return ios.key("cmd+t")
    ios.tap("id=Browser.Toolbar.Button.TabSwitcher")
    return tap_first_present(ios, NEW_TAB)


def switch_to_tab(ios, tab_locator=FIXTURE_TAB):
    """iPad: tap the tab in the tab bar. iPhone: open the tab switcher and tap the tab."""
    if ios.device == "iphone":
        ios.tap("id=Browser.Toolbar.Button.TabSwitcher")
    return ios.tap(tab_locator)


def close_current_new_tab(ios):
    """Close the blank tab: the tab bar's close button on iPad; the switcher's close control, then Done, on iPhone."""
    if ios.device == "ipad":
        return tap_first_present(ios, ['label="Close tab"', 'label="Close Tab"'])
    ios.tap("id=Browser.Toolbar.Button.TabSwitcher")
    r = tap_first_present(ios, ['label="Close Tab"', 'label="Close tab"', 'label="Close \\"New Tab\\""'])
    tap_first_present(ios, DONE)
    return r


# ---------------------------------------------------------------- simulator settings (each registers its undo)
def _simctl(ios, *args):
    """A simulator setting; failing is setup trouble (INCONCLUSIVE), not the behavior under proof."""
    p = env.run(["xcrun", "simctl", *args])
    if p.returncode:
        raise env.SetupFailed(f"simctl {' '.join(args)} failed", stderr=p.stderr.strip())


def reset_location_permission(ios):
    """Forget the app's iOS location grant (back to "not determined"), and again after the proof."""
    ios.on_cleanup("reset the app's iOS location permission",
                   lambda: _simctl(ios, "privacy", ios.d.udid, "reset", "location", env.BUNDLE))
    _simctl(ios, "privacy", ios.d.udid, "reset", "location", env.BUNDLE)


def set_simulated_location(ios, lat, lon):
    """Give the simulator a location fix; cleared again after the proof (the undo is registered first)."""
    ios.on_cleanup("clear the simulated location", lambda: _simctl(ios, "location", ios.d.udid, "clear"))
    _simctl(ios, "location", ios.d.udid, "set", f"{lat},{lon}")


# ---------------------------------------------------------------- fire button
def fire(ios):
    """Press the Fire button and confirm "Delete All": closes all tabs and clears site data."""
    ios.tap(ids(ios)["fire"])
    ios.shot("fire-sheet")
    ios.tap("id=alert.forget-data.confirm")
    ios.wait("id=searchEntry", "exists", 15)


# ---------------------------------------------------------------- Duck.ai
def open_duckai_new_chat(ios):
    """Open Duck.ai from its in-app entry point and start a new chat. Needs the live duck.ai service."""
    ios.tap(ids(ios)["aichat"])
    ios.tap('label="New Chat"')
    ios.expect_url_contains("duck.ai", 15)


def send_duckai_prompt(ios, prompt):
    """iPhone uses the app's native input; iPad uses Duck.ai's own web input."""
    if ios.device == "iphone":
        ios.wait("id=AIChat.Toolbar.Button.Submit", "exists", 15)
        ios.type("-", prompt)
        ios.wait("id=AIChat.Toolbar.Button.Submit", "enabled", 5)
        return ios.tap("id=AIChat.Toolbar.Button.Submit")
    box = 'label="Ask anything privately" nth=0'
    ios.wait(box, "exists", 15)
    ios.type(box, prompt)
    ios.wait('role=button label="Ask"', "enabled", 5)
    return ios.tap('role=button label="Ask"')


def read_duckai_answer(ios, timeout=90, settle=2.0):
    """The last assistant answer, once streaming has stopped (text unchanged for `settle` seconds).

    Relies on Duck.ai's front end labelling each answer "Duck.ai said" (its own page text, not ours): if that wording
    changes this fails loudly, never passes. Polls quietly; the settled answer is logged to the transcript."""
    js = 'var b=document.body.innerText; var i=b.lastIndexOf("Duck.ai said"); return {t: i<0?"":b.slice(i+12).trim().slice(0,300)}'
    prev, since, last = None, None, ""
    end = time.time() + timeout
    while time.time() < end:
        res = ios.d.web.eval(js) or {}
        last = res.get("t", "") if isinstance(res, dict) else ""
        if last and last == prev and "Generating" not in last:
            since = since or time.time()
            if time.time() - since >= settle:
                return ios._log("duck.ai answer", [], lambda: last)
        else:
            since = None
        prev = last
        time.sleep(0.5)
    raise Failed(f"Duck.ai answer did not settle within {timeout}s", last=last)


# ---------------------------------------------------------------- Duck.ai contextual chat (features/duck-ai-contextual.md)
import re  # noqa: E402  (kept with the block that uses it)

# Flags every contextual proof pins: the feature is off by default, the iPad entry is the tabs-bar menu button and the
# chat docks beside the page, iPhone uses the floating native input, and page attachment is manual (the default).
CONTEXTUAL_FLAGS = {"contextualDuckAIMode": True, "aiChatChromeShortcutIPad": True, "aiChatChromeMenuButtonIPad": True,
                    "ipadAIChatContextSidebar": True, "aiChatContextualUnifiedToggleInput": True,
                    "aiChatContextualFloatingInput": True, "aiChatAutoAttachContextByDefault": False}
CONTEXTUAL_INPUT = "role=textview id=searchEntry"   # shares `searchEntry` with the address bar (a search field)
CONTEXTUAL_IDS = {
    # iPhone: the sheet's Fire sits beside the collapsed input and shares its label with the toolbar Fire button, which
    # stays in the tree under the sheet (not hittable) and is listed second.
    "iphone": dict(fire='label="Clear Tabs and Data" nth=0', expand='label="Open In 24"'),
    "ipad": dict(fire='label="Fire 24"', expand='label="Expand 24"'),
}
_TREE_LINE = re.compile(r"^\s*(\d+) id=.*? label=(['\"])(.*?)\2 value=")


def open_contextual_chat(ios):
    """On a web page with no chat yet: the Duck.ai entry button, then Ask About Page, which attaches the page.
    iPhone opens the floating input over the page (the sheet comes with the first prompt); iPad opens the sheet."""
    ios.tap(ids(ios)["aichat"])
    ios.tap('label="Ask About Page"')
    return ios.wait("id=AIChat.ContextChip.AttachedTitle", "exists", 15)


def attached_context(ios):
    """The title of the page attached to the next prompt, or None when nothing is attached."""
    matches = ios.find("id=AIChat.ContextChip.AttachedTitle")
    return matches[0]["label"] if matches else None


def send_contextual_prompt(ios, prompt):
    """Type into the contextual input and submit; ends with the sheet open (iPhone promotes the floating input)."""
    ios.tap(CONTEXTUAL_INPUT)   # iPad opens without focus in the input
    ios.type(CONTEXTUAL_INPUT, prompt)
    ios.wait("id=AIChat.Toolbar.Button.Submit", "enabled", 5)
    ios.tap("id=AIChat.Toolbar.Button.Submit")
    return ios.wait("id=AIChat.ContextualSheet", "exists", 20)


def _contextual_answer_text(ios):
    """Static texts after the last "Duck.ai said" heading in the native tree, up to the first button ("" if none)."""
    lines = ios.snapshot().get("tree", "").splitlines()
    heads = [i for i, line in enumerate(lines) if (m := _TREE_LINE.match(line)) and m.group(1) == "48"
             and m.group(3) == "Duck.ai said"]
    texts = []
    for line in lines[heads[-1] + 1:] if heads else []:
        m = _TREE_LINE.match(line)
        if m and m.group(1) == "9":
            break
        if m and m.group(1) == "48":
            texts.append(m.group(3))
    return " ".join(texts)


def read_contextual_answer(ios, timeout=90, settle=2.0):
    """The last answer in the sheet (model name first), once it has stopped changing for `settle` seconds.

    The web channel reads the tab, not the sheet, so this reads the sheet's chat from the native tree. Relies on Duck.ai's
    "Duck.ai said" heading (its own wording): if that changes this fails loudly, never passes."""
    prev, since, last = None, None, ""
    end = time.time() + timeout
    while time.time() < end:
        last = _contextual_answer_text(ios)
        if last and last == prev:
            since = since or time.time()
            if time.time() - since >= settle:
                return ios._log("contextual answer", [], lambda: last)
        else:
            since = None
        prev = last
        time.sleep(0.5)
    raise Failed(f"contextual answer did not settle within {timeout}s", last=last)


def fire_contextual_chat(ios):
    """Fire from the sheet and confirm Delete Chat: the sheet closes and this tab's chat is deleted."""
    ios.tap(CONTEXTUAL_IDS[ios.device]["fire"])
    ios.wait("id=alert.forget-data.confirm", "exists", 5)
    ios.shot("contextual-fire-confirm")
    ios.tap("id=alert.forget-data.confirm")
    return ios.expect_hidden("id=AIChat.ContextualSheet", 10)


def expand_contextual_chat(ios):
    """Move the sheet's chat to its own Duck.ai tab."""
    ios.tap(CONTEXTUAL_IDS[ios.device]["expand"])
    return ios.expect_url_contains("chatID=", 15)

"""Shared DuckDuckGo app steps for proofs: each one is a user action with the app's quirks handled once.

Every step uses only generic actions and the ids documented in ../../features/. Keep it that way: when the app gets
an XCUITest target, these port to Swift mechanically, from the feature map, not from this code.

A step that looks for something and doesn't find it raises with runner code NOT_FOUND (TIMEOUT when it waited), like
the driver does, so `prove --base` can take that miss for the base build's expected failure inside `on_base("fail")`.
"""
import ast
import json
import re
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
    raise Failed(f"none of {locators} present", runner=dict(code="NOT_FOUND"))


# ---------------------------------------------------------------- session and pages
def fresh_start(ios):
    """Known state: reinstalled app, onboarding skipped, pinned flags, default capture conditions (light, default text
    size, portrait, live status bar), one blank tab (or the proof's PROFILE), address bar not focused.
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
            raise Failed("tab-switcher button found, but no tab-count label right after it in the tree",
                         runner=dict(code="NOT_FOUND"))
    raise Failed("no tab-switcher button (Browser.Toolbar.Button.TabSwitcher) in the tree", runner=dict(code="NOT_FOUND"))


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
    # The first duck.ai load on a fresh iPad simulator sometimes fails with "Could not connect to the server"; a
    # reload loads it. Reload once and say so, so a run that needed it is visible in the report. The URL already
    # reads duck.ai while that first load is in flight, so "loaded" means the chat input is on screen.
    if ios.eventually("duck.ai loaded or failed to load", lambda: _duckai_load_state(ios), 20) == "failed":
        ios.note("duck.ai failed its first load (Could not connect to the server); reloaded once")
        tap_first_present(ios, ["id=Browser.OmniBar.Button.RefreshExternal", "id=Browser.OmniBar.Button.Refresh"])
        ios.eventually("duck.ai loaded after the reload", lambda: _duckai_load_state(ios) == "loaded", 20)
    ios.expect_url_contains("duck.ai", 15)


DUCKAI_LOAD_ERROR = 'label="Could not connect to the server."'
# Duck.ai's chat input: iPhone shows the app's native composer, iPad the page's own input box.
DUCKAI_INPUT = ["id=AIChat.Toolbar.Button.Submit", 'label="Ask anything privately" nth=0']


def _duckai_load_state(ios):
    if ios.exists(DUCKAI_LOAD_ERROR, 0.2):
        return "failed"
    return "loaded" if any(ios.exists(loc, 0.2) for loc in DUCKAI_INPUT) else None


def send_duckai_prompt(ios, prompt):
    """iPhone uses the app's native input; iPad uses Duck.ai's own web input."""
    if ios.device == "iphone":
        ios.wait("id=AIChat.Toolbar.Button.Submit", "exists", 15)
        ios.type("-", prompt)
        ios.wait("id=AIChat.Toolbar.Button.Submit", "enabled", 5)
        return ios.tap("id=AIChat.Toolbar.Button.Submit")
    # The box isn't focused in a chat opened in a second tab, and typing into it then changes nothing: tap it first.
    # The submit button is "Ask" until the user has accepted the terms (their first prompt), "Send" after.
    box = 'label="Ask anything privately" nth=0'
    ios.wait(box, "exists", 15)
    ios.tap(box)
    ios.type("-", prompt)
    submit = ios.eventually("Duck.ai submit enabled", lambda: next(
        (loc for loc in DUCKAI_SUBMIT if any(m.get("enabled") for m in ios.find(loc))), None), 5)
    return ios.tap(submit)


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
    raise Failed(f"Duck.ai answer did not settle within {timeout}s", last=last, runner=dict(code="TIMEOUT"))


# ---------------------------------------------------------------- Duck.ai: chat ids, history, deletion, storage
DUCKAI_SUBMIT = ['role=button label="Ask"', 'role=button label="Send"']
# The Fire button on a Duck.ai tab: iPhone has no id there, only this label; iPad keeps its toolbar id.
DUCKAI_FIRE = {"iphone": 'label="Clear Tabs and Data"', "ipad": "id=Browser.Toolbar.Button.Fire"}


def duckai_chat_id(ios, timeout=30):
    """The open chat's id: Duck.ai adds `chatID=<id>` to the tab's URL once the first prompt is sent."""
    url = ios.eventually("chat id in the URL", lambda: "chatID=" in (ios.page_url() or "") and ios.page_url(), timeout)
    return url.split("chatID=", 1)[1].split("&", 1)[0]


def new_duckai_chat_tab(ios):
    """Start another chat in a new tab, from a Duck.ai tab. iPhone: the chat header's New menu, then Chat (the
    address-bar Duck.ai button isn't on a Duck.ai tab). iPad: the tab bar's Duck.ai menu, then New Chat."""
    if ios.device == "iphone":
        ios.tap('label="New"')
        ios.tap('label="Chat"')
    else:
        ios.tap(ids(ios)["aichat"])
        ios.tap('label="New Chat"')
    ios.eventually("a new chat without a chat id", lambda: _is_empty_duckai_chat(ios.page_url() or ""), 15)


def duckai_history(ios):
    """Open chat history from a Duck.ai tab and return the chat titles it lists, newest first.
    iPhone: the native Chats sheet (chat header button "Recent chats"); rows have no ids, and each title follows its
    `Chat-24` icon in the tree; closed again with Close. iPad: Duck.ai's own web sidebar ("Show sidebar"); rows are
    the buttons between "Search chats" and "Settings & More"; left open (it covers the input, not the toolbar)."""
    if ios.device == "iphone":
        ios.tap('label="Recent chats"')
        ios.wait("id=Chats", "exists", 10)
        lines = ios.snapshot().get("tree", "").splitlines()
        titles = [_label(nxt) for line, nxt in zip(lines, lines[1:]) if "id='Chat-24'" in line]
        ios.tap('label="Close"')
        ios.wait("id=Chats", "hidden", 10)
    else:
        if not ios.exists('label="Search chats"', 1):
            ios.tap('label="Show sidebar"')
        ios.wait('label="Search chats"', "exists", 10)
        lines = ios.snapshot().get("tree", "").splitlines()
        start = next(i for i, line in enumerate(lines) if "label='Search chats'" in line)
        titles = []
        for line in lines[start + 1:]:
            if "label='Settings & More'" in line:
                break
            if line.strip().startswith("9 "):   # element type 9 is a button
                titles.append(_label(line))
    return ios._log("duck.ai history", [], lambda: titles)


def _is_empty_duckai_chat(url):
    return "duck.ai" in url and "chatID=" not in url


# Device.snapshot writes `label={label!r}`, so read the label back as the Python literal repr wrote: a title with an
# apostrophe comes out double-quoted (label="Mango's chat").
_LABEL = re.compile(r""" label=('(?:[^'\\]|\\.)*'|"(?:[^"\\]|\\.)*")""")


def _label(tree_line):
    m = _LABEL.search(tree_line)
    return ast.literal_eval(m.group(1)) if m else ""


def delete_current_duckai_chat(ios, timeout=180):
    """The Fire button on a Duck.ai tab offers only "Delete This Chat" (`Fire.Confirmation.Button.ThisTab`). It deletes
    that chat whatever the Data Clearing settings say, and the tab reloads an empty chat.
    Until the whole clear finishes, the app covers its window with an invisible overlay that takes the next tap (a
    user's tap just removes it), so every control reads as not hittable. That can last minutes on a loaded Mac: wait
    for the Fire button to be hittable again instead of tapping through it."""
    ios.tap(DUCKAI_FIRE[ios.device])
    ios.wait("id=Fire.Confirmation.Button.ThisTab", "visible", 10)
    ios.shot("fire-sheet")
    ios.tap("id=Fire.Confirmation.Button.ThisTab")
    ios.eventually("tab shows an empty chat", lambda: _is_empty_duckai_chat(ios.page_url() or ""), 15)
    ios.wait(DUCKAI_FIRE[ios.device], "visible", timeout)


DUCKAI_STORAGE_JS = """
const needles = %s, hits = {};
const look = (where, text) => { for (const n of needles) if (text && text.includes(n)) (hits[where] = hits[where] || []).push(n); };
const req = (r) => new Promise((ok, no) => { r.onsuccess = () => ok(r.result); r.onerror = () => no(r.error); });
for (const k of Object.keys(localStorage)) look('localStorage:' + k, localStorage.getItem(k));
for (const info of await indexedDB.databases()) {
  const db = await req(indexedDB.open(info.name));
  for (const s of Array.from(db.objectStoreNames)) {
    const keys = await req(db.transaction(s).objectStore(s).getAllKeys());
    const rows = await req(db.transaction(s).objectStore(s).getAll());
    look('indexedDB:' + info.name + '/' + s, JSON.stringify(keys) + JSON.stringify(rows));
  }
  db.close();
}
const ns = navigator.duckduckgo.createMessageBridge('duckAiNativeStorage');
const chats = (await ns.request('getAllChats', {})).chats || [];
look('native:chats', JSON.stringify(chats));
look('native:files', JSON.stringify(await ns.request('listFiles', {})));
const entries = (await ns.request('getAllEntries', {})).entries || {};
const tombstones = entries.locallyDeletedChatIds || [];
delete entries.locallyDeletedChatIds;
look('native:entries', JSON.stringify(entries));
return {chats: chats.map(c => ({id: c.chatId, title: c.title || ''})), tombstones, hits};
"""


def duckai_storage(ios, needles):
    """Read Duck.ai's storage from a duck.ai page: the chats in native storage (id, title), the
    `locallyDeletedChatIds` tombstones, and where any of `needles` (chat ids, prompt text) appears: localStorage, every
    IndexedDB store, and native storage's chats, files and entries (tombstones left out). Native storage is read
    through the page bridge Duck.ai itself uses (`duckAiNativeStorage`), so the tab must show duck.ai."""
    return ios.eval(DUCKAI_STORAGE_JS % json.dumps(list(needles)))


# ---------------------------------------------------------------- Duck.ai contextual chat (features/duck-ai-contextual.md)

# Flags every contextual proof pins: the feature is off by default, the iPad entry is the tabs-bar menu button and the
# chat docks beside the page, iPhone uses the floating native input with Fire beside it (`aiChatTabHandoffImprovements`,
# which CONTEXTUAL_IDS["iphone"]["fire"] relies on), and page attachment is manual (the default).
# Proofs copy it (`FLAGS = {**steps.CONTEXTUAL_FLAGS}`) so an override never leaks into another proof in the same run.
CONTEXTUAL_FLAGS = {"contextualDuckAIMode": True, "aiChatChromeShortcutIPad": True, "aiChatChromeMenuButtonIPad": True,
                    "ipadAIChatContextSidebar": True, "aiChatContextualUnifiedToggleInput": True,
                    "aiChatContextualFloatingInput": True, "aiChatTabHandoffImprovements": True,
                    "aiChatAutoAttachContextByDefault": False}
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


def _contextual_answer_texts(ios):
    """Static texts after the last "Duck.ai said" heading in the native tree, up to the first button ([] if none)."""
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
    return texts


def read_contextual_answer(ios, timeout=90, settle=2.0):
    """The last answer in the sheet (model name first), once it has stopped changing for `settle` seconds.

    The web channel reads the tab, not the sheet, so this reads the sheet's chat from the native tree. Relies on Duck.ai's
    "Duck.ai said" heading (its own wording): if that changes this fails loudly, never passes. Never settles on the model
    name alone or while Duck.ai shows "Generating"."""
    prev, since, last = None, None, ""
    end = time.time() + timeout
    while time.time() < end:
        texts = _contextual_answer_texts(ios)
        last = " ".join(texts)
        if len(texts) > 1 and last == prev and "Generating" not in last:
            since = since or time.time()
            if time.time() - since >= settle:
                return ios._log("contextual answer", [], lambda: last)
        else:
            since = None
        prev = last
        time.sleep(0.5)
    raise Failed(f"contextual answer did not settle within {timeout}s", last=last, runner=dict(code="TIMEOUT"))


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


# ---------------------------------------------------------------- Sync & Backup
BROWSING_MENU = {"iphone": "id=Browser.Toolbar.Button.Menu", "ipad": "id=Browser.OmniBar.Button.BrowsingMenu"}
PASSCODE_FIELD = 'app=springboard id="Passcode field"'
CAMERA_PROMPT = 'app=springboard role=alert contains="access your camera"'
SYNC_DEV_PROFILE = {"debug.syncEnvironment": "Development"}
SYNC_FLAGS = {"syncImprovedPairingFlow": True, "syncCanUseV2ConnectFlow": True, "syncCanShowV2ConnectCode": True}


def open_settings(ios):
    """Browsing menu, then Settings. On iPad a tap while the menu is still animating in can do nothing, so it taps
    Settings again if the Settings screen hasn't appeared."""
    dismiss_address_bar(ios)
    ios.tap(BROWSING_MENU[ios.device])
    ios.tap('role=button label="Settings"')
    if not ios.exists('role=button label="Done"', 5):
        ios.tap('role=button label="Settings"')
    ios.wait('role=button label="Done"', "visible", 10)


def open_sync_settings(ios):
    """Settings, then the Sync & Backup row (its label carries the state: "Sync & Backup, Off" or ", On")."""
    open_settings(ios)
    ios.scroll_to('contains="Sync & Backup,"')
    ios.tap('role=button contains="Sync & Backup,"')
    ios.wait('label="Sync & Backup"', "exists", 10)


def unlock_device(ios, timeout=5):
    """Answer the system passcode sheet ("Unlock device to set up Sync & Backup") if it appears; the simulator takes
    any passcode. One unlock stays valid for a short while, so a later gated step may not ask: returns whether it did.
    The sheet belongs to SpringBoard, so its locators carry `app=springboard`."""
    if not ios.exists(PASSCODE_FIELD, timeout):
        return False
    ios.type(PASSCODE_FIELD, "0000")
    ios.tap("app=springboard id=Done")
    ios.expect_hidden(PASSCODE_FIELD, 10)
    return True


def allow_camera(ios):
    """Allow the camera prompt the code scanner raises, as often as it comes back (it can show twice in a row).
    The simulator has no camera, so a code is always entered through Enter Code."""
    for _ in range(3):
        if not ios.exists(CAMERA_PROMPT, 4):
            return
        try:
            ios.alert("accept", button="Allow")
        except Failed as e:
            if ((getattr(e, "extra", None) or {}).get("runner") or {}).get("code") != "ALERT_STILL_SHOWN":
                raise


def answer_alert(ios, button, timeout=10):
    """Press `button` on the alert showing. A SwiftUI alert can still be up when the runner checks right after the
    press, so wait for it to go and press again only if it stays."""
    try:
        return ios.alert("accept", button=button)
    except Failed as e:
        if ((getattr(e, "extra", None) or {}).get("runner") or {}).get("code") != "ALERT_STILL_SHOWN":
            raise
    try:
        ios.wait("role=alert", "hidden", timeout)
    except Failed:
        ios.alert("accept", button=button)


def copy_in_app(ios, text):
    """Put `text` on the clipboard from inside the app, through Settings > All debug options > Sync > "Paste and Copy
    Recovery Code". Text written from the host (`simctl pbcopy`) never reaches the app's Paste Sync Code. Ends back on
    the Settings list."""
    open_settings(ios)
    ios.scroll_to('label="All debug options"')
    ios.tap('role=button label="All debug options"')
    ios.scroll_to('role=button label="Sync"')
    ios.tap('role=button label="Sync"')
    ios.tap('label="Paste and Copy Recovery Code"')
    ios.type("-", text)
    ios.alert("accept", button="Copy")
    ios.tap("id=BackButton")
    ios.tap("id=BackButton")


def clipboard(ios):
    """The simulator's clipboard, read from the host (read-back only)."""
    p = env.run(["xcrun", "simctl", "pbpaste", ios.d.udid])
    return p.stdout.strip()


def turn_off_and_delete_server_data(ios):
    """From the synced Sync & Backup screen: Turn Off Sync & Backup, "Also delete server data?" on, Turn Off and Delete
    Server Data, Permanently Delete. Ends on the screen with sync off. Refuses unless the screen shows the
    "Dev environment" badge: it never deletes an account on the production server."""
    if not ios.exists('label="Dev environment"', 3):
        raise Failed("refusing to delete Sync server data: the Sync & Backup screen doesn't show \"Dev environment\"")
    ios.scroll_to('role=button label="Turn Off Sync & Backup"')
    ios.tap('role=button label="Turn Off Sync & Backup"')
    unlock_device(ios)
    ios.wait("id=DeleteServerDataToggle", "visible", 10)
    if ios.get("id=DeleteServerDataToggle") != "1":
        ios.tap("id=DeleteServerDataToggle")
    ios.wait("id=TurnOffAndDeleteServerDataButton", "visible", 10)
    ios.tap("id=TurnOffAndDeleteServerDataButton")
    ios.wait('role=alert label="You Can’t Undo This Action."', "exists", 10)
    answer_alert(ios, "Permanently Delete")
    ios.wait('role=button label="I Have a Recovery Code"', "visible", 30)


def close_settings(ios):
    """From Settings or a screen one level inside it (Sync & Backup): back, then Done, to the browser."""
    if ios.exists("id=BackButton", 1):
        ios.tap("id=BackButton")
    ios.wait('role=button label="Done"', "visible", 10)
    try:
        ios.tap('role=button label="Done"')
    except Failed as e:
        if ((getattr(e, "extra", None) or {}).get("runner") or {}).get("code") != "MATCHES_CHANGED":
            raise
        ios.tap('role=button label="Done"')
    ios.wait("id=searchEntry", "exists", 10)


def recover_with_code(ios, code):
    """From the browser, with sync off: I Have a Recovery Code > Recover Synced Data > Enter Code > Paste Sync Code with
    `code`. Returns True on "Sync & Backup enabled" and False on "Sync failed.", which also covers server and network
    errors, so False alone doesn't prove the account is gone."""
    copy_in_app(ios, code)
    ios.scroll_to('contains="Sync & Backup,"')
    ios.tap('role=button label="Sync & Backup, Off"')
    ios.tap('role=button label="I Have a Recovery Code"')
    ios.tap('role=button label="Recover Synced Data"')
    unlock_device(ios, 10)
    allow_camera(ios)
    ios.tap('role=button label="Enter Code"')
    ios.tap('role=button label="Paste Sync Code"')
    end = time.time() + 60
    while time.time() < end:
        if ios.exists("id=SyncSuccessTitle", 1):
            return True
        if ios.exists('role=alert label="Sync failed."', 1):
            ios.alert("accept", button="Got It")
            return False
    raise Failed("recovery showed neither the success screen nor \"Sync failed.\" within 60 s",
                 runner=dict(code="TIMEOUT"))

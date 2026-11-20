# Duck.ai: full-tab chat

The user opens Duck.ai in its own tab, starts a new chat, sends a prompt and reads the streamed answer. They can
reopen earlier chats from chat history, start another chat, attach images and files, and delete a chat. iPhone uses
the app's native input and a native chat history sheet; iPad uses Duck.ai's own web input and web sidebar. Duck.ai in
a sheet over a web page is [contextual chat](./duck-ai-contextual.md).

## Sub-features

- `duckai-open` an entry point opens Duck.ai in a tab.
- `duckai-new-chat` New Chat starts an empty chat; from a chat tab it opens in a new tab.
- `duckai-send` a typed prompt is submitted and an answer streams back; the tab's URL gains `chatID=<id>`.
- `duckai-history` chat history lists earlier chats by title; the user opens, searches and reopens them.
- `duckai-swipe-new-chat` (iPhone) pulling up past the end of a chat starts a new chat.
- `duckai-attach` the chat input attaches photos, images and files.
- `duckai-delete` deleting a chat removes it from history and from Duck.ai's storage; other chats stay.

## How to get to it (user POV)

Ids come from source. "Driven" means a live run on that device opened Duck.ai through it; the rest are recorded
with what they need.

- Duck.ai button, then New Chat or Chats. Driven on both.
  - iPhone: `Browser.OmniBar.Button.AIChat` on the address bar and the new-tab page. On a blank tab its menu has
    "New Chat" and "Chats"; its "Ask About Page" items belong to [contextual chat](./duck-ai-contextual.md).
  - iPad: `Browser.TabsBar.AIChatMenuButton` (label "Open Duck.ai"), with the same menu. It shows only when the
    Duck.ai settings' "Tab Bar" toggle, `aiChatChromeShortcutIPad` (on by default) and the internal-only
    `aiChatChromeMenuButtonIPad` flag are all on; debug builds have all three. Without the menu flag the tab bar can
    show the older `Browser.TabsBar.AIChatChip` instead.
  - "Chats" opens history: the native Chats sheet on iPhone (empty, it offers "Open Duck.ai"), Duck.ai's web sidebar
    on iPad.
- Tab switcher Duck.ai button: `TabSwitcher.Button.DuckChat`, or the icon label `Ai Chat 24` in the switcher layout
  without ids. On iPhone it opens a menu: "New Chat", recent chats once there are some, "View all chats". Driven on
  both.
- Browsing menu: iPhone "New Chat", iPad "Duck.ai". No ids; use `role=button label=…`, because the iPad tab bar
  also shows the text "Duck.ai". Driven on both.
- Address bar: typing `duck.ai` and submitting opens it like any site, and the tab becomes a Duck.ai tab. Driven on
  both (iPhone by hand, see Gotchas for the keyboard intro that got in the way of the proof).
- iPad keyboard: ⌥⌘N opens a new chat. Driven. The iPad menu bar's Duck.ai menu also has New Voice Chat, New Image
  Chat, Recent Chats and Delete All Chats; not driven.
- Deep link `ddgOpenAIChat://`: what the search widget's AI icon, the lock-screen and Control Center widgets and the
  Siri intent open. Drive it with `xcrun simctl openurl <udid> ddgOpenAIChat://`, then
  `ios.alert("accept", button="Open")` for iOS's "Open in DuckDuckGo?". Driven on both; the widgets themselves
  aren't (they need the home or lock screen set up by hand).
- Search / Duck.ai toggle: iPhone `AddressBar.Button.DuckAI` in the focused address bar, iPad
  `Browser.OmniBar.Button.ModeToggle.AIChat`. Not on a fresh install: it needs Duck.ai settings' "Search & Duck.ai"
  turned on first (Maestro's `.maestro/shared/set_search_and_duckai.yaml` does it through Settings). Not driven.
- Home-screen quick action "Duck.ai" (long-press the app icon): not driven here: the verify-ios runner drives only
  the app, not SpringBoard. `iOS/AtbUITests/ApplicationShortcutItemsUITests.swift` checks it through SpringBoard.
- Settings > AI Features > "Duck.ai Settings" (`Settings.AIFeatures.DuckAISettings`) opens Duck.ai's own settings
  page; not driven.
- From a chat: iPhone header `New`, then `Chat` (new tab), and `Recent chats` (history); iPad Duck.ai's sidebar
  ("Show sidebar", then "New Chat"). Driven by t12.
- iPhone only, behind the internal-only flag `aiChatSwipeUpNewChat`: pull up past the end of a chat for a new chat.
  Not driven (see Reaching states).

## Driving it with verify-ios

Preconditions:

- `steps.fresh_start(ios)`: a run must not start on a previous run's Duck.ai tab.
- The proof declares `LIVE = ["duck.ai"]`: it needs the real network and the live Duck.ai service.
- A proof that reads storage or history pins where chats live:
  `FLAGS = {"aiChatNativeStorage": True, "aiChatNativeDataAccess": True}`, as production ships. With them off, chats
  live only in the web page's IndexedDB and the iPhone Chats sheet has nothing to read.
- A proof that deletes a chat also pins `fireButtonRefinements: True` and `fireMode: True` (both on by default,
  remote; on iOS 17+ the first needs the second, which the app reads once at launch). Together they give a Duck.ai
  tab its own "Delete This Chat" sheet. If either is off, the Fire button shows "Delete All" and, below it, "Delete This
  Tab" (same id, `Fire.Confirmation.Button.ThisTab`).

### Steps

- **Open and start a chat.** `steps.open_duckai_new_chat(ios)`: taps the device's Duck.ai button, then
  `label="New Chat"`; proof: `ios.expect_url_contains("duck.ai")`.
- **Send.** `steps.send_duckai_prompt(ios, prompt)`. iPhone: waits for `id=AIChat.Toolbar.Button.Submit`, types into
  the focused native input (`ios.type("-", …)`), waits for Submit to be enabled, taps it. iPad: taps
  `label="Ask anything privately" nth=0`, types into it, then taps whichever of `Ask` and `Send` is enabled.
- **Read the answer.** `steps.read_duckai_answer(ios)` reads the text after the last "Duck.ai said" once it has stopped
  changing for 2 s. Proof: it contains the expected content (`ios.check`).
- **Chat id.** `steps.duckai_chat_id(ios)` waits for `chatID=` in the tab's URL and returns it.
- **Another chat.** `steps.new_duckai_chat_tab(ios)` from a chat tab: iPhone taps the chat header's `New`, then
  `Chat`; iPad taps the tab bar's Duck.ai menu, then `New Chat`. Both open a new tab.
- **History.** `steps.duckai_history(ios)` returns the listed chat titles. iPhone: header button `Recent chats` opens
  the native sheet (`id=Chats`); each title follows its `Chat-24` icon; `Close` closes it. iPad: `Show sidebar` opens
  Duck.ai's sidebar; titles are the buttons between `Search chats` and `Settings & More`.
- **Delete.** `steps.delete_current_duckai_chat(ios)`: the Fire button on the chat tab (iPhone
  `label="Clear Tabs and Data"`, iPad `id=Browser.Toolbar.Button.Fire`) opens "Delete this chat?";
  `id=Fire.Confirmation.Button.ThisTab` deletes it and the tab reloads an empty chat.
- **Storage.** `steps.duckai_storage(ios, needles)` runs on a duck.ai page and returns the chats in native storage
  (id, title), the `locallyDeletedChatIds` tombstones, and every store where a needle appears: localStorage, each
  IndexedDB store, and native storage's chats, files and entries.
- Worked proofs: `examples/t8_duckai.py` (send and read), `examples/t12_duckai_delete_chat.py` (delete: history and
  storage before and after, a second chat that must survive).

### Reaching states

- **A new chat** (`duckai-open`, `duckai-new-chat`): `fresh_start`, then `open_duckai_new_chat`. Answers come from
  the live service and vary between runs: prompt for something checkable ("reply with exactly the word …") and check
  containment, never equality.
- **Earlier chats** (`duckai-history`, `duckai-delete`): only the UI can create chats today, so the proof sends one
  prompt per chat it needs (about 10 s each). Titles are generated after the answer; read them with
  `duckai_storage` before matching history rows, and use prompts that give different titles.
- **History search and reopen**: from the Chats sheet (iPhone), `Search` filters by title; tapping a row opens that
  chat in the tab (driven on iPhone). On iPad, `Search chats` in the sidebar filters the list, and a result's label
  is "<title> <date>". Tapping a result is not driven yet: `find` lists it, but the runner's tap fails with "No
  matches found for Element at index …" every time, even by exact label. Rows have no ids on either device.
- **An image attached** (iPhone): a new chat's input is focused, so `Attach` shows; then `Add Image`, a sample photo
  (`id=PXGGridLayout-Info nth=0`, the simulator's built-in library) and `Done`. Proof: the
  `AIChat.Footer.Card.attachmentPrivacy` card and Submit enabled with no text. After an answer the input collapses
  and hides `Attach` until it is focused again. iPad uses the web input's `Add images or PDFs`.
- **Paid models**: blocked. Debug builds use the staging subscription backend, so a paid-model state needs a staging
  subscription account, which this skill doesn't have yet.
- **Swipe for a new chat**: blocked by the driver. The gesture needs a slow drag that starts at the bottom of a chat
  and passes 150 pt before release; `ios.swipe` is a fast fling and doesn't arm it. It needs a press-and-drag action
  in the runner.
- **A custom front-end URL**: the debug menu's AI Chat screen, "Set Custom AI Chat URL", stored in UserDefaults
  `aichat.debug.customURL` (a launch argument can set it). Any path on that host counts as Duck.ai; only a
  different host leaves it. No proof uses this yet.
- **Data Clearing "Delete Duck.ai Chats"** (off by default) decides whether Fire's "Delete All", from any tab, also
  deletes chats; "Delete This Chat" and "Delete This Tab" ignore it.
- **Other ways to delete chats**, not driven: the iPhone Chats sheet (swipe a row for its fire icon, "Select Chats"
  then Delete, or its fire button for all), the fire button on a recent chat listed under the Duck.ai input, the
  iPad Duck.ai sidebar's fire icons (one per chat, one beside "Chats"), and the iPad menu bar's "Delete All Chats".

### Already covered elsewhere

XCUITests in `iOS/AtbUITests` (`iOS/UITests` has none):

- `FloatingUIXCUITests.swift`: the address-bar Duck.ai button's menu ("New Chat" and "Chats" on a blank tab, "Ask
  About Page" on a page), and a custom front-end URL treated as Duck.ai.
- `ApplicationShortcutItemsUITests.swift`: the home-screen quick action "Duck.ai" exists.
- `SitePermissionsXCUITests.swift`: Duck.ai dictation and voice chat losing microphone access (the input's mic
  permission, not the chat tab).

Maestro flows in `.maestro/`:

- `release_tests/ai-chat.yaml`, `ai-chat-ipad.yaml`, `ai-chat-iphone-ipad-flag.yaml`, `ai-chat-settings.yaml`: opening
  a chat from the new-tab page and the tab switcher, the Duck.ai setting off, iPad toggles, the settings row.
- `unified_toggle_input/test_chat_tab_*.yaml`, `test_ai_chat_tab_header.yaml`, `test_enter_chat_from_web.yaml`: the
  iPhone chat tab's header, toolbar, model picker, New button and sending a prompt.
- `ipad_duckai/ipad_duckai_bar_controls.yaml`, `browser_features/duckai_chrome_shortcut_*.yaml`: iPad omnibar
  controls and the tab bar Duck.ai button and menu.

None covers swipe for a new chat, attachments or deleting a chat; prove those here.

## Gotchas

- `LIVE`: every proof here talks to the live Duck.ai service and its web front end. The front end ships separately
  from the app and changes without an app release: its labels ("Duck.ai said", "Ask anything privately", "Send",
  "Show sidebar") are its own, so a front-end change can break a step. Steps that depend on them fail loudly, never
  pass silently.
- Flags: pin what the proof depends on. Production keeps chats in native storage (`aiChatNativeStorage`,
  `aiChatNativeDataAccess`); with the live configuration a debug build may or may not have them. `aiChatKeepSession`
  can't be pinned: the app ignores a local override for it.
- Answers stream: reading too early gives a partial answer; `read_duckai_answer` waits for it to settle.
- iPhone and iPad have **different inputs**: `AIChat.Toolbar.Button.Submit` (native) vs `Ask anything privately`
  (web). The web submit is "Ask" until the user accepts the terms with their first prompt, then "Send". In a chat
  opened in a second tab the web input isn't focused, and typing into it changes nothing until it is tapped.
  `send_duckai_prompt` handles all of this.
- `Ask anything privately` matches more than once on iPad; use `nth=0`. Duck.ai's open sidebar covers it.
- On a Duck.ai tab the iPhone toolbar changes: the Fire button is `label="Clear Tabs and Data"` (no id) and the tab
  switcher is `label="Tab Switcher"`, so `steps.tab_count` and `steps.fire` don't work there.
- After "Delete This Chat" (and any manual Fire), an invisible overlay covers the window until clearing finishes, which
  takes minutes on a loaded Mac; every control reads as not hittable. A user's tap removes it early and fires a
  pixel. `delete_current_duckai_chat` waits it out.
- Deleting a chat leaves its id in native storage's `locallyDeletedChatIds` entry on purpose: Duck.ai's web app reads
  it to reconcile deletions. Prove "no trace" against the chat's content (its record, files and prompt text), and
  report the tombstone.
- On iPhone a fresh simulator can show iOS's "slide to type" intro over the keyboard; while it shows, typing with
  `submit=True` changes nothing (`NO_EFFECT`). Tap `role=button label="Continue"`, then type a newline
  (`ios.type("-", "\n")`) to submit.
- The first duck.ai load on a fresh iPad simulator sometimes fails with "Could not connect to the server";
  `open_duckai_new_chat` reloads once and notes it.
- Judge reachability from the app, not from a host-side request: the host's sandbox can refuse connections the
  simulator makes fine. If New Chat never loads `duck.ai`, check the network before calling it a product bug.

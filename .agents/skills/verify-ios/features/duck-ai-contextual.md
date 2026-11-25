# Duck.ai: contextual chat

On a web page, the user opens Duck.ai over the page instead of in a new tab, with the page attached as context for
the prompt. The chat lives with that tab: closing it and tapping Duck.ai again reopens it, Fire from the chat deletes
it, and expand moves it to its own tab. Duck.ai in its own tab is [full-tab chat](./duck-ai-tab.md).

## Sub-features

- `ctx-open` on a web page, an entry point opens the contextual chat: the floating input over the page on iPhone, the
  sheet on iPad.
- `ctx-attach-manual` Ask About Page attaches the current page; the chip shows its title and can be removed. Manual is
  the default.
- `ctx-attach-auto` with "Automatically Send Content" on, the page is attached without asking.
- `ctx-reattach` after the tab navigates to another page: with auto on, the new page is attached again; with it off,
  reopening offers a dashed "Ask About Page" chip instead.
- `ctx-send` a prompt sent from the contextual input opens the sheet (iPhone) and the answer streams into it.
- `ctx-expand` expand, or a tap on the sheet's title (`AIChat.ContextualSheet.TitleButton`), moves the chat to its own
  Duck.ai tab and empties the sheet.
- `ctx-close` close hides the sheet and keeps the chat until a session timer runs out; until then the Duck.ai button
  reopens it directly.
- `ctx-fire` Fire from the sheet asks "Delete this chat?", then closes the sheet and deletes this tab's chat. The page
  and other tabs stay.

## How to get to it (user POV)

Driven live on both devices unless marked otherwise.

- **Duck.ai button, then Ask About Page.** iPhone: the address bar's Duck.ai button (`Browser.OmniBar.Button.AIChat`).
  iPad: the tabs-bar Duck.ai button (`Browser.TabsBar.AIChatMenuButton`, label "Open Duck.ai"). On a web page with no
  chat yet, either one opens a menu: New Chat (a full-tab chat), Ask About Page, Chats. Ask About Page opens the
  floating input on iPhone and the sheet on iPad, with the page attached. Once the tab has a chat, the same button
  reopens the sheet directly, and taps it closed again. On a narrow iPad window the address-bar Duck.ai button carries
  the same menu (not driven).
- **Same menu, other page kinds** (from source, not driven). On a search results page the second item is "Continue in
  Duck.ai": it opens the contextual chat and sends the search query. On a PDF it is "Ask About Document". Prerequisite:
  a DuckDuckGo search or a PDF in the tab; the fixture is neither.
- **Text selection, Ask Duck.ai** (iPhone only). Long-press page text, then `role=menuitem label="Ask Duck.ai"` in the
  edit menu. It attaches the selection instead of the page, and offers selection suggestions such as
  `summarize-selection`. With no chat yet it opens the floating input; with one it opens the sheet. Needs
  `aiChatTextActions` and `aiChatContextualUnifiedToggleInput` pinned on and Duck.ai enabled; hidden on Duck.ai tabs and
  absent on iPad.
- **iPad tabs-bar chip, sheet half** (from source, not driven). `Browser.TabsBar.AIChatChip.SheetToggleButton`
  ("Toggle Duck.ai sheet") toggles the sheet without Ask About Page, so the page is attached only in auto mode.
  Prerequisite: `aiChatChromeShortcutIPad` on, `aiChatChromeMenuButtonIPad` off (the menu button replaces the chip),
  the Tab Bar shortcut on, and the chip's sheet half shown (Duck.ai shortcut settings, or the chip's long-press menu).
- **iPad menu bar, Open Recent Chat** (from source, not driven). For a chat that lives in a tab's sheet, it selects
  that tab and opens the sheet. Prerequisite: a hardware-keyboard menu bar and an earlier contextual chat.
- **"Automatically Send Content" setting** (from source, not driven): native Settings > AI Features, Duck.ai section,
  shown only while Duck.ai is enabled and contextual mode is available. It switches between manual and auto
  attachment. Until the user toggles it, its value follows the `aiChatAutoAttachContextByDefault` flag. The iPhone
  website browsing menu's "Duck.ai Settings" opens duck.ai's own web settings in a new tab, not this screen.
- Not entry points: the browsing menu's Duck.ai and New Chat open a full-tab chat; no long-press link item or keyboard
  shortcut opens the contextual chat.

## Driving it with verify-ios

Preconditions:

- `FLAGS = {**steps.CONTEXTUAL_FLAGS}`, a copy so an override stays in its own proof. `contextualDuckAIMode` is off by
  default; the set also pins the iPad tabs-bar menu button and docked chat (`ipadAIChatContextSidebar`), the iPhone
  floating native input, Fire beside the iPhone's collapsed input (`aiChatTabHandoffImprovements`), and manual
  attachment, so the paths below are the ones a run gets.
- `steps.fresh_start(ios)`, then `steps.open_fixture(ios, token)`: a web page with a known title ("verify-ios
  fixture") to attach.
- `LIVE = ["duck.ai"]`: sending needs the live Duck.ai service.

Steps:

- **Open with the page attached.** `steps.open_contextual_chat(ios)`: entry button, Ask About Page, waits for
  `AIChat.ContextChip.AttachedTitle`. Proof: `steps.attached_context(ios)` is the page's title (`None` when nothing
  is attached). Remove: `AIChat.ContextChip.RemoveButton`.
- **Send.** `steps.send_contextual_prompt(ios, prompt)`: taps and types into `role=textview id=searchEntry`, taps
  `AIChat.Toolbar.Button.Submit` once enabled, waits for `AIChat.ContextualSheet`.
- **Read the answer.** `steps.read_contextual_answer(ios)` reads the sheet's last answer from the native tree once it
  has settled (model name first). `steps.read_duckai_answer` reads the tab, not the sheet.
- **Close.** `AIChat.ContextualSheet.CloseButton`. Proof: the sheet is hidden, and the Duck.ai button reopens it with
  the chat.
- **Fire.** `steps.fire_contextual_chat(ios)`: the sheet's Fire, confirm `alert.forget-data.confirm` ("Delete Chat"),
  waits for the sheet to hide. Proof: the tab still shows the page, and the Duck.ai button offers its menu again (no
  chat to reopen).
- **Expand.** `steps.expand_contextual_chat(ios)`: proof is a Duck.ai tab whose URL has `chatID=`.
- Worked proof: `examples/t11_duckai_contextual.py` (open, attach, send, answer, Fire, a second chat, expand).

Reaching each state:

- Manual attachment: the default with `CONTEXTUAL_FLAGS`. Auto attachment:
  `FLAGS = {**steps.CONTEXTUAL_FLAGS, "aiChatAutoAttachContextByDefault": True}` (the setting follows it until toggled).
- A chat to reopen, close, Fire or expand: send one prompt first.
- Re-attach after navigation: send, close the sheet, follow the fixture's `external link` to `target.html` (title
  "verify-ios target"), then tap the Duck.ai button. With auto, `attached_context` is "verify-ios target" (seen on both
  devices). With manual, the iPhone sheet shows `AIChat.ContextChip.Suggested` ("Ask About Page") instead (seen on
  iPhone).
- The chat surviving a close: Debug > "Contextual Session Timer" shortens the timer after which a closed chat resets;
  no proof sets it.
- A selection instead of the page: the text-selection entry above, iPhone only.

Blocked, and why:

- **Page content reaching the model, from the fixture.** On the local fixture the chip shows the page attached, but the
  sent prompt has no "Page content from …" line and the model answers that it can't see the page (both devices). On
  https://example.com the same flow shows `label="Page content from"` and the page title under the prompt, and the
  answer uses the page. Serving the fixture as `localhost` instead of `127.0.0.1` changes nothing. Candidate causes,
  not settled: a local host, or plain http. Proofs from the
  fixture prove the chip, not delivery; record delivery with `ios.unverified`. Don't make a proof depend on a public
  site to get it.
- **Exact answers.** Answers come from a live model and vary; check for one requested word, never a whole answer.
- **Paid models and their states** need a signed-in staging subscription: not reachable here.
- **A custom Duck.ai front end** (Debug > AI Chat > Custom URLs). The sheet keeps only pages whose scheme and host match
  the custom URL; others open in a browser tab. The path is not compared
  (`SharedPackages/AIChat/Sources/AIChat/iOS/PublicAPI/AIChatDebugSettingsHandling.swift:93-102`), so a wrong host or
  scheme ejects the page, a wrong path does not. No proof sets it.

Already covered elsewhere, so a proof needn't repeat it:

- XCUITest `iOS/AtbUITests/FloatingUIXCUITests.swift` (`testAddressBarButtonMenus`): the address-bar menu's items on
  the new-tab page and on a web page.
- Maestro, `.maestro/browser_features/`: `duckai_chrome_shortcut_contextual_sheet_toggle.yaml` (iPad: Ask About Page
  opens the sheet, close returns the menu), `duckai_chrome_shortcut_menu_actions.yaml` (iPad: Ask About Page only on
  web pages).
- Maestro, `.maestro/unified_toggle_input/` (iPhone): `test_contextual_immediate_uti_pre_submit_context.yaml` (auto:
  remove, re-attach after navigation, promotion to the sheet), `..._pre_submit_toolbar.yaml` (manual attach before
  submit), `..._manual_context_clears_after_navigation.yaml` and `..._manual_context_clears_after_post_submit_navigation.yaml`,
  `test_contextual_web_uti_auto_attach_regression.yaml` and `..._manual_attach_regression.yaml` (the older web input).
  Their `assertNotVisible` checks on `AIChat.ContextChip.Placeholder` prove nothing: no view has that id.
  `test_uti_multiline_contextual.yaml` reaches Duck.ai through the browsing menu, which opens a full-tab chat.

## Gotchas

- **iPhone and iPad differ.** iPhone: Ask About Page opens a floating input over the page with the keyboard up; the
  sheet appears only after the first prompt. iPad: the sheet opens at once, docked beside the page
  (`ipadAIChatContextSidebar`; without it the sheet is modal, not driven), without focus in the input (tap it before
  typing). Fire is `Fire 24` in the iPad header and `Clear Tabs and Data` beside the iPhone's
  collapsed input; expand is `Expand 24` on iPad and `Open In 24` on iPhone (`steps.CONTEXTUAL_IDS`).
- **Two `searchEntry` ids.** The contextual input is a text view with id `searchEntry`, like the address bar (a search
  field). Always use `role=textview id=searchEntry`.
- **The iPhone sheet's Fire shares its label** with the toolbar Fire button, which stays in the tree under the sheet
  (not hittable): `nth=0` is the sheet's. It sits beside the collapsed input only with `aiChatTabHandoffImprovements`
  (pinned; without it Fire moves to the header and the selector matches only the toolbar's), so it is covered while
  the keyboard is up (for example right after reopening); fire from the state just after an answer.
- **The web channel reads the tab, never the sheet.** `ios.eval` and `ios.url()` see the page behind the sheet; read the
  chat from the native tree.
- **Page-context timing.** The page is read the moment the chat opens, from whatever has loaded, and read again each
  time a page finishes loading. Wait for the page's own text (`open_fixture` does) before opening, or the chip can
  show a partial page or none.
- **Flags.** Without `contextualDuckAIMode` the Duck.ai button opens a full-tab chat. Without the floating input flag
  the iPhone button opens the sheet directly, with no menu. Pin flags; never rely on the live privacy configuration.
- **The live service.** Sending needs the network and duck.ai. A first chat may show a consent card ("Agree and
  Continue") in some states; the runs here didn't meet it. If an answer never appears, check the network before
  calling it a product bug.

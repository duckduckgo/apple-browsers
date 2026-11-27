# Duck.ai: sidebar

The user opens Duck.ai beside the page they're on, in a sidebar of that tab, usually with the page attached ("Ask
About Page") or with text they selected (summarize, translate, ask about it). The sidebar belongs to its tab: closing
it hides that tab's chat. They can expand it into a full tab, or detach it into a floating window and attach it again.
From any Duck.ai surface, Duck.ai can use browser tools (list tabs, read a page), which ask for permission in a native
prompt. Duck.ai in a tab of its own is the [full tab](./duck-ai-tab.md).

## Sub-features

- `duckai-sidebar-ask-page`: Ask About Page opens the sidebar beside a web page, with the page attached.
- `duckai-sidebar-open`: Open Sidebar opens an empty sidebar on a New Tab Page.
- `duckai-sidebar-close`: Close Sidebar hides it; the chat stays hidden in that tab, even after navigating.
- `duckai-sidebar-selection`: Summarize, Translate or Ask Duck.ai About selected text opens the sidebar with it.
- `duckai-sidebar-expand`: the sidebar's expand button moves the chat into a full tab.
- `duckai-sidebar-floating`: detach the sidebar into a floating "Duck.ai" window, attach it back, close it.
- `duckai-browser-tools`: Duck.ai calls a browser tool; a tool that asks shows the native permission prompt.

## How to get to it (user POV)

Ids and titles come from source (paths under `macOS/DuckDuckGo/`). Debug builds have every flag named here on unless
it says otherwise.

- `duckai-sidebar-ask-page`: tab bar "Ask Duck.ai" pill (`TabBarViewController.duckAIChromeTitleButton`) → "Ask About
  Page" (`duckAIMenuSidebarAction`), or Duck.ai menu → "Ask About Page" (opt+cmd+L). The item's title follows the
  tab: "Ask About Page" on a web page, "Open Sidebar" on a New Tab Page, "Close Sidebar" while it's open
  (`TabBar/View/TabBarViewController.swift`). Needs `aiChatChromeSidebar` and `aiChatChromeMenuButton`; with the menu
  button off, the tab bar has a sidebar button (`TabBarViewController.duckAIChromeSidebarButton`, "Open Duck.ai
  sidebar") and View → "Show Duck.ai Sidebar" (opt+cmd+L), which don't attach the page. Also with
  `aiChatChromeSidebar` off, the address bar's Duck.ai button (`AddressBarButtonsViewController.aiChatButton`)
  toggles the sidebar when "Open Duck.ai in the sidebar" is on.
- From search results: when duckduckgo.com hands a Duck.ai chat over to the app, it opens in the sidebar if no chat
  is showing (`AIChat/Sidebar/AIChatCoordinator.swift`).
- `duckai-sidebar-open`: the same item on a New Tab Page, titled "Open Sidebar".
- `duckai-sidebar-close`: the same item, titled "Close Sidebar"; or the sidebar's own close button
  (`AIChatViewController.closeButton`).
- `duckai-sidebar-selection`: select text on a page, then right-click → "Summarize with Duck.ai" (shift+cmd+Return),
  "Translate with Duck.ai" (opt+cmd+T) or "Ask Duck.ai About Selected Content" (opt+cmd+K, `aiChatSelectionContext`)
  (`Tab/TabExtensions/ContextMenuManager.swift`). The keys also work without the menu. None show on a Duck.ai tab.
- `duckai-sidebar-expand`: the sidebar's `AIChatViewController.openInNewTabButton`.
- `duckai-sidebar-floating`: the sidebar's `AIChatViewController.detachButton` (needs `aiChatSidebarFloating`,
  internal-only: on for the internal user `prove` launches). The window is titled "Duck.ai" or "Duck.ai・<page
  title>" (a katakana middle dot, U+30FB) and has `AIChatViewController.attachButton` and
  `AIChatViewController.titleButton`. While it floats, the tab bar item reads "Close Sidebar".
- `duckai-browser-tools`: ask Duck.ai, in any surface, for something only a tool can answer ("Which tabs do I have
  open right now?" calls `listOpenTabs`). Needs `aiChatBrowserTools` (off by default) and one
  `aiChatBrowserTool<Name>` per tool (internal-only); tools that ask also need `websitePermissionsPrompts`.

## Driving it

Preconditions:

- `LIVE = ["duck.ai"]`: the sidebar loads the live Duck.ai web app.
- `AUTOMATION = True`, and the page comes from the local fixture: `navigate(fixture_url(token("x")))`.
- No flag pins for the default layout. `duckai-browser-tools` pins `aiChatBrowserTools`, each tool's flag, and
  `websitePermissionsPrompts`.

Per sub-feature:

- `duckai-sidebar-ask-page`: on the fixture page, `click("TabBarViewController.duckAIChromeTitleButton")`, then
  `click("duckAIMenuSidebarAction")`. Proof: `AIChatViewController.closeButton` appears, the tab's `url()` is still
  the fixture page and there is still one tab. Proved by `examples/t7_duckai_sidebar.py`. Not proved: that the page
  is attached. In a wiped VM container the sidebar's empty chat showed an "Ask about this page" chip above the input,
  with no attachment the harness could read.
  `macOS/UITests/AIChat/AIChatMenuButtonTests.swift` (`test_menu_onWebsite_showsAskAboutPage_andOpensSidebar`)
  covers it too.
- `duckai-sidebar-open`: not driven here; covered by `AIChatMenuButtonTests`
  (`test_menu_onNewTabPage_showsOpenSidebar_andOpensSidebar`).
- `duckai-sidebar-close`: not driven here; covered by `AIChatMenuButtonTests`
  (`test_menu_whenChatOpen_showsCloseSidebar_andCloses`) and, per tab, by `macOS/UITests/AIChat/AIChatTests.swift`
  (`test_sidebarButton_togglesSidebarPerTab`).
- `duckai-sidebar-selection`: not driven. Reachable: select the fixture page's text (`key("cmd+a")` on the page), then
  `key("shift+cmd+return")`; proof would be the sidebar's close button and the summary request reaching the page.
- `duckai-sidebar-expand`: not driven here; covered by `AIChatTests` (`test_sidebarExpandButton_opensDuckAITab`).
- `duckai-sidebar-floating`: not driven here; covered by `AIChatTests` (`test_detachSidebar_*`,
  `test_floatingSidebar_*`, `test_closeFloatingSidebar_updatesChromeBarIcon`,
  `test_closeTabWithDetachedSidebar_showsWarningPopover`), which run with the menu button off.
- `duckai-browser-tools`: blocked for a worked proof: the live model decides whether to call a tool, so a run can't
  make it happen reliably. By hand:
  - The permission prompt is an `NSPopover` below `TabBarViewController.browserToolPermissionButton`, a button that
    shows inside the Duck.ai pill while a request waits; the popover has no id of its own. Its buttons:
    `BrowserToolPermissionPrompt.allowOnce|alwaysAllow|neverAllow|dontAllow|allowInChat|allowForChat`. Cmd+Return
    picks the primary choice, Esc dismisses.
  - Proof per call: what the tool did, read from the app (a tab listed, switched or opened). The app logs no
    `success` / `cancelled` / `denied` result for a real call; only the debug panel's own calls are logged. Each new
    message is a new call ("list my open tabs one more time").
  - Reset stored Always / Never choices from Debug → AI Chat → Browser Tools Panel, Permissions section.
  - The prompt waits 120 s for an answer.

## Gotchas

- The sidebar web view has no id: detect the sidebar by its controls (`AIChatViewController.closeButton`,
  `openInNewTabButton`, `detachButton`).
- Detaching opens a second window: from then on every tab bar id matches twice (Shared steps, "Find across windows").
- Closing the sidebar leaves the chat hidden for that tab, even after navigating.
- The permission prompt makes itself key when it shows, and also answers Esc and Cmd+Return from the browser
  window, except while a text field (the address bar, Duck.ai's input) has focus: there the keys go to the field
  (Shared steps, "Key-window popovers").
- A browser tool that never gets called is usually a flag that isn't pinned.

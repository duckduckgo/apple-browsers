# Duck.ai: full tab

The user opens Duck.ai at duck.ai in a tab of its own: from the Duck.ai menu, the tab bar's "Ask Duck.ai" menu, the
More options menu, or by switching the address bar to Duck.ai mode and typing a prompt. They send a prompt, read the
streamed answer, and reopen earlier chats from Recent Chats. Duck.ai beside a page is the
[sidebar](./duck-ai-sidebar.md).

## Sub-features

- `duckai-tab-new-chat`: New Chat opens Duck.ai in a new selected tab (on a New Tab Page, from the tab bar menu, in
  that tab).
- `duckai-tab-omnibar`: in the address bar's Duck.ai mode, Return sends the typed prompt to Duck.ai in the current tab
  (in a new tab when the current one already shows Duck.ai).
- `duckai-tab-address`: typing `duck.ai` in the address bar loads it like any site.
- `duckai-tab-voice-image`: New Voice Chat and New Image Chat open Duck.ai in that mode in a new tab.
- `duckai-tab-history`: Recent Chats reopens an earlier chat in the current tab; chats persist across launches.
- `duckai-tab-delete-all`: Delete All Chats removes every chat.

## How to get to it (user POV)

Ids and titles come from source (paths under `macOS/DuckDuckGo/`). Debug builds have every flag named here on unless
it says otherwise.

- `duckai-tab-new-chat`:
  - Duck.ai menu (menu bar) → "New Chat", key equivalent opt+cmd+N (`Menus/AIChatMenu.swift`, shown while
    `aiChatMainMenuShortcut` is on). With that flag off, File → "New Duck.ai Chat" instead (`Menus/MainMenu.swift`).
  - Tab bar "Ask Duck.ai" pill (`TabBarViewController.duckAIChromeTitleButton`) → "New Chat"
    (`duckAIMenuNewChatAction`). Cmd-click or middle-click on the pill skips the menu and opens a new chat tab. The
    pill needs `aiChatChromeSidebar` and `aiChatChromeMenuButton`; with the menu button off, the tab bar shows a
    "Duck.ai" title button that opens a tab directly, and a separate sidebar button.
  - Duck.ai menu → "Open Duck.ai" opens it in a new tab too.
  - More options (⋯) → "Duck.ai" submenu → "New Chat" (`NavigationBar/View/MoreOptionsMenu.swift`,
    `aiChatMoreOptionsMenuShortcut`; with it off, a flat "New Duck.ai Chat" item).
  - Not on the default layout: with `aiChatChromeSidebar` off, the address bar's own Duck.ai button
    (`AddressBarButtonsViewController.aiChatButton`) opens a tab when "Open Duck.ai in the sidebar" is off. The
    Prompt Bar (a floating launcher; its shortcut and menu-bar icon are off by default) opens a tab or a window.
- `duckai-tab-omnibar`: focus the address bar, then switch to Duck.ai: click the "Duck.ai" segment of the toggle
  (`AddressBarButtonsViewController.searchModeToggleControl`, a radio group with segments "Search" and "Duck.ai" and
  no ids of their own), or press shift+Return or opt+Return (switches without submitting). Type, then Return.
  ctrl+Return from Search mode opens Duck.ai with the typed text submitted, as does the "Ask Duck.ai" row in the
  address bar's suggestions. In Duck.ai mode the suggestions list recent chats. The toggle shows only while the address
  bar is focused, and needs the AI Features setting "Show Search and Duck.ai toggle when the address bar is focused"
  (`Preferences.AIChat.showSearchAndDuckAIToggleToggle`, on by default).
  Right-click on the toggle offers "Hide Duck.ai Toggle".
- `duckai-tab-address`: type `duck.ai` in the address bar in Search mode, Return.
- `duckai-tab-voice-image`: Duck.ai menu → "New Voice Chat" (opt+cmd+V) or "New Image Chat" (opt+cmd+G).
- `duckai-tab-history`: Duck.ai menu → "Recent Chats" (up to 8), and "View All Chats..." in a new tab once there are
  more; the tab bar menu's "Chats" item (`duckAIMenuChatsAction`, flag `aiChatChromeMenuChats`, greyed out with no
  chats).
- `duckai-tab-delete-all`: Duck.ai menu → "Delete All Chats...".

## Driving it

Preconditions:

- `LIVE = ["duck.ai"]`: Duck.ai's page is the live web app at https://duck.ai (the default; a Debug custom URL in
  Debug → AI Chat → Web Communication overrides it, and a VM run starts without one).
- `AUTOMATION = True` for `url()`.
- Pin the flags of the entry point you drive: they default on, but remote configuration can turn them off.
  `t6_duckai_tab` pins `aiChatMainMenuShortcut`. A proof of a flag-off layout pins it off.

Per sub-feature:

- `duckai-tab-new-chat`: `key("opt+cmd+n")`. Proof: one more tab than before, the new tab's `url()` contains
  `duck.ai`, and Duck.ai's input ("Ask anything privately") shows. The URL changes while the page is still a grey
  skeleton: wait for the input before a screenshot. Proved by `examples/t6_duckai_tab.py`. The tab bar pill's New Chat and Cmd-click are covered by
  `macOS/UITests/AIChat/AIChatMenuButtonTests.swift` (`test_menu_newChat_opensNewTab`,
  `test_pillCommandClick_opensNewChatTab_withoutDropdown`).
- `duckai-tab-omnibar`: `key("cmd+t")` (the new tab's address bar is focused), `type(prompt)`, `key("shift+return")`
  (the switch carries the text over, with a line break), `key("return")`. Proof: still the same number of tabs, `url()` contains `duck.ai`, and `find(token)` matches the
  prompt in Duck.ai's page. Proved by `examples/t6_duckai_tab.py`. Prompt with a fresh `token()` and a space; never
  wait for the answer. `macOS/UITests/AIChat/AIChatOmnibarTests.swift` covers per-tab drafts, two-step Escape and toggle
  clicks, but not submitting.
- `duckai-tab-address`: not driven: ordinary navigation, the same as any site.
- `duckai-tab-voice-image`: not driven. Voice chat asks for the microphone (a TCC prompt the VM can't answer
  unattended).
- `duckai-tab-history`: not driven. Chats exist only after a prompt was answered and titled, which needs a streamed
  answer from the live model; a wiped VM container starts with none.
- `duckai-tab-delete-all`: not driven: needs earlier chats, as above.
- Paid models: blocked. Debug builds use the staging subscription backend, and this skill has no staging subscription
  account.

## Gotchas

- The address bar's Duck.ai mode stays on in that tab until it submits, navigates or is switched back (Shared
  steps, "Toggle memory"). A one-word prompt that reads as a URL navigates instead of reaching Duck.ai.
- Duck.ai mode's own input dropped characters typed into it at the harness's pace ("prompt-…" arrived as "promp").
  Type the prompt in Search mode and switch after, which carries it over intact. Its text isn't readable through
  AX: read the prompt back from Duck.ai's page after submitting.
- In a wiped container, Duck.ai shows the submitted prompt, then asks to accept its terms ("Continue") before it
  answers. Press Continue (Shared steps, "Duck.ai terms").
- The prompt doesn't travel in the URL: the tab loads plain duck.ai and the app hands the prompt to the page. Prove
  the prompt arrived from the page's content (`find`), not from `url()`.
- Duck.ai's first-use screens and accepted terms live in its web storage. A VM run starts with none; on this Mac a
  proof must not assume either.
- A fresh container has Duck.ai's own "recent chats" setting off (`isRecentChatsOn = "0"`, a setting of the web app,
  not the browser): chats don't persist. That isn't broken native storage.
- Debug and DMG builds keep chats in different containers; don't compare across bundles.
- "Ask anything privately", "Continue" and the chat's text are labels of Duck.ai's web app, which ships apart from the
  browser: a front-end change can break a check that reads them, and it fails loudly.
- `find("Duck.ai")` matches the menu bar's Duck.ai menu, the tab bar pill and the tab title: use ids.

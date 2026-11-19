# Duck.ai

The user reaches Duck.ai from the omnibar toggle, the sidebar or a full tab, sends a prompt and reads
the streamed answer. Chats persist across launches, and Duck.ai can call browser tools that ask for
permission in a native prompt.

## Sub-features

- `duckai-toggle`: the omnibar Search/Duck.ai toggle sends the typed text to Duck.ai.
- `duckai-sidebar`: Duck.ai in the sidebar next to the page.
- `duckai-full-tab`: Duck.ai at duck.ai in a tab.
- `duckai-storage`: chats persist across launches (native storage).
- `duckai-browser-tools`: Duck.ai calls a browser tool; tools that ask show the native permission
  prompt.

## How to get to it (user POV)

- `duckai-toggle`: click the address bar, then the Duck.ai segment of the toggle; type, Return.
- `duckai-sidebar`: the toolbar Duck.ai button, or the View menu.
- `duckai-full-tab`: type `duck.ai` in the address bar.
- `duckai-storage`: any of the three above, then quit and relaunch with the same topic.
- `duckai-browser-tools`: ask for something only a tool can answer, from any of the three above.

## Driving it

Preconditions:

- Network: responses need it. Without it, verify only the native side and mark the rest Unverified.
- `duckai-browser-tools`: `verify.sh flag <topic> aiChatBrowserTools on`, plus one
  `aiChatBrowserTool<Name>` per tool (internal-only); tools that ask also need
  `websitePermissionsPrompts on`.
- Duck.ai dev instance: the debug Duck.ai URL lives in `com.duckduckgo.macos.browser.debug`
  `customURL` (e.g. `https://use-serp-dev-testing3.duck.ai/`). Read it; don't overwrite it.

Per sub-feature:

- `duckai-toggle`: typing a prompt and pressing Return submits it. Proof: Duck.ai opens with the
  prompt as the first message. Wait for the response stream to finish before capturing.
- `duckai-storage`: proof: after quit and relaunch, the chat is in the recent list.
- `duckai-browser-tools`:
  - Trigger a tool by asking for it: "Which tabs do I have open right now?" calls `listOpenTabs`.
    Each new message is a new call, so "list my open tabs one more time" asks again.
  - The permission prompt is an `NSPopover` from the Duck.ai button (the tab bar control when
    visible). AX ids: `BrowserToolPermissionPrompt.allowOnce|alwaysAllow|neverAllow|close`.
  - Proof per call: the logged `executeClientTool` response (`success` / `cancelled` / `denied`).
  - Reset stored Always / Never choices from the Browser Tools debug panel, Permissions section.
  - The 120 s prompt deadline needs `verify.sh wait`.

## Gotchas

- A fresh container has `isRecentChatsOn = "0"`: chats don't persist. That's an FE setting, not
  broken native storage.
- Debug and DMG variants each have their own storage path; don't compare across bundles.
- A tool that never gets called is usually a flag that isn't pinned.
- The omnibar toggle remembers Duck.ai mode: typing a URL or a search then sends it to Duck.ai as a prompt
  instead of loading the page. For page setup use `verify.sh web navigate`, or switch the toggle to Search first.
- Tab-bar "Ask Duck.ai" pill (`TabBarViewController.duckAIChromeTitleButton`, needs `aiChatChromeSidebar` and
  `aiChatChromeMenuButton`): menu items `duckAIMenuNewChatAction`, `duckAIMenuSidebarAction` (title changes:
  Open Sidebar on NTP, Ask About Page on a web page, Close Sidebar when open) and `duckAIMenuChatsAction`.
  Closing the sidebar leaves the chat hidden for that tab, even after navigating.

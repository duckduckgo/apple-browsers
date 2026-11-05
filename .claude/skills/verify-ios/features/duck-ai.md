# Duck.ai

The user opens Duck.ai from the browser, starts a new chat, sends a prompt and reads the streamed answer. iPhone uses
the app's native input; iPad uses Duck.ai's own web input.

## Sub-features

- `duckai-open` the in-app entry point opens Duck.ai.
- `duckai-new-chat` New Chat starts an empty chat.
- `duckai-send` a typed prompt is submitted and an answer streams back.

## How to get to it (user POV)

- iPhone: the Duck.ai button in the omnibar (`Browser.OmniBar.Button.AIChat`), then New Chat.
- iPad: the Duck.ai button in the tab bar (`Browser.TabsBar.AIChatMenuButton`), then New Chat.

## Driving it with verify-ios

Preconditions:

- `steps.fresh_start(ios)`: a run must not start on a previous run's Duck.ai tab.
- The proof declares `LIVE = ["duck.ai"]`: it needs the real network and the live Duck.ai service.

- **Open and start a chat.** `steps.open_duckai_new_chat(ios)`: taps the device's entry button, then
  `label="New Chat"`; proof: `ios.expect_url_contains("duck.ai")`.
- **Send.** `steps.send_duckai_prompt(ios, prompt)`. iPhone: waits for `id=AIChat.Toolbar.Button.Submit`, types into
  the focused native input (`ios.type("-", …)`), waits for Submit to be enabled, taps it. iPad: types into
  `label="Ask anything privately" nth=0`, waits for `role=button label="Ask"` to be enabled, taps it.
- **Read the answer.** `steps.read_duckai_answer(ios)` reads the text after the last "Duck.ai said" once it has stopped
  changing for 2 s. Proof: it contains the expected content (`ios.check`).
- Worked proof: `examples/t8_duckai.py`.

## Gotchas

- iPhone and iPad have **different inputs**: `AIChat.Toolbar.Button.Submit` (native) vs `Ask anything privately` +
  `Ask` (web). A proof written for one fails on the other unless it uses `steps.send_duckai_prompt`.
- The tab switcher has its own Duck.ai button, `TabSwitcher.Button.DuckChat`. Earlier driver evaluation runs also saw a Duck.ai
  control labelled with the icon name `Ai Chat 24`; this skill's runs have not met it yet.
- `Ask anything privately` matches more than once on iPad; use `nth=0`.
- Answers stream: reading too early gives a partial answer.
- Judge reachability from the app, not from a host-side request: the host's sandbox can refuse connections the
  simulator makes fine. If New Chat never loads `duck.ai`, check the network before calling it a product bug.

"""Duck.ai opens as a full tab: New Chat (opt+cmd+N) opens duck.ai in a new tab, and Duck.ai mode in the address bar (shift+Return) sends the typed prompt to duck.ai in the current tab."""
FLAGS = {"aiChatMainMenuShortcut": True}   # the Duck.ai menu and its New Chat key equivalent
LIVE = ["duck.ai", "improving.duckduckgo.com"]   # the live Duck.ai web app and the page's own telemetry host; no
# check here waits for a streamed answer
AUTOMATION = True    # for url()


def run(mac):
    # duckai-tab-new-chat: the Duck.ai menu's New Chat key equivalent
    tabs = mac.tab_count()   # not 1 on --target mac, where the Debug app may restore its session
    mac.key("opt+cmd+n")
    mac.expect_tab_count(tabs + 1)
    mac.expect_url_contains("duck.ai")
    # Duck.ai's input placeholder, a label of its web app: the page has loaded past its skeleton
    mac.eventually("Duck.ai's input shows", lambda: mac.find("Ask anything privately"), timeout=20)
    mac.shot("new-chat-tab")

    # duckai-tab-omnibar: a new tab's focused address bar, switched to Duck.ai mode, sends the prompt to duck.ai
    token = mac.token("t6")
    mac.key("cmd+t")
    mac.expect_tab_count(tabs + 2)
    # Typed in Search mode, then carried over by the switch: Duck.ai's own input can drop fast-typed characters.
    mac.type(f"say {token}")   # a space, so it can't be read as a URL
    mac.key("shift+return")    # flips the Search / Duck.ai toggle without submitting
    mac.shot("duckai-mode")
    mac.key("return")
    mac.expect_tab_count(tabs + 2)   # the current tab, not a new one
    mac.expect_url_contains("duck.ai")
    mac.eventually("the prompt reached Duck.ai's page", lambda: mac.find(token))   # a second read, through AX
    mac.shot("prompt-in-duckai")

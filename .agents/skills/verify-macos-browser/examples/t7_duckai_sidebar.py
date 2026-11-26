"""On a web page, the tab bar's Ask Duck.ai menu, Ask About Page, opens the Duck.ai sidebar beside the page: the sidebar's controls appear and the tab still shows the page."""
FLAGS = {"aiChatChromeSidebar": True, "aiChatChromeMenuButton": True}   # the tab bar's "Ask Duck.ai" menu
LIVE = ["duck.ai"]   # the sidebar loads the live Duck.ai web app; no proof here waits for a streamed answer
AUTOMATION = True    # for navigate() and url()


def run(mac):
    token = mac.token("t7")
    mac.navigate(mac.fixture_url(token))   # setup only; the action under proof is the menu below
    mac.expect_url_contains(token)
    mac.click("TabBarViewController.duckAIChromeTitleButton")   # the "Ask Duck.ai" pill opens its menu
    mac.click("duckAIMenuSidebarAction")   # titled "Ask About Page" on a web page
    mac.eventually("the sidebar's close button shows", lambda: mac.find("AIChatViewController.closeButton"))
    mac.expect_url_contains(token)   # the page stays in the tab; Duck.ai is beside it, not instead of it
    mac.expect_tab_count(1)
    mac.shot("sidebar")

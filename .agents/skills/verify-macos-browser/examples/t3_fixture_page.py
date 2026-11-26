"""A local fixture page loads with this run's token in its URL and tab title, and clicking its link opens target.html, with no live service."""
FLAGS = {}
LIVE = []           # local pages only: the report says so, and flags any other host the app loaded
AUTOMATION = True   # for navigate() and url()


def run(mac):
    token = mac.token("t3")
    mac.navigate(mac.fixture_url(token))   # setup only; the action under proof is the click below
    mac.expect_url_contains(token)
    mac.eventually("tab title shows the token", lambda: mac.find(f"fixture {token}"))   # a second read, through AX
    mac.shot("fixture")
    mac.click("target link")   # the link's aria-label, so the match is the link alone
    mac.expect_url_contains("/target.html")
    mac.shot("target")

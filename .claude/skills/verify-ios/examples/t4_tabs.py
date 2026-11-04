"""Opening a new tab, switching back, and closing it takes the tab count 1 → 2 → 1, and the first tab keeps its page."""
from verify_ios import steps


def run(ios):
    steps.fresh_start(ios)
    token = ios.token("t4")
    steps.open_fixture(ios, token)
    steps.expect_tab_count(ios, 1)
    steps.new_tab(ios)
    steps.expect_tab_count(ios, 2)
    ios.shot("new-tab")
    steps.dismiss_address_bar(ios)
    steps.switch_to_tab(ios)
    ios.expect_url_contains(token)
    steps.close_current_new_tab(ios)
    steps.expect_tab_count(ios, 1)
    ios.expect_web_text("#token", token)
    ios.shot("final")

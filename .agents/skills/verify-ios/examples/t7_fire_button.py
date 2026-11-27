"""The Fire button closes all tabs, clears site data, and reports it in its pixels and its data-clearing wide event."""
from verify_ios import steps

STORAGE_KEY = "verify-ios"   # the fixture page writes its token here on load


def run(ios):
    steps.fresh_start(ios)
    token = ios.token("t7")
    steps.open_fixture(ios, token)
    ios.check("setup: the page wrote localStorage",
              ios.eval(f"return {{v: localStorage.getItem('{STORAGE_KEY}')}}").get("v") == token)
    steps.new_tab(ios)                                 # a second tab, so "closes all tabs" is tested
    steps.expect_tab_count(ios, 2)
    steps.dismiss_address_bar(ios)
    ios.mark()
    steps.fire(ios)
    steps.expect_tab_count(ios, 1, 10)                 # 2 → 1
    ios.expect_no_web_page()                           # the remaining tab is a blank new-tab page
    ios.expect_pixel(f"m_forget-all-executed_daily_ios_{ios.form_factor}")
    ios.expect_wide_event("data-clearing", status="SUCCESS")
    steps.open_fixture(ios, ios.token("t7b"))
    ios.expect_web_text("#stored", "empty")            # "present" would mean localStorage survived
    ios.shot("final")

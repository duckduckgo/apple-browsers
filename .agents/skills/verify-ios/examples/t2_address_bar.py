"""Tapping the address bar on the new-tab page focuses it, and submitting a URL loads that page in the current tab."""
from verify_ios import steps


def run(ios):
    steps.fresh_start(ios)          # address bar not focused
    token = ios.token("t2")
    ios.mark()
    ios.tap("id=searchEntry")
    ios.expect_keyboard(shown=True)
    ios.expect_pixel(f"m_addressbar_click_ntp_ios_{ios.form_factor}")
    ios.type("id=searchEntry", ios.fixture_url(token), submit=True)
    ios.expect_url_contains(token)
    ios.shot("after-submit")
    ios.expect_web_text("#token", token)

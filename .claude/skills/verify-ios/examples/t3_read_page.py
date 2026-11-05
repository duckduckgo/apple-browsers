"""A loaded page's text is readable both from the native accessibility tree and from the web channel."""
from verify_ios import steps


def run(ios):
    steps.fresh_start(ios)
    token = ios.token("t3")
    steps.open_fixture(ios, token)
    ios.expect_visible(f'label="token: {token}"')
    ios.expect_visible('label="status: idle"')
    ios.expect_web_text("#token", token)
    ios.expect_web_text("#status", "idle")
    ios.shot("page")

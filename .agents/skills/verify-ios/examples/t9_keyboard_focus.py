"""Tapping the address bar focuses it and shows the keyboard; dismissing hides both. On iPad, cmd+l focuses it."""
from verify_ios import steps


def run(ios):
    steps.fresh_start(ios)
    steps.open_fixture(ios, ios.token("t9"))
    ios.tap("id=searchEntry")
    ios.expect_keyboard(shown=True)
    ios.expect_focused("searchEntry")
    ios.shot("focused")
    ios.tap(steps.ids(ios)["dismiss"])
    ios.expect_keyboard(shown=False)
    ios.expect_not_focused("searchEntry")
    if ios.device == "ipad":
        ios.key("cmd+l")
        ios.expect_focused("searchEntry")
        ios.tap(steps.ids(ios)["dismiss"])
    ios.shot("final")

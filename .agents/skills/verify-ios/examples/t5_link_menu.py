"""Long-pressing a link shows its context menu, and Open in New Tab opens the link target in a new tab."""
from verify_ios import steps


def run(ios):
    steps.fresh_start(ios)
    steps.open_fixture(ios, ios.token("t5"))
    before = len(ios.handles())
    link = 'role=link label="external link"'
    ios.wait(link, "visible", 8)
    ios.long_press(link, ms=1000)
    ios.expect_visible('label="Open in New Tab"', 5)
    ios.shot("menu")
    ios.tap('label="Open in New Tab"')
    ios.eventually("a new tab exists", lambda: len(ios.handles()) == before + 1)
    ios.eventually("the new tab shows the link target", lambda: ios.url().endswith("/target.html"))
    ios.shot("final")

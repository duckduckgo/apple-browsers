"""Cmd+T opens a second tab and Cmd+W closes it again: the tab bar goes from 1 to 2 to 1 tab."""
FLAGS = {}
LIVE = []
AUTOMATION = False


def run(mac):
    mac.expect_tab_count(1)
    mac.key("cmd+t")
    mac.expect_tab_count(2)   # read back through the accessibility tree, not assumed from the key press
    mac.shot("two-tabs")
    mac.key("cmd+w")
    mac.expect_tab_count(1)
    mac.shot("one-tab")

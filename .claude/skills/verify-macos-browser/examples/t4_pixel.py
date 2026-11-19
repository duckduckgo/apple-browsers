"""Cmd+T fires the new-tab page loading pixel and does not fire the Fire Window pixel."""
FLAGS = {}
LIVE = []
AUTOMATION = False


def run(mac):
    mac.expect_tab_count(1)
    mac.mark()                     # telemetry counts from here: launch and setup fire pixels too
    mac.key("cmd+t")
    mac.expect_tab_count(2)
    mac.expect_pixel("m_mac_new-tab-page_loading_time")
    mac.expect_no_pixel("m_mac_firewindow_opened")
    mac.shot("new-tab")

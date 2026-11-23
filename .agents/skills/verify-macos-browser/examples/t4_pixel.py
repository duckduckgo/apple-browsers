"""Cmd+T fires the new-tab page loading pixel and does not open a Fire Window."""
FLAGS = {}
LIVE = []
AUTOMATION = False


def run(mac):
    mac.expect_tab_count(1)
    mac.mark()                     # telemetry counts from here: launch and setup fire pixels too
    mac.key("cmd+t")
    mac.expect_tab_count(2)
    mac.expect_pixel("m_mac_new-tab-page_loading_time")
    mac.expect_no_pixel("m_mac_firewindow_opened_manual")   # New Fire Window (shift+cmd+N) sits next to New Tab in File
    mac.shot("new-tab")

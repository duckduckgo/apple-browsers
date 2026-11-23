"""This worktree's Debug build launches and shows one window with one tab; prove's doctor step confirms the running binary is that build."""
FLAGS = {}
LIVE = []
AUTOMATION = False


def run(mac):
    mac.expect_tab_count(1)
    mac.shot("launched")

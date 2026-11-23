"""In dark mode, with its window at 40,60 and 1280×800 points, the app opens a second tab on Cmd+T."""
FLAGS = {}
LIVE = []
AUTOMATION = False
# Set before the proof, read back, recorded in report.md and manifest.json, undone after it: screenshots compare
# between runs and with --base. In a VM the appearance is the system's; on this Mac it is the app's own setting.
CONDITIONS = dict(appearance="dark", window=(40, 60, 1280, 800))


def run(mac):
    mac.expect_tab_count(1)
    mac.key("cmd+t")
    mac.expect_tab_count(2)
    mac.shot("dark-two-tabs")   # 1280×800 points, dark: look at it before claiming either

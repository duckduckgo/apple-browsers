"""Dark mode, a larger text size, landscape and a fixed status bar all reach the app, so screenshots can be compared.

Every condition is undone after the proof (ios.on_cleanup) and recorded in the manifest.
"""
from verify_ios import steps

READ = """var e=document.createElement('span'); e.style.font='-apple-system-body'; e.textContent='x';
document.body.appendChild(e); var px=parseFloat(getComputedStyle(e).fontSize); e.remove();
return {dark: matchMedia('(prefers-color-scheme: dark)').matches, bodyFont: px, landscape: innerWidth > innerHeight}"""


def run(ios):
    steps.fresh_start(ios)
    steps.open_fixture(ios, ios.token("t10"))
    before = ios.eval(READ)
    ios.check("starts in light mode, portrait", not before["dark"] and not before["landscape"], before)

    ios.fixed_status_bar()                              # read back from the simulator, or the run is inconclusive
    ios.check("status bar override is active", ios.d.capture_conditions()["statusBar"].startswith("fixed"))
    ios.appearance("dark")
    ios.eventually("the page sees dark mode", lambda: ios.eval(READ)["dark"])

    ios.text_size("accessibility-large")
    steps.open_fixture(ios, ios.token("t10b"))          # a fresh page picks up the new Dynamic Type size
    ios.eventually("body text got larger", lambda: ios.eval(READ)["bodyFont"] > before["bodyFont"])

    ios.rotate("landscapeLeft")
    ios.eventually("the page is landscape", lambda: ios.eval(READ)["landscape"])
    ios.shot("dark-large-landscape")

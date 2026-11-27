"""The driver refuses every unsafe action and the build check rejects a wrong build: the trust contract.

Run it after any change to the runner, the driver or the library, and before using a new driver:
    bin/verify-ios prove tests/must_fail.py
Every probe must fail with the expected code and leave the page unchanged.
"""
import os, tempfile

from verify_ios import Failed, steps
from verify_ios.driver import XCUITestRunner


def must_fail(ios, what, fn, code):
    try:
        fn()
    except Failed as e:
        got = (e.extra.get("runner") or {}).get("code") or e.extra.get("code") or str(e)
        return ios.check(f"refused: {what} ({code})", got == code, dict(got=got, message=str(e)))
    ios.check(f"refused: {what} ({code})", False, "the action succeeded")


def run(ios):
    steps.fresh_start(ios)
    token = ios.token("mf")
    steps.open_fixture(ios, token)
    steps.dismiss_address_bar(ios)
    url = ios.url()

    must_fail(ios, "tap a missing element", lambda: ios.d.tap("id=verify-ios.does-not-exist"), "NOT_FOUND")
    # Two buttons share this label and either one changes #status, so a guessed tap would show in the check below.
    must_fail(ios, "tap an ambiguous locator", lambda: ios.d.tap('label="twin button"'), "AMBIGUOUS")
    must_fail(ios, "wait on an ambiguous locator", lambda: ios.d.wait('label="twin button"', "visible", 1), "AMBIGUOUS")
    must_fail(ios, "tap a disabled button", lambda: ios.d.tap('role=button label="disabled button"'), "DISABLED")
    must_fail(ios, "swipe on a disabled button", lambda: ios.d.swipe("up", 'role=button label="disabled button"'), "DISABLED")
    must_fail(ios, "tap an element that is off-screen", lambda: ios.d.tap('label="bottom marker"'), "NOT_HITTABLE")
    must_fail(ios, "type with nothing focused", lambda: ios.d.type("-", "x"), "NOT_FOCUSED")
    must_fail(ios, "answer an alert that isn't there", lambda: ios.d.alert("accept", timeout=1), "NOT_FOUND")
    ios.check("page unchanged by refused actions", ios.url() == url and ios.d.get("web:css=#status")["value"] == "idle")

    if ios.device == "iphone":   # a new tab opens with the keyboard covering the bottom toolbar
        steps.new_tab(ios)
        ios.expect_keyboard(shown=True)
        must_fail(ios, "tap a toolbar button under the keyboard", lambda: ios.d.tap("id=Browser.Toolbar.Button.Fire"), "NOT_HITTABLE")
        must_fail(ios, "wait for a covered button to be visible", lambda: ios.d.wait("id=Browser.Toolbar.Button.Fire", "visible", 1),
                  "TIMEOUT")
        steps.expect_tab_count(ios, 2)

    stranger = XCUITestRunner(ios.d.udid, ios.d.runner_port, "not-this-worktrees-token")
    ios.check("runner refuses a caller without the worktree token", not stranger.alive())
    ios.check("runner refuses shutdown without the token",
              stranger.call({"op": "shutdown"}).get("code") == "UNAUTHORIZED" and ios.d.driver.alive())

    with tempfile.TemporaryDirectory() as tmp:
        fake = os.path.join(tmp, "DuckDuckGo.app")
        os.makedirs(fake)
        with open(os.path.join(fake, "DuckDuckGo"), "wb") as f:
            f.write(os.urandom(64))
        wrong = ios.d.identity(app=fake)
        ios.check("doctor rejects a different build", not wrong["ok"] and "not this worktree's build" in wrong["reason"], wrong)
    missing = ios.d.identity(app="/nonexistent/DuckDuckGo.app")
    ios.check("doctor rejects a build it cannot hash", not missing["ok"] and "cannot hash" in missing["reason"], missing)
    ios.check("doctor accepts this worktree's build", ios.d.identity()["ok"])

    # With the app stopped, "gone" and "not focused" must not pass: there is nothing to observe.
    ios.d.terminate()
    must_fail(ios, "expect an element gone while the app is stopped", lambda: ios.d.wait("id=searchEntry", "hidden", 1),
              "APP_NOT_RUNNING")
    must_fail(ios, "read focus while the app is stopped", lambda: ios.d.snapshot(), "APP_NOT_RUNNING")
    ios.check("the run is not judged in the foreground while the app is stopped", not ios.d.foreground())
    ios.launch()   # so the run itself ends with the app in the foreground

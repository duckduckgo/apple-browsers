"""A page asking for location shows DuckDuckGo's permission sheet; Never Allow gives the page a denial.

The allow path is not proven here: the iOS 27.0 simulator may never deliver a location fix (environment, not app).
"""
from verify_ios import steps


def run(ios):
    steps.reset_location_permission(ios)          # undone after the proof (ios.on_cleanup)
    steps.set_simulated_location(ios, 52.52, 13.405)
    steps.fresh_start(ios)                        # reinstall also clears DuckDuckGo's per-site permission
    steps.open_fixture(ios, ios.token("t6"))
    ios.tap('role=button label="ask for location"')
    ios.expect_web_text("#geo-result", "asking", 4)
    ios.expect_visible("id=SitePermissions.Dialog", 6)
    ios.shot("site-permission")
    ios.tap("id=SitePermissions.Dialog.NeverAllow")
    ios.expect_no_alert(within=3)                 # denying in DuckDuckGo's sheet never reaches the iOS alert
    ios.expect_web_text("#geo-result", "denied", 16)
    ios.unverified("allow path", "the iOS 27.0 simulator may never deliver a location fix (geolocation error 3)")

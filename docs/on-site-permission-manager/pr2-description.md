# Suggested PR title

`Add on-site permission coordination and system gating`

# Suggested PR body

Task/Issue URL: https://app.asana.com/1/137249556945/task/1217863452475659
Tech Design URL: https://app.asana.com/1/137249556945/task/1213800892997347
CC:

### Description

Adds the decision and system-permission layers for on-site camera, microphone, and location access. It also freezes the existing media-capture behavior in regression matrices before the feature is connected to production flows.

The feature remains behind `sitePermissions`, which is off by default. This PR adds no production reachability or UI and does not alter the existing Duck.ai or browser media-capture delegates.

### Testing Steps

1. Run `xcodebuildmcp simulator build --workspace-path DuckDuckGo.xcworkspace --scheme "iOS Browser" --simulator-name "iPhone 17"` from the repository root. The app builds successfully with the project deployment target.
2. Run `xcodebuildmcp simulator test --workspace-path DuckDuckGo.xcworkspace --scheme "iOS Browser" --simulator-name "iPhone 17" --extra-args=-only-testing:SitePermissionsTests --extra-args=-only-testing:UnitTests --extra-args=IPHONEOS_DEPLOYMENT_TARGET=16.0`. The selected suites complete with no failures; the verified run passed 6,629 tests and reported 37 baseline skips.

### Impact

High. This code will decide whether privacy-sensitive camera, microphone, and location requests proceed once later PRs connect it to the app.

#### What could go wrong?

- A queued request could use stale permission state → the coordinator re-evaluates stored and session choices when each request reaches the front of its per-tab FIFO.
- A callback could grant access to a navigated tab → every callback validates the tab, request URL, current main-frame URL, committed document identity, and active-tab identity.
- An iOS prompt could appear without the site prompt → undetermined native access returns the recovery path for automatic stored or session Allow requests.
- Concurrent location requests could hang or duplicate the native prompt → the system client coalesces callers and resumes every pending continuation.
- The feature could change current behavior while disabled → production delegates are unchanged in this PR, and exact legacy matrices cover both browser and Duck.ai paths.

### Quality Considerations

- Persistent Allow remains stored when iOS denies access so the manager continues to show the user’s site choice.
- Allow Once and Deny Once are session-only and are cleared on document or tab lifecycle changes.
- Combined camera and microphone decisions never resolve partially.
- Location uses one `CLLocationManager` for authorization and one-shot position callbacks.
- Permission state contains no domain, host, URL, or origin telemetry.

---
###### Internal references:
[Definition of Done](https://app.asana.com/0/1202500774821704/1207634633537039/f) | [Engineering Expectations](https://app.asana.com/0/59792373528535/199064865822552) | [Tech Design Template](https://app.asana.com/0/59792373528535/184709971311943)

---
name: ddg-ios-launch-profile
description: Use when starting the iOS app on a simulator in a given state — feature flags, experiments, internal user, onboarding skipped, a clean start, a privacy config URL or open tabs — for example to follow a PR's testing steps or to reproduce a bug. Also use when writing iOS PR testing steps that need such a state.
---

# iOS launch profile

Start the app in a known state with one JSON value instead of tapping through Settings and the Debug menu.
Works in DEBUG and ALPHA builds only.

```bash
xcrun simctl launch --terminate-running-process <udid> com.duckduckgo.mobile.ios -launchProfile '{
  "resetAppState": true,
  "internalUser": true,
  "onboardingCompleted": true,
  "featureFlags": { "sitePermissions": true },
  "tabs": ["https://example.com"]
}'
```

`-launchProfile` takes inline JSON or an absolute path to a `.json` file. In XCUITest, append
`["-launchProfile", json]` to `app.launchArguments`.

## Keys

Keys are JSON paths: `{"featureFlags": {"x": true}}` and `{"featureFlags.x": true}` are the same.

| Key | Value | Effect |
|---|---|---|
| `resetAppState` | Bool | `true` deletes saved settings, flag overrides, statistics and tabs first |
| `internalUser` | Bool | Internal user, needed by every key marked * (flags and experiments also work without it in UI tests) |
| `onboardingCompleted` | Bool | `true` skips onboarding, `false` shows it, this launch only |
| `featureFlags.<name>` * | Bool | Overrides a `FeatureFlag` case (raw value), like the Debug menu |
| `experiments.<name>` * | String | Puts the user in a cohort of that experiment flag |
| `privacyConfigURL` * | http(s) URL | Privacy configuration from this URL, this launch only |
| `tabs` | [http(s) URL] | Replaces the open tabs and closes Fire tabs; the last one is selected |

The catalog is `iOS/DuckDuckGo/LaunchProfile/IOSLaunchSettings.swift`.

## Rules

- Start with `"resetAppState": true` unless the test needs earlier state. Values otherwise persist like a Debug
  menu change, so leftovers from earlier sessions would decide what you test.
- State in your result which profile you launched with.
- A profile is checked as a whole: one unknown key, wrong type or missing `"internalUser": true` and nothing
  is written.
- If the profile fails, a key's meaning is unclear, or a PR's summary and JSON disagree: when the intent is clear,
  fix it, carry on and flag what you changed in your result; when it isn't, stop and ask. Quote the
  `LAUNCH_PROFILE_FAILED` line either way.

## Result

The app logs one line and prints it to stderr:

```
LAUNCH_PROFILE_APPLIED keys=resetAppState,internalUser,featureFlags.sitePermissions
LAUNCH_PROFILE_FAILED Unknown key "featureFlag.x".
```

Read it with `xcrun simctl spawn <udid> log show --last 1m --predicate 'category == "LaunchProfile"'`.

## In a PR

Under Testing Steps, give the starting state for a person testing by hand, and the same state as a profile in a
collapsed block for agents. The JSON is the source of truth; write the summary from it. List only what a tester
has to set up on purpose: leave out a fresh install, internal user and skipped onboarding, which every tester
does anyway. Use one item per line: each flag with ON/OFF and, if the name doesn't say it, what it changes; tabs
numbered in order with full URLs and the selected one marked.

````markdown
**Starting state**
- Feature flags:
  - `sitePermissions`: ON
  - `floatingUIiOS27`: OFF (classic toolbar)
- Open tabs (2):
  1. https://example.com/
  2. https://duckduckgo.com/ ← selected

<details><summary>Launch profile</summary>

```json
{
  "resetAppState": true,
  "internalUser": true,
  "onboardingCompleted": true,
  "featureFlags": { "sitePermissions": true, "floatingUIiOS27": false },
  "tabs": ["https://example.com/", "https://duckduckgo.com/"]
}
```
</details>
````

## Adding a key

Add one factory to `IOSLaunchSettings` that takes only the store it writes, list it in `make`, and cover what it
writes in `IOSLaunchSettingsTests`. Put checks that can fail in `validate`, so a bad profile writes nothing.

---
name: ddg-ios-launch-profile
description: Use when starting the iOS app on a simulator in a set state (flags, experiments, settings, Debug menu values, tabs), e.g. to follow PR testing steps or reproduce a bug; when writing iOS PR testing steps; or when adding a Settings or Debug menu option.
---

# iOS launch profile

Start the app in a known state with one JSON value instead of tapping through Settings and the Debug menu.
Works in Debug and Alpha builds only.

## Launch

Launch with the skill's `launch` script. It boots this worktree's own simulator, installs the app, launches it with
the profile and prints the result line:

```bash
.claude/skills/ddg-ios-launch-profile/launch --fresh --app <path to DuckDuckGo.app> '{
  "internalUser": true,
  "onboardingCompleted": true,
  "featureFlags": { "floatingUIiOS27": true },
  "tabs": ["https://example.com"]
}'
```

- `--fresh` uninstalls first, so it needs `--app`. Use it when you switch to a different PR or bug: a profile sets only the keys it lists,
  and saved values from the previous one, such as flag overrides, would otherwise still apply. For the same PR, leave
  it out.
- Leave out `--app` to relaunch the installed build. `--device ipad` uses an iPad. `--udid` picks another simulator.
- Exit 0: applied. 1: the app rejected the profile. 2: anything else.
- Don't launch the app with `xcrun simctl` yourself. The script refuses `verify-ios-*` simulators; on one of them, a
  running proof would check your app instead of its own.

The profile is inline JSON or an absolute path to a `.json` file. In XCUITest, which can't reinstall between tests,
append `["-clearAllDefaults", "-launchProfile", json]` to `app.launchArguments`.

## Keys

Keys are JSON paths: `{"featureFlags": {"x": true}}` and `{"featureFlags.x": true}` are the same.
Keys marked * need `"internalUser": true` in the same profile (flags and experiments don't in UI tests).

| Key | Value | Lasts | Effect |
|---|---|---|---|
| `internalUser` | Bool | Saved | Internal user |
| `onboardingCompleted` | Bool | One launch | `true` skips onboarding, `false` shows it |
| `featureFlags.<name>` * | Bool | Saved | Overrides a `FeatureFlag` that supports local overriding, like the Debug menu; other flags have no key |
| `experiments.<name>` * | String | Saved | Puts the user in a cohort of that experiment; a wrong cohort lists the valid ones |
| `privacyConfigURL` * | http(s) URL | One launch | Privacy configuration from this URL |
| `tabs` | [http(s) URL] | Saved | Replaces the open tabs and closes Fire tabs; the last one is selected |
| `settings.addressBarPosition` | `top`, `bottom` | Saved | Address bar position (iPad is always top) |
| `settings.theme` | `systemDefault`, `light`, `dark` | Saved | App theme |
| `settings.textZoom` | 50, 60, … 170 | Saved | Website text size in percent |
| `settings.fireAnimation` | `fireRising`, `fireRisingLegacy`, `waterSwirl`, `airstream`, `none` | Saved | Fire button animation; `none` speeds up Fire repros |
| `settings.autoClear.options` | any of `tabs`, `data`, `aiChats` | Saved | What Automatically Clear Data clears; `[]` turns it off |
| `settings.autoClear.timing` | `termination`, `delay5min`, `delay15min`, `delay30min`, `delay60min` | Saved | When it clears |
| `duckAI.enabled` | Bool | Saved | Duck.ai on or off everywhere |
| `duckAI.addressBar`, `.searchInput`, `.browsingMenu`, `.voiceSearch`, `.tabSwitcher` | Bool | Saved | Duck.ai entry points; `searchInput` is the search and Duck.ai toggle in the address bar |
| `duckAI.defaultOmnibarMode` | `search`, `duckAI`, `lastUsed` | Saved | Mode the address bar starts in (needs the `aiChatOmnibarDefaultPosition` flag) |
| `duckAI.pageSummariesModel` | `duckAI`, `appleIntelligence` | Saved | Model that summarizes pages |
| `debug.onboarding.userType` | `notSet`, `newUser`, `returningUser` | Saved | Onboarding treats the install as new or returning |
| `debug.onboarding.flowType` | `default`, `duckAI` | Saved | Forces an onboarding flow |
| `debug.duckAI.customURL` | http(s) URL | Saved | Loads Duck.ai from this URL |
| `debug.idleReturnThresholdSeconds` | Int > 0 | Saved | Seconds in the background before the app returns to a new tab page |
| `debug.syncEnvironment` | `Production`, `Development` | Saved | Sync server; use it signed out of Sync |
| `debug.daysSinceInstall` | Int ≥ 0 | Saved | Install date that many days back, as Remote Messaging's "Set Days Since Installed" sets it; a fresh install's first statistics request can still reset it to today, so relaunch with the profile before relying on it |
| `debug.configURLs.<name>` * | http(s) URL | Saved | Custom configuration URL; `<name>` is `privacyConfiguration`, `trackerDataSet`, `surrogates`, `remoteMessagingConfig`, `bloomFilterSpec`, `bloomFilterBinary` or `bloomFilterExcludedDomains` |

"Saved" values stay until the app changes them or is reinstalled. For a privacy config used once, use
`privacyConfigURL`; for one that must survive relaunches, use `debug.configURLs.privacyConfiguration`.

The catalog is `iOS/DuckDuckGo/LaunchProfile/IOSLaunchSettings.swift`, with the other keys in
`IOSLaunchSettings+Settings.swift`, `+DuckAI.swift` and `+Debug.swift`.

## Result

The app logs one line, which the `launch` script prints. In XCUITest, read it with
`xcrun simctl spawn <udid> log show --last 1m --predicate 'category == "LaunchProfile"'`.

| Line | Meaning |
|---|---|
| `LAUNCH_PROFILE_APPLIED keys=internalUser,featureFlags.floatingUIiOS27` | Everything was written |
| `LAUNCH_PROFILE_FAILED Unknown key "featureFlag.x".` | Nothing was written. Fix the profile and launch again |
| `LAUNCH_PROFILE_FAILED applied=internalUser,tabs <problem>` | A write failed after the listed keys were written. Reinstall and launch again |
| No line | A Release build, or the argument didn't reach the app |

The whole profile is checked before anything is written: one unknown key (an empty object `{}` counts as one),
wrong type or missing `"internalUser": true` and nothing changes.

## Relaunching

A relaunch without the profile shows onboarding again and drops `privacyConfigURL`. To relaunch mid-test, pass the
same profile without `tabs`, so the open tabs stay. XCUITest sends `launchArguments` on every `app.launch()`.

## Rules

- State in your result which profile you launched with.
- If the profile fails, a key's meaning is unclear, or a PR's summary and JSON disagree: when the intent is clear,
  fix it, carry on and flag what you changed in your result; when it isn't, stop and ask. Quote the
  `LAUNCH_PROFILE_FAILED` line either way.
- No profile in the PR: build one from its testing steps and the diff (new flags), say in your result what you
  inferred, and do the steps no key covers by hand.

## In a PR

Under Testing Steps, give the starting state for a person testing by hand, and the same state as a profile in a
collapsed block for agents. The JSON is the source of truth; write the summary from it. List only what a tester
has to set up on purpose: leave out a fresh install, internal user and skipped onboarding, which every tester
does anyway. Use one item per line: each flag with ON/OFF and, if the name doesn't say it, what it changes; tabs
numbered in order with full URLs and the selected one marked.

````markdown
**Starting state**
- Feature flags:
  - `aiChatOmnibarDefaultPosition`: ON (Duck.ai setting for the address bar's starting mode)
  - `floatingUIiOS27`: OFF (classic toolbar)
- Open tabs (2):
  1. https://example.com/
  2. https://duckduckgo.com/ ← selected

<details><summary>Launch profile</summary>

```json
{
  "internalUser": true,
  "onboardingCompleted": true,
  "featureFlags": { "aiChatOmnibarDefaultPosition": true, "floatingUIiOS27": false },
  "tabs": ["https://example.com/", "https://duckduckgo.com/"]
}
```
</details>
````

## Adding a key

Every new Settings or Debug menu option that stores a value gets a launch key in the same PR.

1. Add a factory to the file for its area and list it in that file's group function:
   `+Settings.swift` (`settings.<name>`, `settingsScreen`), `+DuckAI.swift` (`duckAI.<name>`, `duckAI`) or
   `+Debug.swift` (`debug.<name>`, `debugMenu`). It takes only the store it writes.
2. Write through the API the screen uses (`AppSettings` or the feature's store). If it sends pixels, inject the
   pixel firer and pass none, like `AIChatUserSettingsStore` in `+DuckAI.swift`.
3. Use `LaunchSetting.choice` for enums. For other values, put checks that can fail in `validate` or `parse`, so a
   bad profile writes nothing. Don't use `setLaunchArgument` for settings: it hides changes the tester makes later.
4. If the store isn't in `IOSLaunchSettings.Dependencies`, add it there and in `LaunchProfileStartup`.
5. Test it in `IOSLaunchSettingsTests` by reading the value back through the store the screen reads, and add a
   row to the table above.

If the store can't be written before the app's services start (it needs `AppDependencyProvider`), split the
writes into a type that doesn't, as `AIChatUserSettingsStore` does, or skip the key and say why in the PR description.

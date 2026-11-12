# iPad and iPhone Duo windows

`iPadMultiWindow` is a launch-scoped flag under `iOSBrowserConfig`. Its default is disabled. Enable the `iPadMultiWindow` subfeature in the privacy-configuration repository for rollout; the rollout task URL is pending. The existing `fireMode` flag still controls Fire mode.

The browser menu offers **New Window** and, when Fire mode is enabled, **New Fire Window**. Availability follows UIKit's `supportsMultipleScenes`, so iPhone Duo uses the same implementation as iPad. The minimum deployment target is unchanged.

## Storage and clearing

- Each scene owns its coordinator, normal and Fire tab lists, tab selection, previews, and navigation restoration files. Existing tabs remain in the original window's storage; additional windows use their scene session identifiers.
- Every window has a distinct persistent Fire WebKit container and matching Fire Duck.ai native store. Closing the last Fire tab or clearing Fire mode affects that window. Contextual Duck.ai sheets use their originating tab's WebKit container.
- Regular website data, history, bookmarks, settings, Fireproof sites, downloads, and sync remain shared. Clearing one regular tab retains the existing domain-based behavior: shared site data can change in other regular windows. Other windows' tabs remain open.
- Clear all data runs against every window, including sessions UIKit has archived. Burns from different windows are serialized. All windows are covered during a global clear, and new scene connections wait for clearing to finish. Windows remain open with empty tab lists or a new tab.
- A manual global clear plays the selected Fire animation in every visible browser window. Saved-window restoration finishes before playback starts. Fire-mode and single-tab clears animate only their originating window. The clearing covers stay below the animation until every window finishes clearing. The deletion toast stays in the source window.
- Normal-window and Fire-window creation never clears existing browsing sessions. Auto-clear at launch is claimed once per process; inactivity timing starts only after the last foreground window backgrounds. Clearing saved windows before their views load skips UI updates while retaining data cleanup.
- Closing a scene discards its tabs and burns its Fire data. A temporary scene disconnection retains its state for reconnection. Scene restoration retains the selected browsing mode.

## Lifecycle choices

Shared app services resume when the first window foregrounds and suspend when the last one backgrounds. Scene launch cleanup, app authentication, width tracking, and first-responder lookup are separate for each window. Fire popovers and snapshot overlays use their presenting scene. Theme changes update all windows. Sync alerts, remote-message navigation, VPN subscription navigation, and the system-settings tutorial follow the most recently foregrounded window. History cleanup and subscription tab reporting read the combined window tab model. The Duck.ai menu reads recent chats from the focused window’s current mode and Fire store.

With multi-window enabled on a device that supports scenes, windows at least 678 points wide keep the tabs bar; narrower windows use the smaller chrome. This retains the original width threshold until the browser UI can adapt to narrower layouts, including expanded Duo windows. Each window tracks its own width. Flag-off single-window builds retain their existing layout policy. New tabs, browser borders, and privacy snapshots use the same window layout decision.

UIKit requires a static `UIApplicationSupportsMultipleScenes` opt-in. Consequently, system New Window controls may appear even with the flag off. New scene sessions are rejected and the existing window is activated. If the flag is disabled after use, already saved windows can still reconnect and remain included in global clearing; their tabs are preserved. New multi-window entry points are disabled. Changes to the rollout flag take effect after restarting the app. Additional windows are held back until startup onboarding finishes.

## Validation

Use a dedicated iPad or iPhone Duo simulator. In an internal build enable `iPadMultiWindow` and `fireMode`, then restart. For UI-test launch overrides use `UITEST_MODE=1`, `-isOnboardingCompleted true`, `-ff.iPadMultiWindow true`, and `-ff.fireMode true`.

1. Open regular and Fire windows from the browser menu. Switch modes in each window's tab switcher.
2. Set a cookie and local-storage value on the same origin in two Fire windows. Verify separate values and shared values between regular windows.
3. Clear one tab, then close the last Fire tab. Verify other windows keep their tabs and Fire data.
4. Clear all tabs and data from regular mode or Settings. Verify every window is empty, including a background window restored afterward.
5. Relaunch with multiple saved windows, background individual windows, and close a window. Verify restoration, app lock, and auto-clear settings.
6. Disable the flag and restart. Verify the window actions disappear and an OS request cannot attach an additional browser window.
7. Put two windows side by side. Clear all from either window and verify both animate; clear Fire mode or one tab and verify only the source window animates. Repeat with the animation setting set to None.
8. Resize a window through 678 points. Verify the tabs bar and toolbar change together, other windows keep their layouts, and a new tab uses the expected desktop/mobile preference.

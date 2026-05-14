# Update Analytics

Wide Event pixel tracking for measuring Sparkle update flow reliability and performance.

## Overview

The Update Analytics system tracks the complete lifecycle of Sparkle update flows using the Wide Event pixel framework. It measures timing, reliability, and failure modes across update phases (check, download, extraction, installation) to help diagnose update issues and measure update adoption rates.

**Sparkle Only**: Wide Event tracking is only available for direct download builds using Sparkle. App Store builds use simpler event-based pixels for version checks.

**Privacy-First**: All measurements are designed with privacy in mind, using bucketed time ranges instead of exact timestamps and limiting personally identifiable information.

## Architecture

``SparkleUpdateController`` emits lifecycle events into ``SparkleUpdateWideEvent``, which orchestrates a single active flow at a time, persists state via `WideEventManager`, and transmits the completed flow through PixelKit.

- ``SparkleUpdateWideEvent`` — Orchestrator. Drives one active flow, coordinates phase timing, and handles edge cases (overlapping flows, app termination, abandoned sessions).
- ``UpdateWideEventData`` — Data model. Holds from/to version and build, timing measurements per phase, cancellation reasons, error data, and system context (OS version, disk space, internal-user flag).

## Tracked Metrics

### Version Information

- **From Version/Build**: Current app version before update
- **To Version/Build**: Target update version (when found)
- **Update Type**: Regular or critical update

### Timing Measurements

All durations are measured in milliseconds:

- **Update Check Duration**: Time to fetch and parse appcast
- **Download Duration**: Time to download update package
- **Extraction Duration**: Time to extract and validate update
- **Total Duration**: Complete flow from start to completion/cancellation

**Incomplete Intervals**: If a timing measurement isn't completed before the flow ends (e.g., download started but not completed), it won't be included in the pixel.

### User Context

- **Initiation Type**: `automatic` (background check) or `manual` (user-triggered)
- **Update Configuration**: User's automatic updates preference (`automatic` or `manual`)
- **Internal User**: Whether user is DuckDuckGo internal employee
- **OS Version**: macOS version string
- **Time Since Last Update**: Bucketed time range (privacy-safe)

### Flow Status

- **Last Known Step**: Final milestone reached before flow ended
  - `updateCheckStarted`, `updateFound`, `noUpdateFound`
  - `downloadStarted`, `downloadCompleted`
  - `extractionStarted`, `extractionCompleted`
  - `readyToInstall`

- **Cancellation Reason** (if applicable):
  - `appQuit` - App terminated during update
  - `settingsChanged` - Automatic updates toggled off
  - `buildExpired` - Current build too old to update
  - `newCheckStarted` - New check interrupted previous flow

### Failure Context

**Disk Space Remaining**: Captured only on failures to help diagnose insufficient disk space issues. Uses `volumeAvailableCapacityForImportantUsage` which excludes purgeable content.

**Error Data**: Standard Wide Event error information (domain, code, description) when failures occur.

## Update Flow Lifecycle

### 1. Flow Start

An update check (automatic or manual) calls `startFlow(initiationType:)`. The orchestrator builds a fresh ``UpdateWideEventData`` capturing the current version and build, the initiation type, the user's automatic-updates configuration, and the internal-user flag, then starts the `totalDuration` and `updateCheckDuration` timers.

### 2. Phase Tracking

As the update progresses, the controller calls hooks on the orchestrator that mark the last-known step and bracket each phase timer:

- Update check — `didStartUpdateCheck()`, then `didFindUpdate()` or `didFindNoUpdate()` closes `updateCheckDuration`.
- Download — `didStartDownload()` opens `downloadDuration`; `didCompleteDownload()` closes it.
- Extraction — `didStartExtraction()` opens `extractionDuration`; `didCompleteExtraction()` closes it.
- Ready to install — `didBecomeReadyToInstall()` marks the terminal step before user install.

### 3. Flow Completion

The flow ends in one of three ways:

- **Success** — `completeFlow(status: .success)` after the app installs and restarts.
- **Failure** — `completeFlow(status: .failure, error:)` captures disk space at failure time and includes error details.
- **Cancellation** — `cancelFlow(reason:)` records `.appQuit`, `.settingsChanged`, `.buildExpired`, or `.newCheckStarted`.

## Edge Cases

### Overlapping Flows

When a new update check starts while a previous flow is still pending:

1. The existing flow is completed as `.unknown(reason: "incomplete")`
2. The new flow starts with fresh tracking
3. Prevents accumulation of orphaned flows

**Example**: User manually checks for updates while automatic background check is in progress.

### App Termination

When the app terminates with an active update flow:

1. `handleAppTermination()` is called from `AppDelegate`
2. Active flow is cancelled with `reason: .appQuit`
3. Distinguishes graceful quits from crashes/force quits
4. Pixel fired immediately before app fully terminates

### Abandoned Flows

At app launch, any pending flows from previous sessions are considered abandoned:

1. `cleanupAbandonedFlows()` checks for pending flows
2. Marks them as `.unknown(reason: "abandoned")`
3. Helps measure reliability across app crashes or system shutdowns

## Privacy Considerations

### Time Bucketing

Instead of exact timestamps, "time since last update" uses privacy-safe buckets:

- `<30m`, `<2h`, `<6h`, `<1d`, `<2d`, `<1w`, `<1M`, `>=1M`

This provides useful update frequency data without revealing exact user behavior patterns.

### Internal User Flag

The `isInternalUser` flag helps separate employee testing data from real user metrics, allowing more accurate analysis of user experience.

### String Encoding

All numeric values (durations, disk space, timestamps) are encoded as strings in pixel parameters to prevent overflow issues and ensure consistent transmission.

## Integration with Updates System

### SparkleUpdateController Integration

``SparkleUpdateController`` creates a ``SparkleUpdateWideEvent`` on init, calls `startFlow()` when a check begins, drives the per-phase hooks (`didStartDownload()`, `didCompleteDownload()`, and so on), calls `completeFlow()` or `cancelFlow()` on completion, and forwards `handleAppTermination()` when the agent quits.

### WideEventManager

Uses the shared `WideEventManager` from PixelKit for:
- Persisting flow data across app sessions
- Transmitting completed flows as pixels
- Managing retry logic for failed transmissions

### Pixel Name

The wide event pixel is identified as: `sparkle_update_cycle`

## Testing and Debugging

### Debug Logging

Update wide events log to the `updates` subsystem via `Logger.updates`. Filter Console.app for the `updates` subsystem to see wide-event activity, including success completion and transmission failures.

### Manual Testing

To test wide event tracking:
1. Enable internal user mode
2. Trigger manual update check
3. Observe flow progression in logs
4. Verify pixel transmission after flow completes

### Common Issues

**Flow Not Completing**: If a flow doesn't complete, check:
- Was `completeFlow()` or `cancelFlow()` called?
- Did the app terminate before completion?
- Check for abandoned flows on next launch

**Missing Timing Data**: If timing measurements are missing:
- Verify `.startingNow()` was called to start the timer
- Verify `.complete()` was called to finish the measurement
- Incomplete timers won't appear in pixel parameters

## Related Topics

- <doc:Updates> - Main updates architecture and integration
- `WideEventManager` (PixelKit) - Persistence and transmission framework


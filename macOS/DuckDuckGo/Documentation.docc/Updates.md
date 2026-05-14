# Updates

App update checking and installation with dual-distribution support for Sparkle and App Store builds.

## Overview

The Updates system manages checking for, downloading, and installing app updates across two distribution channels: direct downloads (using Sparkle framework) and Mac App Store releases. The architecture abstracts these different update mechanisms behind a unified `UpdateController` protocol, allowing the rest of the app to work with updates regardless of distribution method.

**Direct Download (Sparkle) Builds:**
- Full update lifecycle management: check, download, extract, install, relaunch
- Automatic background downloads and installation
- Local release notes display in browser tabs
- Gradual rollout support with percentage-based distribution

**App Store Builds:**
- Cloud-based version checking against DuckDuckGo's release metadata API
- Redirect to Mac App Store for installation
- Limited update state (check/notify only, no download/install)
- Automatic updates controlled by macOS System Settings

## Architecture

### Core Protocol

The ``UpdateController`` protocol exposes the published state the UI binds to (`latestUpdate`, `hasPendingUpdate`, `needsNotificationDot`, `updateProgress`, `areAutomaticUpdatesEnabled`) and the actions callers invoke (`checkForUpdateSkippingRollout()`, `runUpdate()`, `openUpdatesPage()`). The rest of the app depends on this protocol, not on a specific distribution.

### Distribution Implementations

Two implementations conform to ``UpdateController``:

- ``SparkleUpdateController`` — Drives Sparkle's `SUUpdater`, the `ApplicationUpdateDetector`, the `UpdateUserDriver`, and `ReleaseNotesParser`. Owns the full check → download → extract → install flow.
- ``AppStoreUpdateController`` — Calls `LatestReleaseChecker` against DuckDuckGo's release metadata API, gated by feature flags, and uses `AppStoreOpener` to hand off to the Mac App Store.

## Key Components

### Core Protocol and Implementations

- **`UpdateController`** - Updates module
  - Protocol defining unified update interface
  - Published properties for reactive UI updates
  - Platform-agnostic update actions

- **`SparkleUpdateController`** - Updates module
  - Full-featured update controller for direct downloads
  - Integrates with Sparkle framework for download/install
  - Manages release notes, update validation, and restart coordination

- **`AppStoreUpdateController`** - Updates module
  - Lightweight controller for App Store builds
  - Cloud-based version checking via release metadata API
  - Redirects to App Store for actual updates

### Update State Management

- **`Update`** - Updates module
  - Represents available update information
  - Version, build, release date, release notes
  - Update type (regular vs critical)

- **`UpdateCycleProgress`** - Updates module
  - Tracks update process state machine
  - States: not started, checking, downloading, ready to install, done, error
  - Download progress percentage (Sparkle only)

- **`UpdateCheckState`** - Updates module
  - Rate limiting for automatic update checks
  - Prevents excessive API/appcast requests
  - Typically enforces 24-hour intervals

- **`UpdateCheckActor`** - Updates module
  - Actor-based concurrency for update checks
  - Prevents concurrent update check races

### Release Notes (Sparkle Only)

- **`ReleaseNotesTabExtension`** - Updates module
  - Tab extension for displaying release notes
  - Monitors update state and pushes to JavaScript
  - Shows download progress and installation status

- **`ReleaseNotesUserScript`** - Updates module
  - JavaScript injection for release notes page
  - Bidirectional communication with tab extension
  - Handles "Install & Restart" actions from UI

- **`ReleaseNotesParser`** - Updates module
  - Parses HTML release notes from Sparkle appcast
  - Separates standard and subscription-specific notes

### Notification and UI Integration

- **`UpdateNotificationPresenter`** - Updates module
  - Displays banner notifications for available updates
  - Shows near navigation bar options button
  - Different text for critical vs regular updates
  - Rate-limited to once per 7 days per update

- **`SparkleUpdateMenuItemFactory`** / **`AppStoreUpdateMenuItemFactory`** - Updates module
  - Creates menu items for "Check for Updates"
  - Adds notification dots when updates available
  - Distribution-specific menu text and behavior

## Integration Points

### Menu System

The Updates system integrates with the main menu to provide update actions and visual indicators:

- **"Check for Updates" Menu Item**: Triggers immediate update check bypassing rollout restrictions and rate limits
- **Notification Dots**: Blue dots appear on main menu and Settings gear icon when updates are available
- **Menu Item State**: Enabled/disabled based on update availability and progress

### Preferences Integration

The Settings > About section displays update information and controls:

- **Version Display**: Current version and build number
- **Last Check Date**: Timestamp of most recent update check
- **Update Button**: "Update DuckDuckGo" button (enabled when update available)
- **Automatic Updates Toggle**: For Sparkle builds only
- **Update Progress**: Download/install progress indicators (Sparkle only)

### Tab Extensions

**Sparkle Builds Only**: Release notes are displayed in dedicated browser tabs:

- Special URL scheme triggers release notes tab
- Real-time update progress display
- JavaScript-driven UI for release note content
- "Install & Restart" button integration

## Update Flow

### Sparkle Build Flow

A check (automatic or manual) downloads and parses the appcast, compares versions and applies the rollout filter, downloads the update package if automatic updates are on, extracts and validates the package, and notifies the user via a banner and menu dot. When the user picks "Update DuckDuckGo" or "Install & Restart", Sparkle installs the update and relaunches the app.

### App Store Build Flow

A check calls the release-metadata cloud API, runs a semantic version comparison, and notifies the user. The "Update DuckDuckGo" action opens the Mac App Store page; the App Store itself handles the actual install.

## Update Types

### Regular Updates

Standard feature releases and bug fixes:
- Notification: "New version available. [action]"
- No forced installation
- User can dismiss and update later

### Critical Updates

Security patches or critical bug fixes:
- Notification: "Critical update needed. [action]"
- More prominent notification styling
- Marked as critical in appcast XML or release metadata

## Common Tasks

### Testing Update Notifications

Use internal debug settings to simulate update availability without actual updates. See `UpdatesDebugSettings` for available options.

### Debugging Update Flows

**Sparkle Builds:**
- Check Console.app for Sparkle framework logs
- Use Sparkle's built-in debug logging
- Verify appcast XML parsing with `ReleaseNotesParser`

**App Store Builds:**
- Monitor cloud API requests in network logs
- Verify feature flag state for update flow
- Check version comparison logic with semantic versioning

### Gradual Rollout (Sparkle Only)

Updates can be rolled out gradually to a percentage of users:
- Configured in appcast XML with rollout percentage
- Manual "Check for Updates" bypasses rollout restrictions
- Internal users typically bypass rollout automatically

### Release Notes Content

Release notes are authored in HTML and embedded in Sparkle appcast:
- Standard notes: Shown to all users
- Subscription notes: Shown only to Privacy Pro subscribers
- Parsed and separated by `ReleaseNotesParser`

## Analytics and Monitoring

### Wide Event Tracking (Sparkle Only)

Sparkle builds track complete update flow lifecycle using Wide Event pixels to measure reliability, performance, and failure modes. This includes timing measurements for each phase (check, download, extraction), cancellation reasons, and system context.

See <doc:UpdateAnalytics> for complete wide event tracking documentation.

## Related Topics

- <doc:UpdateAnalytics> - Wide Event pixel tracking for update flows
- <doc:MenuSystem> - Menu bar integration and notification dots
- <doc:Preferences> - Settings UI for update controls
- <doc:TabManagement> - Release notes tab extension integration


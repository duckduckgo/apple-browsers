# Privacy Features

Content blocking, tracker detection, and privacy protections are core to DuckDuckGo.

## Overview

The DuckDuckGo macOS browser implements comprehensive privacy protections through multiple coordinated systems. At the heart of these features is a content blocking pipeline that compiles tracker blocking rules and applies them to web content using WebKit's content blocking API. This system works in conjunction with privacy reporting, the Privacy Dashboard, and various other privacy features to provide transparent, effective protection.

The privacy architecture is designed for flexibility and extensibility, allowing new protections to be added while maintaining clear separation of concerns. Configuration is managed remotely, allowing real-time updates to protection rules without requiring app updates.

For the underlying protocol APIs (``ContentBlockerRulesManager``, ``TrackerDataManager``, ``PrivacyConfigurationManager``), see the BrowserServicesKit package documentation.

## Architecture

### Content Blocking Pipeline

Remote configuration (privacy config and the Tracker Data Set) feeds the package-level managers, which orchestrate rule compilation through WebKit's content rule list store. Compiled rules are cached, then applied per-tab via a content blocking tab extension that records blocked trackers for the Privacy Dashboard.

### Key Components

- ``AppContentBlocking`` — central app-side coordinator that wires the package-level managers together, initializes the rules pipeline, and publishes content blocking updates.
- ``ContentBlockerRulesManager`` (BrowserServicesKit) — orchestrates rule compilation, manages compilation state and queuing, and coordinates with WebKit's content rule store.
- ``TrackerDataManager`` (BrowserServicesKit) — manages the Tracker Data Set, handles remote updates and etags, and provides tracker information for blocking decisions.
- ``PrivacyConfigurationManager`` (BrowserServicesKit) — manages privacy feature configuration, determines which features are enabled per-site, and handles unprotected domains.
- ``ContentBlockingTabExtension`` — per-tab privacy protection state. Tracks blocked trackers and feeds the Privacy Dashboard with data.

## How Compilation Works

Content blocking rule compilation is a multi-stage process triggered when the Tracker Data Set or privacy configuration updates.

1. The rules manager schedules compilation, returning a completion token. Concurrent requests are queued rather than run in parallel.
2. Per-list source managers are prepared — the main Tracker Data Set rules, ad click attribution rules extracted from the TDS, and any additional rules lists.
3. Each rules list is converted to JSON and compiled via WebKit's content rule list store. Compiled rules are cached by identifier.
4. After all compilations finish, the current rules set is updated and an update event is published through Combine.
5. Each tab observes the update, removes old rule lists from its `WKWebView`, adds the new compiled lists, and reloads if necessary.

Compilation is expensive — WebKit compilation can take 1–2 seconds for large rule sets — so caching and queuing matter. See ``ContentBlockerRulesManager`` in BrowserServicesKit for the state machine details.

## Adding a New Privacy Protection Feature

1. Define the feature in the remote privacy configuration with feature flags and site-specific exceptions.
2. Check feature state through ``PrivacyConfigurationManager``.
3. Implement a rules source conforming to ``ContentBlockerRulesListsSource`` (see the BrowserServicesKit package docs for the protocol contract).
4. Register the rules source with ``ContentBlockerRulesManager`` during initialization. ``AppContentBlocking`` is the wiring point in the macOS app.
5. Optionally add a `TabExtension` to track per-tab state. ``ContentBlockingTabExtension`` is the canonical example.

## Accessing Privacy Information for a Tab

Privacy state is exposed through the ``Tab`` public interface: `tab.contentBlocking` for blocking state and `tab.privacyInfo` for dashboard data. See ``ContentBlockingTabExtension`` and ``PrivacyDashboardTabExtension`` for the properties they publish.

## Debugging Content Blocking

**Tracker not blocked**: check whether the domain is in the unprotected list, that the tracker is in the Tracker Data Set with the expected rules, and that no privacy configuration feature toggle disables it. Compiled rules JSON can be inspected for confirmation.

**Compilation failing**: check logs for WebKit compilation errors and verify JSON rule syntax. WebKit enforces rule count limits, and conflicting rules can also break compilation.

**Performance issues**: monitor compilation time via the Content Blocking Assets Time Reporter, check rule counts (fewer, more targeted rules perform better), and verify the rules cache is being used.

## Patterns and Best Practices

- Always respect privacy configuration — check ``PrivacyConfigurationManager`` before applying protections. Sites can be temporarily or permanently unprotected.
- Test with both embedded and remote configs to ensure fallback works.
- Use completion tokens from the rules manager to avoid redundant compilation work.
- Don't compile rules until they're actually needed; allow users to keep browsing while rules update; apply new rules at navigation boundaries.

### Testing

Test privacy features using mock implementations of ``PrivacyConfigurationManager`` and ``TrackerDataManager`` to verify content blocking behavior in isolation.

## Privacy Dashboard Integration

The Privacy Dashboard surfaces tracker blocking and protection state to the user.

``PrivacyDashboardViewController`` hosts the dashboard UI. It receives aggregated data from ``PrivacyDashboardTabExtension``, which in turn reads blocking state from ``ContentBlockingTabExtension`` and the per-tab ``PrivacyInfo`` model.

The dashboard displays:

- **Protection status** — whether protections are active for the current site.
- **Blocked trackers** — list of trackers blocked on the current page.
- **Tracker networks** — entities owning the blocked trackers.
- **Site grade** — privacy grade before and after protections.
- **Unprotected toggle** — user control to disable protections per-site.

### Extending the Dashboard

1. Update the ``PrivacyInfo`` model with the new data.
2. Modify ``PrivacyDashboardTabExtension`` to provide the data.
3. Update ``PrivacyDashboardViewController`` UI if needed.
4. Consider whether the data should influence site grade.

## Related Topics

- <doc:TabManagement> — tab architecture and extensions
- <doc:UserScripts> — JavaScript injection for privacy features
- ``ContentBlockerRulesManager`` — rules compilation engine
- ``PrivacyConfigurationManager`` — feature configuration
- ``TrackerDataManager`` — tracker data management

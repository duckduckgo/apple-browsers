# User Scripts

How the macOS app composes user scripts to add privacy, autofill, special pages, and other features to web content.

## Overview

The macOS browser uses user scripts extensively to add functionality to web pages. They run in isolated JavaScript contexts and provide bidirectional communication between native code and web content. This article describes how the app wires those scripts up. For the protocol contract, lifecycle, and message-broker patterns, see <doc:UserScript> in BrowserServicesKit.

## Architecture

### UserScripts provider

The ``UserScripts`` class is the central provider that owns every user script the app injects into a regular browsing tab. It is constructed per tab from a `ScriptSourceProviding` source, exposes a flat `userScripts` array, and is consumed by the `Tab` to populate its `WKUserContentController`.

At a high level the provider holds three categories:

- **Content Scope Scripts hosts** — ``ContentScopeUserScript`` (page world, restricted) and a second instance running in the isolated world. Most privacy and product features are registered as **Subfeatures** of one of these two hosts rather than as independent user scripts.
- **Independent user scripts** — a small number of dedicated scripts such as ``WebsiteAutofillUserScript``, ``AutoconsentUserScript``, ``SubscriptionPagesUserScript``, and ``IdentityTheftRestorationPagesUserScript``.
- **``SpecialPagesUserScript``** — the host for internal DuckDuckGo pages (Duck Player, onboarding, release notes, history view, error pages).

The new tab page is a separate path: it lives in its own `WKWebView` managed by `NewTabPageWebViewModel` and a dedicated `NewTabPageUserContentController`, not in the main `UserScripts` provider.

```
UserScripts (provider)
├── ContentScopeUserScript           (page world host)
│   ├── PageContextUserScript        (feature-flagged: .aiChatPageContext)
│   └── TrackerProtectionSubfeature
├── ContentScopeUserScript (isolated)
│   ├── WebTelemetryUserScript
│   ├── WebEventsSubfeature
│   ├── FaviconUserScript
│   ├── TabSuspensionUserScript
│   ├── ContextMenuSubfeature
│   ├── PageObserverUserScript
│   ├── HoverUserScript
│   ├── ClickToLoadUserScript
│   ├── AIChatUserScript             (optional)
│   ├── SubscriptionUserScript       (optional)
│   ├── YoutubeOverlayUserScript     (when DuckPlayer is available)
│   ├── SERPSettingsUserScript
│   └── DuckAiNativeStorageUserScript (feature-flagged)
├── SpecialPagesUserScript
│   ├── SpecialErrorPageUserScript
│   ├── YoutubePlayerUserScript      (when DuckPlayer is available)
│   ├── ReleaseNotesUserScript       (Sparkle builds only)
│   ├── OnboardingUserScript
│   └── HistoryViewUserScript
├── WebsiteAutofillUserScript
├── AutoconsentUserScript            (unless web extension provides autoconsent)
├── SubscriptionPagesUserScript
└── IdentityTheftRestorationPagesUserScript
```

Printing for special pages is handled by ``PrintingSubfeature`` from BrowserServicesKit; the macOS app does not maintain its own printing user script.

### Integration with tabs

User scripts are loaded when a `Tab` creates its `WKWebView`. The tab requests the script list from ``UserScripts``, the provider produces `WKUserScript` instances via `loadWKUserScripts()`, and the tab registers them with the WebView's content controller along with their message handlers.

```
Tab creation → request UserScripts → configure WKUserContentController → add message handlers → inject scripts
```

## Security and isolation

### Content worlds

User scripts execute in one of two JavaScript contexts:

- **Isolated world** (`.defaultClient`) — the default. Page JavaScript cannot read or tamper with the script, and the script cannot read page globals. Almost everything in the app uses this world.
- **Page world** (`.page`) — shares the page's JavaScript context. Required only when the script needs to read page globals (e.g. ``PageContextUserScript`` for AI Chat). Comes with security and stability trade-offs.

### Message origin policies

User scripts and subfeatures enforce a `MessageOriginPolicy` that restricts which domains may invoke their handlers. The app convention is `.only(rules: [...])` with explicit hostnames; `.all` is reserved for scripts that genuinely run anywhere (such as global content-scope subfeatures). See <doc:UserScript> for the policy types.

### Security considerations

When implementing a new user script:

1. Default to the isolated world; only opt into the page world when there is no alternative.
2. Use `.only(rules:)` origin policies with the narrowest hostname set that works.
3. Treat all data coming from web content as untrusted: validate types, decode through `Codable`, and reject unexpected frame contexts.
4. Keep credentials and secrets in native code — never embed them in JavaScript sources.
5. Apply timeouts to any operation that waits on a JavaScript response.
6. Surface only generic error messages to the page; log details natively.

## Key user scripts

### Privacy and content blocking

- ``ContentScopeUserScript`` — the host for Content Scope Scripts (C-S-S). The app creates two instances: a page-world one (with a narrow allow-list of non-isolated features) and an isolated-world one that hosts the bulk of subfeatures. Configuration is generated by `ContentScopePrivacyConfigurationJSONGenerator` and bundles `ContentScopeProperties` such as GPC state, session key, theme, and experiment cohorts.
- ``TrackerProtectionSubfeature`` — registered on the page-world ``ContentScopeUserScript`` to apply content-blocking rules and surrogate substitution. Surrogate tracker data is supplied through `scriptContext: .contentScope(surrogateTrackerData:)` rather than as a separate user script.
- ``AutoconsentUserScript`` — automatically dismisses or interacts with cookie-consent dialogs. The app only registers it when no web extension is providing autoconsent.

### Forms and autofill

- ``WebsiteAutofillUserScript`` — password, identity, and credit-card autofill. Lives in BrowserServicesKit and integrates with the macOS SecureVault.

### Special pages and product features

- ``SpecialPagesUserScript`` — the host for DuckDuckGo's internal pages. Subfeatures cover error pages (``SpecialErrorPageUserScript``), onboarding (``OnboardingUserScript``), the history view (``HistoryViewUserScript``), the Duck Player page (``YoutubePlayerUserScript``), and Sparkle-only release notes.
- ``NewTabPageUserScript`` — powers the new tab page. It is **not** registered through ``UserScripts`` or ``SpecialPagesUserScript``; it is installed by `NewTabPageWebViewModel` into a dedicated `WKWebView` via `NewTabPageUserContentController`, with `NewTabPageActionsManager` brokering messages.
- ``AIChatUserScript`` — AI Chat integration, registered as a subfeature of the isolated ``ContentScopeUserScript``. Wires together `DefaultAIChatPreferencesStorage`, `AIChatMessageHandler`, and PixelKit.
- ``PageContextUserScript`` — extracts page context for AI Chat. Registered on the page-world ``ContentScopeUserScript`` (not the isolated one) because it needs page-context access. Gated on the `.aiChatPageContext` feature flag.
- ``SERPSettingsUserScript`` — customizes the search results page through `SERPSettingsProvider`.

### Subscription and premium features

- ``SubscriptionUserScript`` — exposes subscription state and paid features (including paid AI Chat). Registered with the isolated ``ContentScopeUserScript`` and configured via `SubscriptionUserScriptFeatureFlagAdapter` and the `SubscriptionNavigationCoordinator`.
- ``SubscriptionPagesUserScript`` — hosts subscription management pages with `SubscriptionPagesUseSubscriptionFeature` as a subfeature.
- ``IdentityTheftRestorationPagesUserScript`` — hosts the Identity Theft Restoration product pages.

### Media

- ``ClickToLoadUserScript`` — replaces embedded third-party content (YouTube, Facebook, etc.) with privacy-respecting placeholders. Registered as a subfeature of the isolated ``ContentScopeUserScript``.
- ``YoutubeOverlayUserScript`` — offers Duck Player as an alternative on YouTube; registered with the isolated ``ContentScopeUserScript`` when Duck Player is available.
- ``YoutubePlayerUserScript`` — drives the Duck Player page itself; registered as a subfeature of ``SpecialPagesUserScript``.

### Page interaction and UI

- ``PageObserverUserScript`` — tracks page-lifecycle events (load, DOM-ready, navigation) for coordination with the `Tab`. Registered as a subfeature of the isolated ``ContentScopeUserScript``.
- ``ContextMenuSubfeature`` — adds custom items to the web-content context menu via the isolated ``ContentScopeUserScript``.
- ``HoverUserScript`` — surfaces hover state from the page to native code (used to display link previews and similar UI affordances).
- ``FaviconUserScript`` — detects favicons declared by the page for the favicon manager.
- ``TabSuspensionUserScript`` — coordinates tab-suspension behavior with the page.
- ``WebTelemetryUserScript`` and ``WebEventsSubfeature`` — collect privacy-respecting telemetry (currently used for YouTube ad-blocking analytics when the user opts in).
- ``DuckAiNativeStorageUserScript`` — bridges native storage to `duck.ai` when the corresponding feature flag and handler are both available.

## Adding a new user script

1. Decide whether the new feature is a standalone ``UserScript`` or a ``Subfeature`` of an existing C-S-S host. New product features almost always belong as a subfeature of the isolated ``ContentScopeUserScript`` or ``SpecialPagesUserScript``.
2. Implement the protocol from the package (`UserScript`, `UserScriptMessaging`, or `Subfeature`) — see <doc:UserScript> for the patterns and message-broker setup.
3. Place the JavaScript source in the appropriate Resources folder so `Self.loadJS(_:from:withReplacements:)` can find it.
4. Construct the script in ``UserScripts/init`` and either register it as a subfeature with `registerSubfeature(delegate:)` or append it to `userScripts` if it must be installed independently.
5. Add unit tests against the message handler using mock `WKScriptMessage` / `WKUserContentController` instances.

User scripts are loaded automatically when tabs are created; no separate plumbing in the tab is required for subfeatures.

## Message handling

The package documentation (<doc:UserScript>) covers the message-broker pattern, async responses, `Codable`-based dispatch, and origin validation in detail. The app-specific conventions on top of that are:

- Subfeatures of ``ContentScopeUserScript`` use the shared C-S-S broker; their handlers are dispatched by `featureName` and `methodName`.
- Pages hosted by ``SpecialPagesUserScript`` follow the same pattern, with each page (history view, onboarding, Duck Player, etc.) implemented as a subfeature.
- Standalone scripts (``WebsiteAutofillUserScript``, ``AutoconsentUserScript``, ``SubscriptionPagesUserScript``, ``IdentityTheftRestorationPagesUserScript``) implement `WKScriptMessageHandler` directly and dispatch on `message.name`.

### Communication flow for special pages

```
SwiftUI view → ViewModel → SpecialPagesUserScript subfeature → JavaScript
JavaScript event → WKScriptMessage → Subfeature handler → SwiftUI state update
```

## Content Scope Scripts

Content Scope Scripts (C-S-S) is DuckDuckGo's cross-platform JavaScript codebase for privacy features. It is integrated as a submodule, bundled at build time by `copy-content-scope-scripts.js`, and loaded by ``ContentScopeUserScript`` together with the per-instance `ContentScopeProperties`. Most macOS privacy and product features ride on top of C-S-S as subfeatures rather than as independent user scripts.

## Performance considerations

- **Injection time** — `.atDocumentStart` runs before page scripts (use for blocking, content scope, and feature toggles); `.atDocumentEnd` runs after the DOM is ready (use for features that read the rendered page).
- **Message volume** — debounce or throttle handlers that respond to high-frequency events such as keystrokes or scroll.
- **Async work** — never block the main thread inside a message handler; dispatch to a `Task` and await results.
- **Memory** — clean up listeners and timers on navigation. Most subfeatures don't need manual cleanup; standalone scripts that retain state in JavaScript should expose a `cleanup` entry point that the navigation delegate can invoke.

## Debugging

Safari Web Inspector is the primary tool: enable the Develop menu in Safari, then attach to the DuckDuckGo process to inspect injected scripts, console output, and message traffic.

Common diagnoses:

- **Script not running** — verify the subfeature is registered in ``UserScripts/init``; check the `featureName` and feature-flag gating; confirm `injectionTime`.
- **Messages not received** — check `messageOriginPolicy` matches the page's origin; confirm `message.frameInfo.isMainFrame` if the handler expects only main-frame messages; ensure the method name matches between JavaScript and the handler dispatcher.
- **Page world vs isolated world mismatch** — isolated-world scripts cannot read page globals; route those requests through a separate `requiresRunInPageContentWorld` script (with origin restrictions) or expose the data from native code.

## Key files

- ``UserScripts`` — the provider that wires the dependency graph for every regular browsing tab.
- ``ContentScopeUserScript`` (BrowserServicesKit) — host for the bulk of privacy and product subfeatures.
- ``SpecialPagesUserScript`` — host for internal DuckDuckGo pages.
- ``WebsiteAutofillUserScript`` (BrowserServicesKit) — autofill entry point.
- `NewTabPageWebViewModel` and `NewTabPageUserContentController` — the separate new-tab-page path.

## Related Topics

- <doc:UserScript> — protocol contract, message broker, and subfeature patterns (BrowserServicesKit package)
- <doc:TabManagement> — how tabs consume the user-script provider
- <doc:PrivacyFeatures> — privacy features delivered through Content Scope Scripts

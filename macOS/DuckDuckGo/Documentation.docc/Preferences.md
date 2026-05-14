# Preferences

Settings UI organization, user preference persistence, and the `@UserDefaultsWrapper` pattern.

## Overview

The preferences system in the DuckDuckGo macOS browser provides a comprehensive settings interface organized into sections and panes. Built with SwiftUI and backed by `UserDefaults`, it follows a sidebar-content pattern where users navigate through sections (Privacy Protections, Subscription, General Settings, About) and select specific preference panes.

The architecture uses the `@UserDefaultsWrapper` property wrapper for seamless persistence, ``PreferencesSection`` for organizational structure, and dynamically adjusts available panes based on subscription status and feature flags. The system is designed to be easily extensible for new settings and features.

## Architecture

```
PreferencesViewController (Host)
├── PreferencesSidebarModel (Navigation)
│   ├── sections: [PreferencesSection]
│   └── selectedPane: PreferencePaneIdentifier
├── PreferencesSidebar (SwiftUI)
│   └── Sidebar navigation UI
└── Content Panes (SwiftUI Views)

Data Persistence
└── @UserDefaultsWrapper
    └── Per-feature preference objects (AppearancePreferences, StartupPreferences, …)
```

### Organizational Structure

The sidebar is structured around two enums:

- ``PreferencesSectionIdentifier`` defines the grouping of panes in the sidebar (privacy protections, subscription-related groupings, regular preferences, about). Refer to the enum for the current set of section identifiers — subscription state and feature flags determine which sections appear at runtime.
- ``PreferencePaneIdentifier`` defines individual panes. Representative examples include `general`, `privateSearch`, `vpn`, `subscription`, `sync`, and `appearance`, but the enum is the source of truth for the full, current list (it evolves as features ship). Refer to ``PreferencePaneIdentifier`` directly rather than maintaining a parallel list here.

Available panes adjust dynamically based on ``PreferencesSidebarSubscriptionState`` and feature flags — for example, subscription-gated panes only appear for entitled users.

## Key Components

### Core Controllers

- ``PreferencesViewController`` — main preferences window controller. Hosts the SwiftUI preferences interface and manages preference pane navigation.
- ``PreferencesSidebarModel`` — sidebar state and navigation. Owns section/pane management and integrates subscription state.

### Organization

- ``PreferencesSection`` — section and pane definitions. Houses the ``PreferencesSectionIdentifier`` and ``PreferencePaneIdentifier`` enums and dynamic section construction based on features.
- ``PreferencesSidebar`` — SwiftUI sidebar UI and navigation/selection handling.

### Preference Objects

Per-feature preference classes use `@UserDefaultsWrapper` for individual settings. Examples include ``AppearancePreferences``, ``StartupPreferences``, ``TabsPreferences``, ``DownloadsPreferences``, ``AutofillPreferences``, and ``CookiePopupProtectionPreferences``. New feature areas should add their own preferences class rather than extending an existing one.

### Pane Views

Each pane has a SwiftUI view (e.g. `PreferencesGeneralView`, `PreferencesAppearanceView`, `PreferencesPrivacyView`, `PreferencesAutofillView`). These follow a shared layout convention using `PreferencesContentView`, `PreferencesPaneTitle`, and `Form`. Refer to any existing pane view for the canonical pattern.

## Common Tasks

### Adding a New Preference Pane

1. Add a case to ``PreferencePaneIdentifier``.
2. Add the pane to the appropriate section in `defaultSections()` on ``PreferencesSection``.
3. Create a SwiftUI view for the pane using `PreferencesContentView` and `Form`.
4. Register the view in `PreferencesRootView`'s switch statement.

Reference existing pane views for the canonical implementation pattern.

### Creating Preferences with @UserDefaultsWrapper

Create an `ObservableObject` class with `@UserDefaultsWrapper`-decorated properties and define corresponding keys in `UserDefaultsPropertyName`. The wrapper supports any type conforming to the appropriate protocols (`String`, `Int`, `Bool`, `RawRepresentable` enums, etc.).

### Reading Preferences

Instantiate the preferences object in any `@MainActor` context or inject it as a dependency. The wrapper automatically reads from and writes to `UserDefaults`.

### Dynamic Sections

Preferences sections dynamically adjust based on ``PreferencesSidebarSubscriptionState``, showing or hiding subscription-related panes based on user entitlements.

### Feature Flags

Use feature flags in section construction to conditionally include panes. See `defaultSections()` on ``PreferencesSection`` for patterns.

## Patterns & Best Practices

### @UserDefaultsWrapper Pattern

The `@UserDefaultsWrapper` property wrapper provides automatic persistence, type-safe access, default values, optional change notifications, and testable `UserDefaults` access. See ``UserDefaultsWrapper`` for the implementation.

### Preference Object Design

Best practices:
1. One class per feature area (avoid monolithic classes)
2. Use `ObservableObject` for SwiftUI reactivity
3. Group related settings together
4. Always provide sensible defaults
5. Document non-obvious behavior

### Preferences UI Patterns

Use `Form` and `PreferencesSection` for layout. Wrap content in `PreferencesContentView` with `PreferencesPaneTitle` for consistent spacing.

### Navigation State Management

Open preferences to a specific pane by setting `selectedPane` on ``PreferencesSidebarModel`` or by using the `x-ddg-preferences:pane` URL scheme.

## Testing

Test preferences using an isolated `UserDefaults` suite to verify default values, persistence across instances, and `UserDefaults` key mapping.

## Related Topics

- ``PreferencesSidebarModel`` - Sidebar navigation state
- ``PreferencesSection`` - Section organization
- ``PreferencePaneIdentifier`` - Authoritative list of panes
- ``AppearancePreferences`` - Example per-feature preferences class
- ``UserDefaultsWrapper`` - Persistence property wrapper
- ``UserDefaultsPropertyName`` - Type-safe keys

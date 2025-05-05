# UIComponents

## Overview

UIComponents is a Swift Package designed to house reusable UI components for iOS and macOS. The goal is to create a single place for UI elements that can be shared across platforms, promoting consistency and efficiency.

## Dependencies

This package depends on [DesignResourceKit](https://github.com/duckduckgo/DesignResourcesKit), which provides the foundational Design System atoms. It is crucial to understand that:

- **Text should NOT be added to this package**; it should always be injected.
- **Design System elements are not to be added here**. The Design System should remain a consistent set of elements, and any constructs built using these atoms should reside outside of the Design System. For example, components like toasts or alerts, which are built from multiple atoms (colors, buttons, typefaces, spacings), should be implemented in this package rather than in the Design System.

## Guidelines

### What to Include

- **Reusable UI Components**: This package is intended for UI components that can be shared between iOS and macOS, such as:
  - Alerts
  - Buttons
  - Custom Views
  - Any other UI component that can be used across platforms.

### What to Exclude

- **Design System Elements**: As stated, elements that are part of the Design System should not be included in this package.
- **Storyboard and XIBs**: The use of Storyboards and XIBs is not permitted. Preference should be given to SwiftUI for building UI components. UIKit and AppKit are not forbidden, but if you choose to use them, please provide a technical design with the justification.

## Project Structure
The project is organized into the following folders:

```
UIComponents/
├── iOS/
│   └── [iOS-specific components]
├── macOS/
│   └── [macOS-specific components]
└── Shared/
    └── [components shared across platforms]
└── Resources/
    └── [assets shared across componenets]
```

When implementing components, always use `#if os(iOS)` or `#if os(macOS)` directives as necessary to ensure platform-specific code is correctly managed.


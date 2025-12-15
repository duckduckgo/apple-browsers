# SystemFrameworksExtensions

## Overview

This library contains extensions over Apple's Foundation and other system frameworks APIs such as `Combine`, `SwiftUI`, etc.

## Dependencies

This package should only depend on system frameworks and no other packages.

## What belongs here?

- General purpose extensions to Apple framework classes.

The mental test for deciding what belongs in `SystemFrameworksExtensions` is:
> Could this code be used unchanged in another application?

If the answer is yes, then it belongs in `SystemFrameworksExtensions`.

## What does not belong here?

- Frameworks extensions that are specific to the business domain or the application's feature set.
- UI components. Add that in the `UIComponents` framework.

## Platform-specific Extensions

When adding platform-specific extensions, you have two approaches:

### Option 1: Using `#if os(XX)` conditionals (Recommended for simple cases)

For straightforward platform differences, use compiler directives within the same target:

```swift
// In SwiftUIExtensions/View+PlatformSpecific.swift
import SwiftUI

extension View {
   func someViewModifier() -> some View {
      // macOS-specific implementation
      #if os(macOS)
      // Do Something for macOS
      #elseif os(iOS)
      // Do Something for iOS
      #endif
   }
}
```

Option 2: Proxy Target (For complex platform-specific modules)

For more complex platform-specific code that warrants separate modules, use the proxy target inspired by Firebase's approach (https://medium.com/@artem-kirienko/platform-specific-spm-targets-31ee9a48e124):

Swift Package Manager doesn't directly support per-target platforms. The solution is to create a "proxy" that conditionally includes the platform-specific code.

```swift
// In SwiftUIExtensions/View+PlatformSpecific.swift
  .platforms: [
    .iOS(.v15),
    .macOS(.v11),
  ],
  .products: [
     ...
    .library(
       name: "UIKitExtensions", 
       targets: ["UIKitExtensionsProxy"]
    ),
  ],
  .target(
      name: "UIKitExtensions", // Actual code lives here
  ),
  .target(
      name: "UIKitExtensionsProxy", // Proxy decides when to include it
      dependencies: [
          .target(
            name: "UIKitExtensions", 
            condition: .when(platforms: [.iOS])
          ) 
      ]
  ),
```

The Magic:
  - Client imports UIKitExtensions.
  - SPM builds UIKitExtensionsProxy.
  - Proxy conditionally includes the real UIKitExtensions target.
  - On iOS: Gets the real UIKit code.
  - On macOS: Gets nothing (proxy is empty).

## Project Structure
The project is organized into the following folders:

```
SystemFrameworksExtensions/
    ├── Package.swift
    ├── README.md
    └── Sources/
        ├── FoundationExtensions/
            └── // no Package.swift here because it’s just a module
            └── README.md
            └── DateExtension.swift
            └── URLExtension.swift
        ├── CombineExtensions/
            └── README.md
        │   └── // same here and in the rest
        ├── SwiftUIExtensions/
        ├── AppKitExtensions/
        └── UIKitExtensions/
```

# MetricBuilder

A library designed for building responsive metrics that adapt to different iOS device types, screen sizes, and orientations.

## Overview

MetricBuilder provides an API for defining values that automatically adjust based on the current device context. Whether you're setting padding, font sizes, image dimensions, or any other metric, MetricBuilder ensures your UI looks great on all iOS devices.

### Key Features

- 🧰 **Generic** - Works with any type (CGFloat, Font, Bool, etc.)
- 📱 **Device-specific values** - Different metrics for iPhone and iPad
- 🔄 **Orientation awareness** - Separate values for portrait and landscape
- 📐 **Small screen support** - Special handling for compact devices like iPhone SE
- 🧪 **Testable** - Inject custom screen bounds for unit testing

### Basic Usage

```swift
// Simple device-specific padding
let padding = MetricBuilder(iPhone: 16, iPad: 24)
    .build(v: verticalSizeClass, h: horizontalSizeClass)

// Complex responsive layout
let imageSize = MetricBuilder(iPhone: 100, iPad: 200)
    .iPhone(landscape: 150)
    .iPad(landscape: 250)
    .iPhoneSmallScreen(80)
    .build(v: verticalSizeClass, h: horizontalSizeClass)
```

Use it in SwiftUI views as per below:

```
struct ContentView: View {
    @Environment(\.horizontalSizeClass) var h
    @Environment(\.verticalSizeClass) var v
    
    var body: some View {
        Text("Responsive Text")
            .padding(Metrics.standardPadding.build(v: v, h: h))
            .font(Metrics.headerFont.build(v: v, h: h))
    }
}

enum Metrics {
    static let standardPadding = MetricBuilder(iPhone: 16, iPad: 24)
        .landscape(12) // Sets the padding to 12 for all the devices in landscape.
        .iPhoneSmallScreen(10) // Sets the padding to 10 for iPhones with a small screen (iPhone SE). 
    
    static let headerFont = MetricBuilder(
        iPhone: Font.system(size: 24),
        iPad: Font.system(size: 32)
    )
    .landscape(Font.system(size: 20))
}
```

# Dependencies
MetricBuilder is designed to be a zero-dependency library. It only relies on:

- SwiftUI - For UserInterfaceSizeClass types
- UIKit - For UIScreen, UITraitCollection, and UIUserInterfaceSizeClass

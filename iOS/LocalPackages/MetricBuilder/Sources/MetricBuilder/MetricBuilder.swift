//
//  MetricBuilder.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import SwiftUI
import class UIKit.UIScreen
import enum UIKit.UIUserInterfaceIdiom

/// A builder class for creating responsive metrics that adapt to different device types and orientations.
///
/// `MetricBuilder` provides an interface for defining values that change based on:
/// - Device type (iPhone vs iPad)
/// - Screen orientation (portrait vs landscape)
/// - Screen size (small screens like iPhone SE)
///
/// ## Usage
///
/// ```swift
/// // Simple device-specific values
/// let padding = MetricBuilder(iPhone: 16, iPad: 24) // Initialise the builder with default values for iPhone and iPad in all orientations.
///     .build(v: verticalSizeClass, h: horizontalSizeClass)
///
/// // With orientation overrides
/// let imageSize = MetricBuilder(iPhone: 100, iPad: 200) // Initialise the builder with default values for iPhone and iPad in all orientations.
///     .iPhone(landscape: 150) // Set the image size to 150 for iPhone in landscape.
///     .iPad(landscape: 250) // Set the image size to 250 for iPad in landscape.
///     .build(v: verticalSizeClass, h: horizontalSizeClass)
///
/// // Small screen support
/// let fontSize = MetricBuilder(default: 17) // Initialise the builder with a default values for all the devices in all orientations.
///     .iPad(20) // Set the font size to 20 for iPad in all orientations.
///     .iPhoneSmallScreen(15) Set the font size to 15 for iPhone small screen (iPhone SE) in all orientations.
///     .build(v: verticalSizeClass, h: horizontalSizeClass)
///
/// // Configure all devices for a specific orientation
/// let metric = MetricBuilder(iPhone: 10, iPad: 20) // Initialise the builder with default values for iPhone and iPad in all orientations.
///     .landscape(15)  // All devices use 15 in landscape.
///     .iPhoneSmallScreen(portrait: 8, landscape: 12) // iPhone small screen use specific values in portrait and landscape.
///
/// // Or configure each device type individually
/// let metric = MetricBuilder(default: 10) // Initialise the builder with a default value for all the devices in all orientations.
///     .portrait(iPhone: 12, iPad: 20) // Set the value in portrait for iPhone and iPad.
///     .landscape(iPhone: 15, iPad: 25) // Set the value in landscape for iPhone and iPad.
/// ```
public final class MetricBuilder<T>: @unchecked Sendable {
    // Default values that will be used for all pair device/orientation.
    private let defaultIPhoneValue: T
    private let defaultIPadValue: T

    // Overrides for iPhone Portrait/Landscape.
    private var iPhonePortraitValue: T?
    private var iPhoneLandscapeValue: T?

    // Overrides for iPad Portrait/Landscape.
    private var iPadPortraitValue: T?
    private var iPadLandscapeValue: T?

    // Overrides for iPhone small screen (iPhone SE) Portrait/Landscape.
    private var iPhoneSmallScreenPortraitValue: T?
    private var iPhoneSmallScreenLandscapeValue: T?

    // Screen bounds for testing
    // Note: We use optional CGRect defaulting to nil instead of UIScreen.main.bounds
    // because UIScreen.main is @MainActor isolated and cannot be used as a default
    // parameter value. When nil, we fetch UIScreen.main.bounds inside the @MainActor
    // build method. This also improves testability by allowing bounds injection.
    // We could have marked the entire MetricBuilder class as @MainActor, but that
    // would require marking every metric constant with @MainActor as well.
    private let screenBounds: CGRect?

    /// Initialise with different values for iPhone and iPad.
    /// - Parameters:
    ///   - iPhone: The default value for iPhone configurations
    ///   - iPad: The default value for iPad configurations
    ///   - screenBounds: Optional screen bounds for testing. If nil, uses UIScreen.main.bounds.
    public init(iPhone: T, iPad: T, screenBounds: CGRect? = nil) {
        self.defaultIPhoneValue = iPhone
        self.defaultIPadValue = iPad
        self.screenBounds = screenBounds
    }

    /// Initialise with the same value for all devices and orientations
    /// - Parameters:
    ///   - default: The default value to use for all configurations
    ///   - screenBounds: Optional screen bounds for testing. If nil, uses UIScreen.main.bounds.
    public convenience init(default: T, screenBounds: CGRect? = nil) {
        self.init(iPhone: `default`, iPad: `default`, screenBounds: screenBounds)
    }
}

// MARK: - Public

public extension MetricBuilder {

    // MARK: - iPhone

    /// Sets the same value for both portrait and landscape orientations on iPhone.
    ///
    /// This method overrides any previously set iPhone-specific values.
    ///
    /// - Parameter value: The value to use for all iPhone orientations.
    /// - Returns: The builder instance for method chaining.
    func iPhone(_ value: T) -> Self {
        iPhonePortraitValue = value
        iPhoneLandscapeValue = value
        return self
    }

    /// Sets specific values for iPhone portrait and/or landscape orientations.
    ///
    /// Only the provided parameters will be updated; nil parameters leave existing values unchanged.
    /// This allows for partial updates without affecting other orientation values.
    ///
    /// - Parameters:
    ///   - portrait: The value for iPhone portrait orientation, or nil to keep existing.
    ///   - landscape: The value for iPhone landscape orientation, or nil to keep existing.
    /// - Returns: The builder instance for method chaining.
    func iPhone(portrait: T? = nil, landscape: T? = nil) -> Self {
        if let portrait = portrait {
            iPhonePortraitValue = portrait
        }
        if let landscape = landscape {
            iPhoneLandscapeValue = landscape
        }
        return self
    }

    // MARK: - iPhone Small Screen

    /// Sets the same value for both portrait and landscape orientations on small screen iPhones.
    ///
    /// Small screens are detected as devices with a minimum dimension less than 375 points typically iPhone SE and similar compact devices.
    ///
    /// - Parameter value: The value to use for all small iPhone orientations.
    /// - Returns: The builder instance for method chaining.
    func iPhoneSmallScreen(_ value: T) -> Self {
        iPhoneSmallScreenPortraitValue = value
        iPhoneSmallScreenLandscapeValue = value
        return self
    }

    /// Sets specific values for small screen iPhone portrait and/or landscape orientations.
    ///
    /// Only the provided parameters will be updated; nil parameters leave existing values unchanged.
    /// Small screens are detected as devices with a minimum dimension less than 375 points.
    ///
    /// - Parameters:
    ///   - portrait: The value for small iPhone portrait orientation, or nil to keep existing.
    ///   - landscape: The value for small iPhone landscape orientation, or nil to keep existing.
    /// - Returns: The builder instance for method chaining.
    func iPhoneSmallScreen(portrait: T? = nil, landscape: T? = nil) -> Self {
        if let portrait = portrait {
            iPhoneSmallScreenPortraitValue = portrait
        }
        if let landscape = landscape {
            iPhoneSmallScreenLandscapeValue = landscape
        }
        return self
    }

    // MARK: - iPad

    /// Sets the same value for both portrait and landscape orientations on iPad.
    ///
    /// This method overrides any previously set iPad-specific values.
    ///
    /// - Parameter value: The value to use for all iPad orientations.
    /// - Returns: The builder instance for method chaining.
    func iPad(_ value: T) -> Self {
        iPadPortraitValue = value
        iPadLandscapeValue = value
        return self
    }

    /// Sets specific values for iPad portrait and/or landscape orientations.
    ///
    /// Only the provided parameters will be updated; nil parameters leave existing values unchanged.
    /// This allows for partial updates without affecting other orientation values.
    ///
    /// - Parameters:
    ///   - portrait: The value for iPad portrait orientation, or nil to keep existing.
    ///   - landscape: The value for iPad landscape orientation, or nil to keep existing.
    /// - Returns: The builder instance for method chaining.
    func iPad(portrait: T? = nil, landscape: T? = nil) -> Self {
        if let portrait = portrait {
            iPadPortraitValue = portrait
        }
        if let landscape = landscape {
            iPadLandscapeValue = landscape
        }
        return self
    }

    // MARK: - Orientation Specific

    /// Sets portrait orientation values for specific device types.
    ///
    /// This method allows configuring portrait values across different device types in a single call.
    /// Only the provided parameters will be updated; nil parameters leave existing values unchanged.
    ///
    /// - Parameters:
    ///   - iPhone: The value for iPhone portrait orientation, or nil to keep existing.
    ///   - iPhoneSmallScreen: The value for small iPhone portrait orientation, or nil to keep existing.
    ///   - iPad: The value for iPad portrait orientation, or nil to keep existing.
    /// - Returns: The builder instance for method chaining.
    func portrait(iPhone: T? = nil, iPhoneSmallScreen: T? = nil, iPad: T? = nil) -> Self {
        if let iPhone {
            iPhonePortraitValue = iPhone
        }
        if let iPhoneSmallScreen {
            iPhoneSmallScreenPortraitValue = iPhoneSmallScreen
        }
        if let iPad {
            iPadPortraitValue = iPad
        }
        return self
    }

    /// Sets the same portrait orientation value for all device types.
    ///
    /// This is a convenience method that applies the same value to portrait orientation across iPhone, small screen iPhone, and iPad devices.
    ///
    /// - Parameter value: The value to use for portrait orientation on all devices.
    /// - Returns: The builder instance for method chaining.
    func portrait(_ value: T) -> Self {
        return portrait(iPhone: value, iPhoneSmallScreen: value, iPad: value)
    }

    /// Sets landscape orientation values for specific device types.
    ///
    /// This method allows configuring landscape values across different device types in a single call.
    /// Only the provided parameters will be updated; nil parameters leave existing values unchanged.
    ///
    /// - Parameters:
    ///   - iPhone: The value for iPhone landscape orientation, or nil to keep existing.
    ///   - iPhoneSmallScreen: The value for small iPhone landscape orientation, or nil to keep existing.
    ///   - iPad: The value for iPad landscape orientation, or nil to keep existing.
    /// - Returns: The builder instance for method chaining.
    func landscape(iPhone: T? = nil, iPhoneSmallScreen: T? = nil, iPad: T? = nil) -> Self {
        if let iPhone {
            iPhoneLandscapeValue = iPhone
        }
        if let iPhoneSmallScreen {
            iPhoneSmallScreenLandscapeValue = iPhoneSmallScreen
        }
        if let iPad {
            iPadLandscapeValue = iPad
        }
        return self
    }

    /// Sets the same landscape orientation value for all device types.
    ///
    /// This is a convenience method that applies the same value to landscape orientation
    /// across iPhone, small screen iPhone, and iPad devices.
    ///
    /// - Parameter value: The value to use for landscape orientation on all devices.
    /// - Returns: The builder instance for method chaining.
    func landscape(_ value: T) -> Self {
        return landscape(iPhone: value, iPhoneSmallScreen: value, iPad: value)
    }

    // MARK: - Build

    /// Builds the appropriate metric value based on the provided size classes.
    ///
    /// This method determines the current device type and orientation from the size classes then returns the most specific value configured for that context.
    ///
    /// - Parameters:
    ///   - v: The vertical size class, typically from `@Environment(\.verticalSizeClass)`
    ///   - h: The horizontal size class, typically from `@Environment(\.horizontalSizeClass)`
    ///
    /// - Returns: The configured value for the current device context.
    ///
    /// - Note: This method is marked `@MainActor` because it may need to access `UIScreen.main.bounds`
    ///         when no screen bounds were provided during initialisation.
    ///
    /// ## Example
    ///
    /// ```swift
    /// struct ContentView: View {
    ///     @Environment(\.horizontalSizeClass) var h
    ///     @Environment(\.verticalSizeClass) var v
    ///
    ///     var body: some View {
    ///         Text("Hello")
    ///             .padding(padding.build(v: v, h: h))
    ///     }
    /// }
    ///
    /// enum Metrics {
    ///    let padding = MetricBuilder(iPhone: 16, iPad: 24)
    ///         .landscape(12)
    /// }
    /// ```
    @MainActor
    func build(v: UserInterfaceSizeClass?, h: UserInterfaceSizeClass?) -> T {
        let screenBounds = self.screenBounds ?? UIScreen.main.bounds
        let minWidth = min(screenBounds.width, screenBounds.height)
        let isIphoneSmallScreen = minWidth < 375

        if isIphoneSmallScreen {
            return buildIPhoneSmallScreenMetrics(v: v, h: h)
        } else if isIPad(v: v, h: h) {
            return buildIPadMetrics(v: v, h: h, screenSize: screenBounds.size)
        } else {
           return buildIPhoneMetrics(v: v, h: h)
        }
    }

    /// Builds the appropriate metric value using a UIKit trait collection.
    ///
    /// This convenience method extracts size classes from the provided trait collection
    /// and delegates to the main `build(v:h:)` method.
    ///
    /// - Parameter traits: The trait collection containing size class information.
    ///                     Defaults to `UIScreen.main.traitCollection`.
    ///
    /// - Returns: The configured value for the device context described by the trait collection.
    ///
    /// - Note: This method is marked `@MainActor` because it may need to access `UIScreen.main`
    ///         for both the default trait collection and screen bounds calculation.
    ///
    /// ## Example
    ///
    /// ```swift
    /// enum Metrics {
    ///    // Build value immediately as the value does not depend on device orientation.
    ///    let padding = MetricBuilder<CGFloat>(iPhone: 10, iPad: 20).build()
    /// }
    /// ```
    @MainActor
    func build(traits: UITraitCollection = UIScreen.main.traitCollection) -> T {
        let v = UserInterfaceSizeClass(traits.verticalSizeClass)
        let h = UserInterfaceSizeClass(traits.horizontalSizeClass)
        return build(v: v, h: h)
    }
}

// MARK: - Private

private extension MetricBuilder {

    @MainActor
    func buildIPhoneSmallScreenMetrics(v: UserInterfaceSizeClass?, h: UserInterfaceSizeClass?) -> T {
        if isIPhoneLandscape(v: v) {
            iPhoneSmallScreenLandscapeValue ?? iPhoneLandscapeValue ?? defaultIPhoneValue
        } else {
            iPhoneSmallScreenPortraitValue ?? iPhonePortraitValue ?? defaultIPhoneValue
        }
    }

    @MainActor
    func buildIPhoneMetrics(v: UserInterfaceSizeClass?, h: UserInterfaceSizeClass?) -> T {
        if isIPhoneLandscape(v: v) {
            iPhoneLandscapeValue ?? defaultIPhoneValue
        } else {
            iPhonePortraitValue ?? defaultIPhoneValue
        }
    }

    @MainActor
    func buildIPadMetrics(v: UserInterfaceSizeClass?, h: UserInterfaceSizeClass?, screenSize: CGSize) -> T {
        if isIPadLandscape(v: v, h: h, screenSize: screenSize) {
            iPadLandscapeValue ?? defaultIPadValue
        } else {
            iPadPortraitValue ?? defaultIPadValue
        }
    }

}

// MARK: - Helpers

private extension UserInterfaceSizeClass {
    init?(_ uiSizeClass: UIUserInterfaceSizeClass) {
        switch uiSizeClass {
        case .compact:
            self = .compact
        case .regular:
            self = .regular
        case .unspecified:
            return nil
        @unknown default:
            return nil
        }
    }
}

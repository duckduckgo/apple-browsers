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

public final class MetricBuilder<T> {
    // Default values that will be used for all pair device/orientation.
    private let defaultIPhoneValue: T
    private let defaultIPadValue: T

    // Overrides for iPhone Portrait/Landscape.
    private var iPhonePortraitValue: T?
    private var iPhoneLandscapeValue: T?

    // Overrides for iPad Portrait/Landscape.
    private var iPadPortraitValue: T?
    private var iPadLandscapeValue: T?

    // Overrides for iPhone smalls screen (iPhone SE) Portrait/Landscape.
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

    /// Initialize with different values for iPhone and iPad (designated initializer)
    /// - Parameters:
    ///   - iPhone: The default value for iPhone configurations
    ///   - iPad: The default value for iPad configurations
    ///   - screenBounds: Optional screen bounds for testing. If nil, uses UIScreen.main.bounds
    public init(iPhone: T, iPad: T, screenBounds: CGRect? = nil) {
        self.defaultIPhoneValue = iPhone
        self.defaultIPadValue = iPad
        self.screenBounds = screenBounds
    }

    /// Initialize with the same value for all devices and orientations
    /// - Parameters:
    ///   - default: The default value to use for all configurations
    ///   - screenBounds: Optional screen bounds for testing. If nil, uses UIScreen.main.bounds
    public convenience init(default: T, screenBounds: CGRect? = nil) {
        self.init(iPhone: `default`, iPad: `default`, screenBounds: screenBounds)
    }
}

// MARK: - Public

public extension MetricBuilder {

    // MARK: - iPhone

    /// Set value for all iPhone configurations
    func iPhone(_ value: T) -> Self {
        iPhonePortraitValue = value
        iPhoneLandscapeValue = value
        return self
    }

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

    func iPhoneSmallScreen(_ value: T) -> Self {
        iPhoneSmallScreenPortraitValue = value
        iPhoneSmallScreenLandscapeValue = value
        return self
    }

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

    /// Set value for iPad (both orientations or specific ones)
    func iPad(_ value: T) -> Self {
        iPadPortraitValue = value
        iPadLandscapeValue = value
        return self
    }

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

    func portrait(iPhone: T? = nil, iPhoneSmallScreen: T? = nil, iPad: T? = nil) -> Self {
        iPhonePortraitValue = iPhone
        iPhoneSmallScreenPortraitValue = iPhoneSmallScreen
        iPadPortraitValue = iPad
        return self
    }

    func portrait(_ value: T) -> Self {
        return portrait(iPhone: value, iPhoneSmallScreen: value, iPad: value)
    }

    func landscape(iPhone: T? = nil, iPhoneSmallScreen: T? = nil, iPad: T? = nil) -> Self {
        iPhoneLandscapeValue = iPhone
        iPhoneSmallScreenLandscapeValue = iPhoneSmallScreen
        iPadLandscapeValue = iPad
        return self
    }

    func landscape(_ value: T) -> Self {
        return landscape(iPhone: value, iPhoneSmallScreen: value, iPad: value)
    }

    // MARK: - Build

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

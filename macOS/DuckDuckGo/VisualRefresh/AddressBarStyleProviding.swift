//
//  AddressBarStyleProviding.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import AppKit
import DesignResourcesKitIcons
import FeatureFlags
import Foundation
import PrivacyConfig

protocol AddressBarStyleProviding {
    // MARK: - Public API(s)
    func navigationBarHeight(for type: AddressBarSizeClass, focused: Bool) -> CGFloat
    func addressBarTopPadding(for type: AddressBarSizeClass, focused: Bool) -> CGFloat
    func addressBarBottomPadding(for type: AddressBarSizeClass, focused: Bool) -> CGFloat
    func addressBarStackSpacing(for type: AddressBarSizeClass) -> CGFloat
    func shouldShowOutlineBorder(isHomePage: Bool) -> Bool
    func sizeForSuggestionRow(isHomePage: Bool) -> CGFloat

    // MARK: - Configuration
    var shouldShowNewSearchIcon: Bool { get }
    var shouldAddPaddingToAddressBarButtons: Bool { get }
    var shouldAddAddressBarShadowWhenInactive: Bool { get }
    var shouldDisplayAddressBarOuerBorder: Bool { get }
    var shouldLeaveBottomPaddingInSuggestions: Bool { get }
    var shouldUseLegacyAddressBarSpacingMechanism: Bool { get }

    // MARK: - Font Sizes
    var defaultAddressBarFontSize: CGFloat { get }
    var newTabOrHomePageAddressBarFontSize: CGFloat { get }

    // MARK: - Metrics
    var addressBarActiveBackgroundViewRadius: CGFloat { get }
    var addressBarActiveOuterBorderViewRadius: CGFloat { get }
    var addressBarActiveOuterBorderSize: CGFloat { get }
    var addressBarButtonSize: CGFloat { get }
    var addressBarButtonsCornerRadius: CGFloat { get }
    var addressBarInactiveBackgroundViewRadius: CGFloat { get }
    var addressBarInnerBorderViewRadius: CGFloat { get }
    var addTabButtonPadding: CGFloat { get }
    var privacyShieldStyleProvider: PrivacyShieldAddressBarStyleProviding { get }
    var suggestionHighlightCornerRadius: CGFloat { get }
    var suggestionIconViewLeadingPadding: CGFloat { get }
    var suggestionShadowRadius: CGFloat { get }
    var suggestionTextFieldLeadingPadding: CGFloat { get }
    var tabBarBackgroundTopPadding: CGFloat { get }
    var topSpaceForSuggestionWindow: CGFloat { get }
}

struct AddressBarStyleProvidingFactory {

    static func buildStyleProvider(featureFlagger: FeatureFlagger) -> AddressBarStyleProviding {
        if featureFlagger.isFeatureOn(.appRebranding) {
            return RefreshAddressBarStyleProvider(featureFlagger: featureFlagger)
        }

        return CurrentAddressBarStyleProvider(featureFlagger: featureFlagger)
    }
}

final class CurrentAddressBarStyleProvider: AddressBarStyleProviding {

    /// The TabBar component requires an extra top padding whenever all of the following are met:
    ///     1. We're building on `Xcode 26`
    ///     2. We're running on `Tahoe`
    ///     3. The `UIDesignRequiresCompatibility` flag is disabled
    /// In any other scenario, applying a top padding would result in an unexpected gap
    ///
    let tabBarBackgroundTopPadding: CGFloat = {
#if compiler(>=6.2)
        if #available(macOS 26.0, *), Bundle.main.designCompatibilityEnabled == false {
            return 2
        }
#endif

        return 0
    }()

    private let navigationBarHeightForDefault: CGFloat = 52
    private let navigationBarHeightForHomePage: CGFloat = 52
    private let navigationBarHeightForPopUpWindow: CGFloat = 42
    private let addressBarTopPaddingForDefault: CGFloat = 7
    private let addressBarTopPaddingForDefaultFocusedWithAIChat: CGFloat = 3
    private let addressBarTopPaddingForHomePage: CGFloat = 7
    private let addressBarTopPaddingForHomePageFocusedWithAIChat: CGFloat = 3
    private let addressBarTopPaddingForPopUpWindow: CGFloat = 7
    private let addressBarBottomPaddingForDefault: CGFloat = 7
    private let addressBarBottomPaddingForDefaultFocusedWithAIChat: CGFloat = 3
    private let addressBarBottomPaddingForHomePage: CGFloat = 7
    private let addressBarBottomPaddingForHomePageFocusedWithAIChat: CGFloat = 3
    private let addressBarBottomPaddingForPopUpWindow: CGFloat = 7

    private let featureFlagger: FeatureFlagger

    private var isAIChatOmnibarEnabled: Bool {
        featureFlagger.isFeatureOn(.aiChatOmnibarToggle)
    }

    init(featureFlagger: FeatureFlagger) {
        self.featureFlagger = featureFlagger
    }

    let defaultAddressBarFontSize: CGFloat = 13
    let newTabOrHomePageAddressBarFontSize: CGFloat = 13
    let addressBarButtonsCornerRadius: CGFloat = 9
    let shouldShowNewSearchIcon: Bool = true
    let shouldAddPaddingToAddressBarButtons: Bool = true
    let privacyShieldStyleProvider: PrivacyShieldAddressBarStyleProviding = CurrentPrivacyShieldAddressBarStyleProvider()
    let shouldAddAddressBarShadowWhenInactive: Bool = true
    let shouldDisplayAddressBarOuerBorder: Bool = true
    let tabBarButtonSize: CGFloat = 28
    let addressBarButtonSize: CGFloat = 28
    let addTabButtonPadding: CGFloat = 32 // Takes into account the extra 24pts (12pts for each inset on s-shaped tabs)
    let addressBarActiveBackgroundViewRadius: CGFloat = 15
    let addressBarInactiveBackgroundViewRadius: CGFloat = 12
    let addressBarInnerBorderViewRadius: CGFloat = 15
    let addressBarActiveOuterBorderViewRadius: CGFloat = 17
    let addressBarActiveOuterBorderSize: CGFloat = -2
    let suggestionIconViewLeadingPadding: CGFloat = 8
    let suggestionTextFieldLeadingPadding: CGFloat = 8
    let topSpaceForSuggestionWindow: CGFloat = 16
    let suggestionShadowRadius: CGFloat = 3.0
    let suggestionHighlightCornerRadius: CGFloat = 6.0
    let shouldLeaveBottomPaddingInSuggestions: Bool = true
    let shouldUseLegacyAddressBarSpacingMechanism: Bool = true

    func navigationBarHeight(for type: AddressBarSizeClass, focused: Bool) -> CGFloat {
        switch type {
        case .default: return navigationBarHeightForDefault
        case .homePage: return navigationBarHeightForHomePage
        case .popUpWindow: return navigationBarHeightForPopUpWindow
        }
    }

    func addressBarTopPadding(for type: AddressBarSizeClass, focused: Bool) -> CGFloat {
        switch type {
        case .default:
            if focused {
                return isAIChatOmnibarEnabled ? addressBarTopPaddingForDefaultFocusedWithAIChat : addressBarTopPaddingForDefault - 1
            }
            return addressBarTopPaddingForDefault
        case .homePage:
            if focused {
                return isAIChatOmnibarEnabled ? addressBarTopPaddingForHomePageFocusedWithAIChat : addressBarTopPaddingForHomePage - 1
            }
            return addressBarTopPaddingForHomePage
        case .popUpWindow:
            return addressBarTopPaddingForPopUpWindow
        }
    }

    func addressBarBottomPadding(for type: AddressBarSizeClass, focused: Bool) -> CGFloat {
        switch type {
        case .default:
            if focused {
                return isAIChatOmnibarEnabled ? addressBarBottomPaddingForDefaultFocusedWithAIChat : addressBarBottomPaddingForDefault - 1
            }
            return addressBarBottomPaddingForDefault
        case .homePage:
            if focused {
                return isAIChatOmnibarEnabled ? addressBarBottomPaddingForHomePageFocusedWithAIChat : addressBarBottomPaddingForHomePage - 1
            }
            return addressBarBottomPaddingForHomePage
        case .popUpWindow:
            return addressBarBottomPaddingForPopUpWindow
        }
    }

    func addressBarStackSpacing(for type: AddressBarSizeClass) -> CGFloat {
        return 0
    }

    func shouldShowOutlineBorder(isHomePage: Bool) -> Bool {
        return true
    }

    func sizeForSuggestionRow(isHomePage: Bool) -> CGFloat {
        return 32
    }
}

final class RefreshAddressBarStyleProvider: AddressBarStyleProviding {

    // MARK: - Private Properties
    private let navigationBarHeightForDefault: CGFloat = 52
    private let navigationBarHeightForHomePage: CGFloat = 52
    private let navigationBarHeightForPopUpWindow: CGFloat = 42
    private let addressBarTopPaddingForDefault: CGFloat = 7
    private let addressBarTopPaddingForDefaultFocused: CGFloat = 3
    private let addressBarTopPaddingForPopUpWindow: CGFloat = 7
    private let addressBarBottomPaddingForDefault: CGFloat = 7
    private let addressBarBottomPaddingForHomePage: CGFloat = 7
    private let addressBarBottomPaddingForPopUpWindow: CGFloat = 7

    // MARK: - Configuration
    let shouldShowNewSearchIcon: Bool = true
    let shouldAddPaddingToAddressBarButtons: Bool = true
    let shouldAddAddressBarShadowWhenInactive: Bool = true
    let shouldDisplayAddressBarOuerBorder: Bool = true
    let shouldLeaveBottomPaddingInSuggestions: Bool = true
    let shouldUseLegacyAddressBarSpacingMechanism: Bool = false

    // MARK: - Font Sizes
    let defaultAddressBarFontSize: CGFloat = 13
    let newTabOrHomePageAddressBarFontSize: CGFloat = 13

    // MARK: - Metrics

    let addressBarActiveBackgroundViewRadius: CGFloat = 19      // OK
    let addressBarActiveOuterBorderViewRadius: CGFloat = 0      // Deprecated
    let addressBarActiveOuterBorderSize: CGFloat = 0            // Deprecated
    let addressBarButtonSize: CGFloat = 28
    let addressBarButtonsCornerRadius: CGFloat = 16             // VERIFY
    let addressBarInactiveBackgroundViewRadius: CGFloat = 17    // OK
    let addressBarInnerBorderViewRadius: CGFloat = 19           // OK - Matches addressBarActiveBackgroundViewRadius
    let addTabButtonPadding: CGFloat = 32                       // Takes into account the extra 24pts (12pts for each inset on s-shaped tabs)
    let privacyShieldStyleProvider: PrivacyShieldAddressBarStyleProviding = CurrentPrivacyShieldAddressBarStyleProvider()
    let suggestionHighlightCornerRadius: CGFloat = 12           // OK - Pending Height adjustment
    let suggestionIconViewLeadingPadding: CGFloat = 8
    let suggestionShadowRadius: CGFloat = 3.0                   // Not Needed
    let suggestionTextFieldLeadingPadding: CGFloat = 8
    let tabBarButtonSize: CGFloat = 28
    let topSpaceForSuggestionWindow: CGFloat = 16

    let tabBarBackgroundTopPadding: CGFloat = {
#if compiler(>=6.2)
        if #available(macOS 26.0, *), Bundle.main.designCompatibilityEnabled == false {
            return 2
        }
#endif

        return 0
    }()

    // MARK: - Feature Flag Helpers
    private let featureFlagger: FeatureFlagger

    /// Designated Initializer
    ///
    init(featureFlagger: FeatureFlagger) {
        self.featureFlagger = featureFlagger
    }

    // MARK: - Public API(s)

    func navigationBarHeight(for type: AddressBarSizeClass, focused: Bool) -> CGFloat {
        switch type {
        case .default:
            return navigationBarHeightForDefault
        case .homePage:
            return navigationBarHeightForHomePage
        case .popUpWindow:
            return navigationBarHeightForPopUpWindow
        }
    }

    func addressBarTopPadding(for type: AddressBarSizeClass, focused: Bool) -> CGFloat {        // REVIEW
        switch type {
        case .default, .homePage:
            return focused ? addressBarTopPaddingForDefaultFocused : addressBarTopPaddingForDefault
        case .popUpWindow:
            return addressBarTopPaddingForPopUpWindow
        }
    }

    func addressBarBottomPadding(for type: AddressBarSizeClass, focused: Bool) -> CGFloat {     // REVIEW
        switch type {
        case .default, .homePage:
            return focused ? addressBarTopPaddingForDefaultFocused : addressBarTopPaddingForDefault
        case .popUpWindow:
            return addressBarBottomPaddingForPopUpWindow
        }
    }

    func addressBarStackSpacing(for type: AddressBarSizeClass) -> CGFloat {
        return 0
    }

    func shouldShowOutlineBorder(isHomePage: Bool) -> Bool {
        return false
    }

    func sizeForSuggestionRow(isHomePage: Bool) -> CGFloat {
        return 32
    }
}

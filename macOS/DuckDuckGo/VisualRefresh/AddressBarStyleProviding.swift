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
    func addressBarHorizontalPadding(focused: Bool) -> CGFloat?
    func addressBarStackSpacing(for type: AddressBarSizeClass) -> CGFloat
    func addressBarTrailingStackViewPadding(focused: Bool, showsToggle: Bool) -> CGFloat
    func shouldShowOutlineBorder(isHomePage: Bool) -> Bool
    func sizeForSuggestionRow(isHomePage: Bool) -> CGFloat
    func addressBarInnerBorderViewRadius(isSuggestionsWindowVisible: Bool) -> CGFloat

    // MARK: - Configuration
    var shouldShowNewSearchIcon: Bool { get }
    var shouldAddPaddingToAddressBarButtons: Bool { get }
    var shouldAddAddressBarShadowWhenInactive: Bool { get }
    var shouldLeaveBottomPaddingInSuggestions: Bool { get }
    var shouldUseLegacyAddressBarSpacingMechanism: Bool { get }

    // MARK: - Font Sizes
    var defaultAddressBarFontSize: CGFloat { get }
    var newTabOrHomePageAddressBarFontSize: CGFloat { get }

    // MARK: - Metrics
    var addressBarActiveBackgroundViewRadius: CGFloat { get }
    var addressBarActiveBackgroundViewRadiusWithSuggestions: CGFloat { get }
    var addressBarActiveOuterBorderViewRadius: CGFloat { get }
    var addressBarActiveOuterBorderSize: CGFloat { get }
    var addressBarButtonSize: CGFloat { get }
    var addressBarButtonsCornerRadius: CGFloat { get }
    var addressBarInactiveBackgroundViewLeadingPadding: CGFloat { get }
    var addressBarInactiveBackgroundViewTrailingPadding: CGFloat { get }
    var addressBarButtonsContainerViewLeadingPadding: CGFloat { get }
    var addressBarButtonsContainerViewTrailingPadding: CGFloat { get }
    var addressBarInactiveBackgroundViewRadius: CGFloat { get }
    var addressBarTextFieldLeadingPadding: CGFloat { get }
    var addressBarToggleIndicatorGap: CGFloat { get }
    var addressBarToggleIndicatorHorizontalInset: CGFloat { get }
    var addTabButtonPadding: CGFloat { get }
    var aiChatOmnibarTextContainerTopPadding: CGFloat { get }
    var aiChatOmnibarTextContainerLeadingPadding: CGFloat { get }
    var privacyShieldStyleProvider: PrivacyShieldAddressBarStyleProviding { get }
    var suggestionHighlightCornerRadius: CGFloat { get }
    var suggestionHighlightHorizontalPadding: CGFloat { get }
    var suggestionIconViewLeadingPadding: CGFloat { get }
    var suggestionShadowRadius: CGFloat { get }
    var suggestionTextFieldLeadingPadding: CGFloat { get }
    var tabBarBackgroundTopPadding: CGFloat { get }
    var topSpaceForSuggestionWindow: CGFloat { get }
}

struct AddressBarStyleProvidingFactory {

    static func buildStyleProvider(featureFlagger: FeatureFlagger) -> AddressBarStyleProviding {
        if featureFlagger.isFeatureOn(.appRebranding) {
            return CurrentAddressBarStyleProvider()
        }

        return LegacyAddressBarStyleProvider()
    }
}

final class LegacyAddressBarStyleProvider: AddressBarStyleProviding {

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
    private let addressBarTrailingStackViewOmnibarPadding: CGFloat = 4
    private let addressBarTrailingStackViewFocusedPadding: CGFloat = 4
    private let addressBarTrailingStackViewDefaultPadding: CGFloat = 3

    let defaultAddressBarFontSize: CGFloat = 13
    let newTabOrHomePageAddressBarFontSize: CGFloat = 13
    let addressBarButtonsCornerRadius: CGFloat = 9
    let shouldShowNewSearchIcon: Bool = true
    let shouldAddPaddingToAddressBarButtons: Bool = true
    let privacyShieldStyleProvider: PrivacyShieldAddressBarStyleProviding = CurrentPrivacyShieldAddressBarStyleProvider()
    let shouldAddAddressBarShadowWhenInactive: Bool = true
    let tabBarButtonSize: CGFloat = 28
    let addressBarButtonSize: CGFloat = 28
    let addTabButtonPadding: CGFloat = 32 // Takes into account the extra 24pts (12pts for each inset on s-shaped tabs)
    let addressBarActiveBackgroundViewRadius: CGFloat = 15
    let addressBarActiveBackgroundViewRadiusWithSuggestions: CGFloat = 15
    let addressBarInactiveBackgroundViewRadius: CGFloat = 12
    let addressBarInnerBorderViewRadius: CGFloat = 15
    let addressBarTextFieldLeadingPadding: CGFloat = 20
    let addressBarToggleIndicatorGap: CGFloat = 2
    let addressBarToggleIndicatorHorizontalInset: CGFloat = 0
    let addressBarActiveOuterBorderViewRadius: CGFloat = 17
    let addressBarActiveOuterBorderSize: CGFloat = -2
    let addressBarInactiveBackgroundViewLeadingPadding: CGFloat = 2
    let addressBarInactiveBackgroundViewTrailingPadding: CGFloat = 2
    let addressBarButtonsContainerViewLeadingPadding: CGFloat = 2
    let addressBarButtonsContainerViewTrailingPadding: CGFloat = 2
    let aiChatOmnibarTextContainerLeadingPadding: CGFloat = 10
    let aiChatOmnibarTextContainerTopPadding: CGFloat = 5
    let suggestionIconViewLeadingPadding: CGFloat = 8
    let suggestionTextFieldLeadingPadding: CGFloat = 8
    let topSpaceForSuggestionWindow: CGFloat = 16
    let suggestionShadowRadius: CGFloat = 3.0
    let suggestionHighlightCornerRadius: CGFloat = 6.0
    let suggestionHighlightHorizontalPadding: CGFloat = 0
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
                return addressBarTopPaddingForDefaultFocusedWithAIChat
            }
            return addressBarTopPaddingForDefault
        case .homePage:
            if focused {
                return addressBarTopPaddingForHomePageFocusedWithAIChat
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
                return addressBarBottomPaddingForDefaultFocusedWithAIChat
            }
            return addressBarBottomPaddingForDefault
        case .homePage:
            if focused {
                return addressBarBottomPaddingForHomePageFocusedWithAIChat
            }
            return addressBarBottomPaddingForHomePage
        case .popUpWindow:
            return addressBarBottomPaddingForPopUpWindow
        }
    }

    func addressBarHorizontalPadding(focused: Bool) -> CGFloat? {
        nil
    }

    func addressBarStackSpacing(for type: AddressBarSizeClass) -> CGFloat {
        return 0
    }

    func addressBarTrailingStackViewPadding(focused: Bool, showsToggle: Bool) -> CGFloat {
        return addressBarTrailingStackViewOmnibarPadding
    }

    func shouldShowOutlineBorder(isHomePage: Bool) -> Bool {
        return true
    }

    func sizeForSuggestionRow(isHomePage: Bool) -> CGFloat {
        return 32
    }

    func addressBarInnerBorderViewRadius(isSuggestionsWindowVisible: Bool) -> CGFloat {
        addressBarInnerBorderViewRadius
    }
}

final class CurrentAddressBarStyleProvider: AddressBarStyleProviding {

    // MARK: - Private Properties
    private let navigationBarHeightForDefault: CGFloat = 52
    private let navigationBarHeightForHomePage: CGFloat = 52
    private let navigationBarHeightForPopUpWindow: CGFloat = 42
    private let addressBarTopPaddingForDefault: CGFloat = 7
    private let addressBarTopPaddingForDefaultFocused: CGFloat = 2
    private let addressBarTopPaddingForPopUpWindow: CGFloat = 7
    private let addressBarBottomPaddingForDefault: CGFloat = 7
    private let addressBarBottomPaddingForDefaultFocused: CGFloat = 2
    private let addressBarBottomPaddingForPopUpWindow: CGFloat = 7
    private let addressBarHorizontalPaddingExtended: CGFloat = 1
    private let addressBarHorizontalPaddingIDLE: CGFloat = 4
    private let addressBarTrailingStackViewOmnibarPadding: CGFloat = 1
    private let addressBarTrailingStackViewFocusedPadding: CGFloat = 3
    private let addressBarTrailingStackViewDefaultPadding: CGFloat = 3

    // MARK: - Configuration
    let shouldShowNewSearchIcon: Bool = true
    let shouldAddPaddingToAddressBarButtons: Bool = true
    let shouldAddAddressBarShadowWhenInactive: Bool = false
    let shouldLeaveBottomPaddingInSuggestions: Bool = true
    let shouldUseLegacyAddressBarSpacingMechanism: Bool = false

    // MARK: - Font Sizes
    let defaultAddressBarFontSize: CGFloat = 13
    let newTabOrHomePageAddressBarFontSize: CGFloat = 13

    // MARK: - Metrics

    let addressBarActiveBackgroundViewRadius: CGFloat = 19
    let addressBarActiveBackgroundViewRadiusWithSuggestions: CGFloat = 24
    let addressBarActiveOuterBorderViewRadius: CGFloat = 0      // Deprecated
    let addressBarActiveOuterBorderSize: CGFloat = 0            // Deprecated
    let addressBarButtonSize: CGFloat = 28
    let addressBarButtonsCornerRadius: CGFloat = 14
    let addressBarInactiveBackgroundViewRadius: CGFloat = 17
    let addressBarInactiveBackgroundViewLeadingPadding: CGFloat = 6
    let addressBarInactiveBackgroundViewTrailingPadding: CGFloat = 6
    let addressBarButtonsContainerViewLeadingPadding: CGFloat = 7
    let addressBarButtonsContainerViewTrailingPadding: CGFloat = 7
    let addressBarTextFieldLeadingPadding: CGFloat = 23
    let addressBarToggleIndicatorGap: CGFloat = 0
    let addressBarToggleIndicatorHorizontalInset: CGFloat = 1
    let addTabButtonPadding: CGFloat = 32                       // Takes into account the extra 24pts (12pts for each inset on s-shaped tabs)
    let aiChatOmnibarTextContainerLeadingPadding: CGFloat = 13
    let aiChatOmnibarTextContainerTopPadding: CGFloat = 6
    let privacyShieldStyleProvider: PrivacyShieldAddressBarStyleProviding = CurrentPrivacyShieldAddressBarStyleProvider()
    let suggestionHighlightCornerRadius: CGFloat = 12
    let suggestionHighlightHorizontalPadding: CGFloat = 5
    let suggestionIconViewLeadingPadding: CGFloat = 17
    let suggestionShadowRadius: CGFloat = 3.0
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

    func addressBarTopPadding(for type: AddressBarSizeClass, focused: Bool) -> CGFloat {
        switch type {
        case .default, .homePage:
            return focused ? addressBarTopPaddingForDefaultFocused : addressBarTopPaddingForDefault
        case .popUpWindow:
            return addressBarTopPaddingForPopUpWindow
        }
    }

    func addressBarBottomPadding(for type: AddressBarSizeClass, focused: Bool) -> CGFloat {
        switch type {
        case .default, .homePage:
            return focused ? addressBarBottomPaddingForDefaultFocused : addressBarBottomPaddingForDefault
        case .popUpWindow:
            return addressBarBottomPaddingForPopUpWindow
        }
    }

    func addressBarHorizontalPadding(focused: Bool) -> CGFloat? {
        return focused ? addressBarHorizontalPaddingExtended : addressBarHorizontalPaddingIDLE
    }

    func addressBarStackSpacing(for type: AddressBarSizeClass) -> CGFloat {
        return 0
    }

    func addressBarTrailingStackViewPadding(focused: Bool, showsToggle: Bool) -> CGFloat {
        return showsToggle ? addressBarTrailingStackViewOmnibarPadding : addressBarTrailingStackViewDefaultPadding
    }

    func shouldShowOutlineBorder(isHomePage: Bool) -> Bool {
        return false
    }

    func sizeForSuggestionRow(isHomePage: Bool) -> CGFloat {
        return 34
    }

    func addressBarInnerBorderViewRadius(isSuggestionsWindowVisible: Bool) -> CGFloat {
        isSuggestionsWindowVisible ? addressBarActiveBackgroundViewRadiusWithSuggestions : addressBarActiveBackgroundViewRadius
    }
}

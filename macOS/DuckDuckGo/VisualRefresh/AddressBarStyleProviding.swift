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
import DesignResourcesKitIcons

protocol AddressBarStyleProviding {
    func navigationBarHeight(for type: AddressBarSizeClass) -> CGFloat
    func addressBarTopPadding(for type: AddressBarSizeClass, focused: Bool) -> CGFloat
    func addressBarBottomPadding(for type: AddressBarSizeClass, focused: Bool) -> CGFloat
    func addressBarStackSpacing(for type: AddressBarSizeClass) -> CGFloat
    func shouldShowOutlineBorder(isHomePage: Bool) -> Bool
    func sizeForSuggestionRow(isHomePage: Bool) -> CGFloat

    var defaultAddressBarFontSize: CGFloat { get }
    var newTabOrHomePageAddressBarFontSize: CGFloat { get }
    var shouldShowNewSearchIcon: Bool { get }
    var addressBarLogoImage: NSImage? { get }
    var addressBarButtonsCornerRadius: CGFloat { get }
    var privacyShieldStyleProvider: PrivacyShieldAddressBarStyleProviding { get }
    var shouldAddPaddingToAddressBarButtons: Bool { get }
    var shouldAddAddressBarShadowWhenInactive: Bool { get }
    var addressBarButtonSize: CGFloat { get }
    var addTabButtonPadding: CGFloat { get }
    var addressBarActiveBackgroundViewRadius: CGFloat { get }
    var addressBarInactiveBackgroundViewRadius: CGFloat { get }
    var addressBarInnerBorderViewRadius: CGFloat { get }
    var addressBarActiveOuterBorderViewRadius: CGFloat { get }
    var addressBarActiveOuterBorderSize: CGFloat { get }
    var suggestionIconViewLeadingPadding: CGFloat { get }
    var suggestionTextFieldLeadingPadding: CGFloat { get }
    var topSpaceForSuggestionWindow: CGFloat { get }
    var suggestionShadowRadius: CGFloat { get }
    var suggestionHighlightCornerRadius: CGFloat { get }
    var shouldLeaveBottomPaddingInSuggestions: Bool { get }
}

final class LegacyAddressBarStyleProvider: AddressBarStyleProviding {
    private let navigationBarHeightForDefault: CGFloat = 48
    private let navigationBarHeightForHomePage: CGFloat = 52
    private let navigationBarHeightForPopUpWindow: CGFloat = 42
    private let addressBarTopPaddingForDefault: CGFloat = 6
    private let addressBarTopPaddingForHomePage: CGFloat = 10
    private let addressBarTopPaddingForPopUpWindow: CGFloat = 0
    private let addressBarBottomPaddingForDefault: CGFloat = 6
    private let addressBarBottomPaddingForHomePage: CGFloat = 8
    private let addressBarBottomPaddingForPopUpWindow: CGFloat = 0

    let defaultAddressBarFontSize: CGFloat = 13
    let newTabOrHomePageAddressBarFontSize: CGFloat = 15
    let addressBarButtonsCornerRadius: CGFloat = 0
    let addressBarLogoImage: NSImage? = nil
    let shouldShowNewSearchIcon: Bool = false
    let shouldAddPaddingToAddressBarButtons: Bool = false
    let privacyShieldStyleProvider: PrivacyShieldAddressBarStyleProviding = LegacyPrivacyShieldAddressBarStyleProvider()
    let shouldAddAddressBarShadowWhenInactive: Bool = false
    let tabBarButtonSize: CGFloat = 28
    let addressBarButtonSize: CGFloat = 32
    let addTabButtonPadding: CGFloat = 4
    let addressBarActiveBackgroundViewRadius: CGFloat = 8
    let addressBarInactiveBackgroundViewRadius: CGFloat = 6
    let addressBarInnerBorderViewRadius: CGFloat = 8
    let addressBarActiveOuterBorderViewRadius: CGFloat = 10
    let addressBarActiveOuterBorderSize: CGFloat = -3
    let suggestionIconViewLeadingPadding: CGFloat = 13
    let suggestionTextFieldLeadingPadding: CGFloat = 7
    let topSpaceForSuggestionWindow: CGFloat = 21
    let suggestionShadowRadius: CGFloat = 8.0
    let suggestionHighlightCornerRadius: CGFloat = 3.0
    let shouldLeaveBottomPaddingInSuggestions: Bool = true

    func navigationBarHeight(for type: AddressBarSizeClass) -> CGFloat {
        switch type {
        case .default: return navigationBarHeightForDefault
        case .homePage: return navigationBarHeightForHomePage
        case .popUpWindow: return navigationBarHeightForPopUpWindow
        }
    }

    func addressBarTopPadding(for type: AddressBarSizeClass, focused: Bool) -> CGFloat {
        switch type {
        case .default: return addressBarTopPaddingForDefault
        case .homePage: return addressBarTopPaddingForHomePage
        case .popUpWindow: return addressBarTopPaddingForPopUpWindow
        }
    }

    func addressBarBottomPadding(for type: AddressBarSizeClass, focused: Bool) -> CGFloat {
        switch type {
        case .default: return addressBarBottomPaddingForDefault
        case .homePage: return addressBarBottomPaddingForHomePage
        case .popUpWindow: return addressBarBottomPaddingForPopUpWindow
        }
    }

    func addressBarStackSpacing(for type: AddressBarSizeClass) -> CGFloat {
        switch type.isLogoVisible {
        case true: return 16
        case false: return 0
        }
    }

    func shouldShowOutlineBorder(isHomePage: Bool) -> Bool {
        return isHomePage
    }

    func sizeForSuggestionRow(isHomePage: Bool) -> CGFloat {
        return isHomePage ? 34 : 28
    }
}

final class CurrentAddressBarStyleProvider: AddressBarStyleProviding {
    private let navigationBarHeightForDefault: CGFloat = 52
    private let navigationBarHeightForHomePage: CGFloat = 52
    private let navigationBarHeightForPopUpWindow: CGFloat = 42
    private let addressBarTopPaddingForDefault: CGFloat = 6
    private let addressBarTopPaddingForHomePage: CGFloat = 6
    private let addressBarTopPaddingForPopUpWindow: CGFloat = 6
    private let addressBarBottomPaddingForDefault: CGFloat = 6
    private let addressBarBottomPaddingForHomePage: CGFloat = 6
    private let addressBarBottomPaddingForPopUpWindow: CGFloat = 6

    let defaultAddressBarFontSize: CGFloat = 13
    let newTabOrHomePageAddressBarFontSize: CGFloat = 13
    let addressBarButtonsCornerRadius: CGFloat = 9
    let addressBarLogoImage: NSImage? = DesignSystemImages.Glyphs.Size16.findSearch
    let shouldShowNewSearchIcon: Bool = true
    let shouldAddPaddingToAddressBarButtons: Bool = true
    let privacyShieldStyleProvider: PrivacyShieldAddressBarStyleProviding = CurrentPrivacyShieldAddressBarStyleProvider()
    let shouldAddAddressBarShadowWhenInactive: Bool = true
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

    func navigationBarHeight(for type: AddressBarSizeClass) -> CGFloat {
        switch type {
        case .default: return navigationBarHeightForDefault
        case .homePage: return navigationBarHeightForHomePage
        case .popUpWindow: return navigationBarHeightForPopUpWindow
        }
    }

    func addressBarTopPadding(for type: AddressBarSizeClass, focused: Bool) -> CGFloat {
        switch type {
        case .default: return focused ? addressBarTopPaddingForDefault - 1 : addressBarTopPaddingForDefault
        case .homePage: return focused ? addressBarTopPaddingForHomePage - 1 : addressBarTopPaddingForHomePage
        case .popUpWindow: return addressBarTopPaddingForPopUpWindow
        }
    }

    func addressBarBottomPadding(for type: AddressBarSizeClass, focused: Bool) -> CGFloat {
        switch type {
        case .default: return focused ? addressBarBottomPaddingForDefault - 1 : addressBarBottomPaddingForDefault
        case .homePage: return focused ? addressBarBottomPaddingForHomePage - 1 : addressBarBottomPaddingForHomePage
        case .popUpWindow: return addressBarBottomPaddingForPopUpWindow
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

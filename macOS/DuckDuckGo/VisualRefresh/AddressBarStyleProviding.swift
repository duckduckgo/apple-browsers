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
    func addressBarHeight(for type: AddressBarSizeClass, focused: Bool) -> CGFloat
    func addressBarTopPadding(for type: AddressBarSizeClass) -> CGFloat
    func addressBarBottomPadding(for type: AddressBarSizeClass) -> CGFloat
    func addressBarStackSpacing(for type: AddressBarSizeClass) -> CGFloat
    func shouldShowOutlineBorder(isHomePage: Bool) -> Bool

    var defaultAddressBarFontSize: CGFloat { get }
    var newTabOrHomePageAddressBarFontSize: CGFloat { get }
    var shouldShowLogoinInAddressBar: Bool { get }
    var addressBarLogoImage: NSImage? { get }
    var addressBarButtonsCornerRadius: CGFloat { get }
    var shouldAddPaddingToAddressBarButtons: Bool { get }
    var privacyShieldStyleProvider: PrivacyShieldAddressBarStyleProviding { get }
}

final class LegacyAddressBarStyleProvider: AddressBarStyleProviding {
    private let addressBarHeightForDefault: CGFloat = 48
    private let addressBarHeightForHomePage: CGFloat = 52
    private let addressBarHeightForPopUpWindow: CGFloat = 42
    private let addressBarTopPaddingForDefault: CGFloat = 6
    private let addressBarTopPaddingForHomePage: CGFloat = 10
    private let addressBarTopPaddingForPopUpWindow: CGFloat = 0
    private let addressBarBottomPaddingForDefault: CGFloat = 6
    private let addressBarBottomPaddingForHomePage: CGFloat = 8
    private let addressBarBottomPaddingForPopUpWindow: CGFloat = 0
    private let addressBarHeightWhenFocused: CGFloat = 48
    private let addressBarHeightForHomePageWhenFocused: CGFloat = 52

    let defaultAddressBarFontSize: CGFloat = 13
    let newTabOrHomePageAddressBarFontSize: CGFloat = 15
    let addressBarButtonsCornerRadius: CGFloat = 0
    let addressBarLogoImage: NSImage? = nil
    let shouldShowLogoinInAddressBar: Bool = false
    let shouldAddPaddingToAddressBarButtons: Bool = false
    let privacyShieldStyleProvider: PrivacyShieldAddressBarStyleProviding = LegacyPrivacyShieldAddressBarStyleProvider()

    func addressBarHeight(for type: AddressBarSizeClass, focused: Bool) -> CGFloat {
        switch type {
        case .default: return focused ? addressBarHeightWhenFocused : addressBarHeightForDefault
        case .homePage: return focused ? addressBarHeightForHomePageWhenFocused : addressBarHeightForHomePage
        case .popUpWindow: return addressBarHeightForPopUpWindow
        }
    }

    func addressBarTopPadding(for type: AddressBarSizeClass) -> CGFloat {
        switch type {
        case .default: return addressBarTopPaddingForDefault
        case .homePage: return addressBarTopPaddingForHomePage
        case .popUpWindow: return addressBarTopPaddingForPopUpWindow
        }
    }

    func addressBarBottomPadding(for type: AddressBarSizeClass) -> CGFloat {
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
}

final class CurrentAddressBarStyleProvider: AddressBarStyleProviding {
    private let addressBarHeightForDefault: CGFloat = 52
    private let addressBarHeightForHomePage: CGFloat = 52
    private let addressBarHeightForPopUpWindow: CGFloat = 52
    private let addressBarTopPaddingForDefault: CGFloat = 6
    private let addressBarTopPaddingForHomePage: CGFloat = 6
    private let addressBarTopPaddingForPopUpWindow: CGFloat = 6
    private let addressBarBottomPaddingForDefault: CGFloat = 6
    private let addressBarBottomPaddingForHomePage: CGFloat = 6
    private let addressBarBottomPaddingForPopUpWindow: CGFloat = 6
    private let addressBarHeightWhenFocused: CGFloat = 56
    private let addressBarHeightForHomePageWhenFocused: CGFloat = 56

    let defaultAddressBarFontSize: CGFloat = 13
    let newTabOrHomePageAddressBarFontSize: CGFloat = 13
    let addressBarButtonsCornerRadius: CGFloat = 9
    let addressBarLogoImage: NSImage? = DesignSystemImages.Color.Size24.duckDuckGo
    let shouldShowLogoinInAddressBar: Bool = true
    let shouldAddPaddingToAddressBarButtons: Bool = true
    let privacyShieldStyleProvider: PrivacyShieldAddressBarStyleProviding = CurrentPrivacyShieldAddressBarStyleProvider()

    func addressBarHeight(for type: AddressBarSizeClass, focused: Bool) -> CGFloat {
        switch type {
        case .default: return focused ? addressBarHeightWhenFocused : addressBarHeightForDefault
        case .homePage: return focused ? addressBarHeightForHomePageWhenFocused : addressBarHeightForHomePage
        case .popUpWindow: return addressBarHeightForPopUpWindow
        }
    }

    func addressBarTopPadding(for type: AddressBarSizeClass) -> CGFloat {
        switch type {
        case .default: return addressBarTopPaddingForDefault
        case .homePage: return addressBarTopPaddingForHomePage
        case .popUpWindow: return addressBarTopPaddingForPopUpWindow
        }
    }

    func addressBarBottomPadding(for type: AddressBarSizeClass) -> CGFloat {
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
        return true
    }
}

//
//  VisualStyleProviding.swift
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

import Combine
import BrowserServicesKit
import FeatureFlags
import NetworkProtectionUI

protocol VisualStyleProviding {
    /// Address bar
    func addressBarHeight(for type: AddressBarSizeClass) -> CGFloat
    func addressBarTopPadding(for type: AddressBarSizeClass) -> CGFloat
    func addressBarBottomPadding(for type: AddressBarSizeClass) -> CGFloat
    func addressBarStackSpacing(for type: AddressBarSizeClass) -> CGFloat
    func shouldShowOutlineBorder(isHomePage: Bool) -> Bool
    var addressBarSuffixTextColor: NSColor { get }
    var addressBarTextFieldColor: NSColor { get }
    var defaultAddressBarFontSize: CGFloat { get }
    var newTabOrHomePageAddressBarFontSize: CGFloat { get }
    var addressBarIconsProvider: AddressBarIconsProviding { get }
    var privacyShieldStyleProvider: PrivacyShieldAddressBarStyleProviding { get }
    var shouldShowLogoinInAddressBar: Bool { get }

    /// Navigation toolbar
    var backButtonImage: NSImage { get }
    var forwardButtonImage: NSImage { get }
    var reloadButtonImage: NSImage { get }
    var homeButtonImage: NSImage { get }
    var downloadsButtonImage: NSImage { get }
    var passwordManagerButtonImage: NSImage { get }
    var bookmarksButtonImage: NSImage { get }
    var moreOptionsbuttonImage: NSImage { get }
    var overflowButtonImage: NSImage { get }
    var toolbarButtonsCornerRadius: CGFloat { get }
    var navigationBackgroundColor: NSColor { get }

    /// General colors
    var baseBackgroundColor: NSColor { get }
    var textPrimaryColor: NSColor { get }
    var textSecondaryColor: NSColor { get }
    var backgroundTertiaryColor: NSColor { get }
    var accentPrimaryColor: NSColor { get }
    var accentAlternateColor: NSColor { get }
    var iconsColor: NSColor { get }
    var buttonMouseOverColor: NSColor { get }

    /// New Tab Page
    var ntpLightBackgroundColor: String { get }
    var ntpDarkBackgroundColor: String { get }

    /// Other
    var vpnNavigationIconsProvider: IconProvider { get }
    var fireButtonStyleProvider: FireButtonIconStyleProviding { get }
    var moreOptionsMenuIconsProvider: MoreOptionsMenuIconsProviding { get }
    var tabStyleProvider: TabStyleProviding { get }
}

protocol VisualStyleManagerProviding {
    var style: any VisualStyleProviding { get }
}

enum AddressBarSizeClass {
    case `default`
    case homePage
    case popUpWindow

    var logoWidth: CGFloat {
        switch self {
        case .homePage: 44
        case .popUpWindow, .default: 0
        }
    }

    var isLogoVisible: Bool {
        switch self {
        case .homePage: true
        case .popUpWindow, .default: false
        }
    }
}

struct VisualStyle: VisualStyleProviding {
    private let addressBarHeightForDefault: CGFloat
    private let addressBarHeightForHomePage: CGFloat
    private let addressBarHeightForPopUpWindow: CGFloat
    private let addressBarTopPaddingForDefault: CGFloat
    private let addressBarTopPaddingForHomePage: CGFloat
    private let addressBarTopPaddingForPopUpWindow: CGFloat
    private let addressBarBottomPaddingForDefault: CGFloat
    private let addressBarBottomPaddingForHomePage: CGFloat
    private let addressBarBottomPaddingForPopUpWindow: CGFloat
    private let alwaysShowAddressBarOutline: Bool

    let shouldShowLogoinInAddressBar: Bool
    let toolbarButtonsCornerRadius: CGFloat

    let backButtonImage: NSImage
    let forwardButtonImage: NSImage
    let reloadButtonImage: NSImage
    let homeButtonImage: NSImage
    let downloadsButtonImage: NSImage
    let passwordManagerButtonImage: NSImage
    let bookmarksButtonImage: NSImage
    let moreOptionsbuttonImage: NSImage
    let overflowButtonImage: NSImage
    let vpnNavigationIconsProvider: IconProvider
    let fireButtonStyleProvider: FireButtonIconStyleProviding
    let moreOptionsMenuIconsProvider: MoreOptionsMenuIconsProviding
    let privacyShieldStyleProvider: PrivacyShieldAddressBarStyleProviding
    let addressBarIconsProvider: AddressBarIconsProviding
    let tabStyleProvider: TabStyleProviding
    let navigationBackgroundColor: NSColor
    let baseBackgroundColor: NSColor
    let textPrimaryColor: NSColor
    let textSecondaryColor: NSColor
    let backgroundTertiaryColor: NSColor
    let accentPrimaryColor: NSColor
    let accentAlternateColor: NSColor
    let addressBarSuffixTextColor: NSColor
    let addressBarTextFieldColor: NSColor
    let iconsColor: NSColor
    let buttonMouseOverColor: NSColor

    let ntpLightBackgroundColor: String
    let ntpDarkBackgroundColor: String

    let defaultAddressBarFontSize: CGFloat
    let newTabOrHomePageAddressBarFontSize: CGFloat

    func addressBarHeight(for type: AddressBarSizeClass) -> CGFloat {
        switch type {
        case .default: return addressBarHeightForDefault
        case .homePage: return addressBarHeightForHomePage
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
        return alwaysShowAddressBarOutline || isHomePage
    }

    static var legacy: VisualStyleProviding {
        return VisualStyle(addressBarHeightForDefault: 48,
                           addressBarHeightForHomePage: 52,
                           addressBarHeightForPopUpWindow: 42,
                           addressBarTopPaddingForDefault: 6,
                           addressBarTopPaddingForHomePage: 10,
                           addressBarTopPaddingForPopUpWindow: 0,
                           addressBarBottomPaddingForDefault: 6,
                           addressBarBottomPaddingForHomePage: 8,
                           addressBarBottomPaddingForPopUpWindow: 0,
                           alwaysShowAddressBarOutline: false,
                           shouldShowLogoinInAddressBar: false,
                           toolbarButtonsCornerRadius: 4,
                           backButtonImage: .back,
                           forwardButtonImage: .forward,
                           reloadButtonImage: .refresh,
                           homeButtonImage: .home16,
                           downloadsButtonImage: .downloads,
                           passwordManagerButtonImage: .passwordManagement,
                           bookmarksButtonImage: .bookmarks,
                           moreOptionsbuttonImage: .settings,
                           overflowButtonImage: .chevronDoubleRight16,
                           vpnNavigationIconsProvider: NavigationBarIconProvider(),
                           fireButtonStyleProvider: LegacyFireButtonIconStyleProvider(),
                           moreOptionsMenuIconsProvider: LegacyMoreOptionsMenuIcons(),
                           privacyShieldStyleProvider: LegacyPrivacyShieldAddressBarStyleProvider(),
                           addressBarIconsProvider: LegacyAddressBarIconsProvider(),
                           tabStyleProvider: LegacyTabStyleProvider(),
                           navigationBackgroundColor: .navigationBarBackground,
                           baseBackgroundColor: .windowBackground,
                           textPrimaryColor: .labelColor,
                           textSecondaryColor: .secondaryLabelColor,
                           backgroundTertiaryColor: .inactiveSearchBarBackground,
                           accentPrimaryColor: .controlAccentColor.withAlphaComponent(0.8),
                           accentAlternateColor: .controlColor.withAlphaComponent(0.2),
                           addressBarSuffixTextColor: .addressBarSuffix,
                           addressBarTextFieldColor: .suggestionText,
                           iconsColor: .button,
                           buttonMouseOverColor: .buttonMouseOver,
                           ntpLightBackgroundColor: "#FAFAFA",
                           ntpDarkBackgroundColor: "#333333",
                           defaultAddressBarFontSize: 13,
                           newTabOrHomePageAddressBarFontSize: 15)
    }

    static var current: VisualStyleProviding {
        return VisualStyle(addressBarHeightForDefault: 52,
                           addressBarHeightForHomePage: 52,
                           addressBarHeightForPopUpWindow: 52,
                           addressBarTopPaddingForDefault: 6,
                           addressBarTopPaddingForHomePage: 6,
                           addressBarTopPaddingForPopUpWindow: 6,
                           addressBarBottomPaddingForDefault: 6,
                           addressBarBottomPaddingForHomePage: 6,
                           addressBarBottomPaddingForPopUpWindow: 6,
                           alwaysShowAddressBarOutline: true,
                           shouldShowLogoinInAddressBar: true,
                           toolbarButtonsCornerRadius: 9,
                           backButtonImage: .backNew,
                           forwardButtonImage: .forwardNew,
                           reloadButtonImage: .reloadNew,
                           homeButtonImage: .homeNew,
                           downloadsButtonImage: .downloadsNew,
                           passwordManagerButtonImage: .passwordManagerNew,
                           bookmarksButtonImage: .bookmarksNew,
                           moreOptionsbuttonImage: .optionsNew,
                           overflowButtonImage: .chevronDoubleRight16,
                           vpnNavigationIconsProvider: NewVPNNavigationBarIconProvider(),
                           fireButtonStyleProvider: NewFireButtonIconStyleProvider(),
                           moreOptionsMenuIconsProvider: NewMoreOptionsMenuIcons(),
                           privacyShieldStyleProvider: NewPrivacyShieldAddressBarStyleProvider(),
                           addressBarIconsProvider: NewAddressBarIconsProvider(),
                           tabStyleProvider: NewlineTabStyleProvider(),
                           navigationBackgroundColor: .navigationBackgroundColorNew,
                           baseBackgroundColor: .backgroundBaseColorNew,
                           textPrimaryColor: .primaryTextColorNew,
                           textSecondaryColor: .secondaryTextColorNew,
                           backgroundTertiaryColor: .surfaceTertiaryNew,
                           accentPrimaryColor: .accentPrimaryNew,
                           accentAlternateColor: .accentAltNew,
                           addressBarSuffixTextColor: .accentPrimaryNew,
                           addressBarTextFieldColor: .primaryTextColorNew,
                           iconsColor: .iconsPrimaryNew,
                           buttonMouseOverColor: .controlsFillPrimaryNew,
                           ntpLightBackgroundColor: "#E9EBEC",
                           ntpDarkBackgroundColor: "#27282A",
                           defaultAddressBarFontSize: 13,
                           newTabOrHomePageAddressBarFontSize: 13)
    }
}

final class VisualStyleManager: VisualStyleManagerProviding {
    private let featureFlagger: FeatureFlagger

    private var cancellables: Set<AnyCancellable> = []

    init(featureFlagger: FeatureFlagger) {
        self.featureFlagger = featureFlagger

        subscribeToLocalOverride()
    }

    var style: any VisualStyleProviding {
        return featureFlagger.isFeatureOn(.visualRefresh) ? VisualStyle.current : VisualStyle.legacy
    }

    private func subscribeToLocalOverride() {
        guard let overridesHandler = featureFlagger.localOverrides?.actionHandler as? FeatureFlagOverridesPublishingHandler<FeatureFlag> else {
            return
        }

        overridesHandler.flagDidChangePublisher
            .filter { $0.0 == .visualRefresh }
            .sink { (_, enabled) in
                /// Here I need to apply the visual changes. The easier way should be to restart the app.
                print("Visual refresh feature flag changed to \(enabled ? "enabled" : "disabled")")
            }
            .store(in: &cancellables)
    }
}

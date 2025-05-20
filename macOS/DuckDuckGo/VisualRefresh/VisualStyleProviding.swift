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
    func addressBarHeight(for type: AddressBarSizeClass, focused: Bool) -> CGFloat
    func addressBarTopPadding(for type: AddressBarSizeClass) -> CGFloat
    func addressBarBottomPadding(for type: AddressBarSizeClass) -> CGFloat
    func addressBarStackSpacing(for type: AddressBarSizeClass) -> CGFloat
    func shouldShowOutlineBorder(isHomePage: Bool) -> Bool
    var defaultAddressBarFontSize: CGFloat { get }
    var newTabOrHomePageAddressBarFontSize: CGFloat { get }
    var addressBarIconsProvider: AddressBarIconsProviding { get }
    var privacyShieldStyleProvider: PrivacyShieldAddressBarStyleProviding { get }
    var shouldShowLogoinInAddressBar: Bool { get }
    var addressBarButtonsCornerRadius: CGFloat { get }
    var shouldAddPaddingToAddressBarButtons: Bool { get }

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
    var aiChatButtonImage: NSImage { get }
    var toolbarButtonsCornerRadius: CGFloat { get }
    var fireWindowGraphic: NSImage { get }
    var areNavigationBarCornersRound: Bool { get }
    var bookmarksBarMenuBookmarkIcon: NSImage { get }
    var bookmarksBarMenuFolderIcon: NSImage { get }

    /// Other
    var vpnNavigationIconsProvider: IconProvider { get }
    var fireButtonStyleProvider: FireButtonIconStyleProviding { get }
    var moreOptionsMenuIconsProvider: MoreOptionsMenuIconsProviding { get }
    var tabStyleProvider: TabStyleProviding { get }
    var colorsProvider: ColorsProviding { get }
    var fireButtonSize: CGFloat { get }

    var addressBarActiveBackgroundViewRadius: CGFloat { get }
    var addressBarInactiveBackgroundViewRadius: CGFloat { get }
    var addressBarInnerBorderViewRadius: CGFloat { get }
    var addressBarActiveOuterBorderViewRadius: CGFloat { get }
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
    private let addressBarHeightWhenFocused: CGFloat
    private let addressBarHeightForHomePageWhenFocused: CGFloat

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
    let aiChatButtonImage: NSImage
    let vpnNavigationIconsProvider: IconProvider
    let fireButtonStyleProvider: FireButtonIconStyleProviding
    let moreOptionsMenuIconsProvider: MoreOptionsMenuIconsProviding
    let privacyShieldStyleProvider: PrivacyShieldAddressBarStyleProviding
    let addressBarIconsProvider: AddressBarIconsProviding
    let addressBarButtonsCornerRadius: CGFloat
    let shouldAddPaddingToAddressBarButtons: Bool
    let tabStyleProvider: TabStyleProviding
    let fireWindowGraphic: NSImage
    let areNavigationBarCornersRound: Bool
    let colorsProvider: ColorsProviding
    let defaultAddressBarFontSize: CGFloat
    let newTabOrHomePageAddressBarFontSize: CGFloat
    let bookmarksBarMenuBookmarkIcon: NSImage
    let bookmarksBarMenuFolderIcon: NSImage
    let fireButtonSize: CGFloat
    let addressBarActiveBackgroundViewRadius: CGFloat
    let addressBarInactiveBackgroundViewRadius: CGFloat
    let addressBarInnerBorderViewRadius: CGFloat
    let addressBarActiveOuterBorderViewRadius: CGFloat

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
                           addressBarHeightWhenFocused: 48,
                           addressBarHeightForHomePageWhenFocused: 52,
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
                           aiChatButtonImage: .aiChat,
                           vpnNavigationIconsProvider: NavigationBarIconProvider(),
                           fireButtonStyleProvider: LegacyFireButtonIconStyleProvider(),
                           moreOptionsMenuIconsProvider: LegacyMoreOptionsMenuIcons(),
                           privacyShieldStyleProvider: LegacyPrivacyShieldAddressBarStyleProvider(),
                           addressBarIconsProvider: LegacyAddressBarIconsProvider(),
                           addressBarButtonsCornerRadius: 0,
                           shouldAddPaddingToAddressBarButtons: false,
                           tabStyleProvider: LegacyTabStyleProvider(),
                           fireWindowGraphic: .burnerWindowGraphic,
                           areNavigationBarCornersRound: false,
                           colorsProvider: LegacyColorsProviding(),
                           defaultAddressBarFontSize: 13,
                           newTabOrHomePageAddressBarFontSize: 15,
                           bookmarksBarMenuBookmarkIcon: .bookmark,
                           bookmarksBarMenuFolderIcon: .folder16,
                           fireButtonSize: 28,
                           addressBarActiveBackgroundViewRadius: 8,
                           addressBarInactiveBackgroundViewRadius: 6,
                           addressBarInnerBorderViewRadius: 8,
                           addressBarActiveOuterBorderViewRadius: 10)
    }

    static var current: VisualStyleProviding {
        let palette = NewColorPalette()
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
                           addressBarHeightWhenFocused: 56,
                           addressBarHeightForHomePageWhenFocused: 56,
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
                           aiChatButtonImage: .aiChatNew,
                           vpnNavigationIconsProvider: NewVPNNavigationBarIconProvider(),
                           fireButtonStyleProvider: NewFireButtonIconStyleProvider(),
                           moreOptionsMenuIconsProvider: NewMoreOptionsMenuIcons(),
                           privacyShieldStyleProvider: NewPrivacyShieldAddressBarStyleProvider(),
                           addressBarIconsProvider: NewAddressBarIconsProvider(),
                           addressBarButtonsCornerRadius: 9,
                           shouldAddPaddingToAddressBarButtons: true,
                           tabStyleProvider: NewlineTabStyleProvider(palette: palette),
                           fireWindowGraphic: .burnerWindowGraphicNew,
                           areNavigationBarCornersRound: true,
                           colorsProvider: NewColorsProviding(palette: palette),
                           defaultAddressBarFontSize: 13,
                           newTabOrHomePageAddressBarFontSize: 13,
                           bookmarksBarMenuBookmarkIcon: .bookmarkNew,
                           bookmarksBarMenuFolderIcon: .folderNew,
                           fireButtonSize: 32,
                           addressBarActiveBackgroundViewRadius: 11,
                           addressBarInactiveBackgroundViewRadius: 11,
                           addressBarInnerBorderViewRadius: 11,
                           addressBarActiveOuterBorderViewRadius: 13)
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

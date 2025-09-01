//
//  PreferencesSection.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

import Foundation
import SwiftUI
import Subscription
import SubscriptionUI
import BrowserServicesKit

struct PreferencesSection: Hashable, Identifiable {
    let id: PreferencesSectionIdentifier
    let panes: [PreferencePaneIdentifier]

    @MainActor
    static func defaultSections(includingDuckPlayer: Bool,
                                includingSync: Bool,
                                includingAIChat: Bool,
                                subscriptionState: PreferencesSidebarSubscriptionState) -> [PreferencesSection] {
        let privacyPanes: [PreferencePaneIdentifier] = [
            .defaultBrowser, .privateSearch, .webTrackingProtection, .threatProtection, .cookiePopupProtection, .emailProtection
        ]

        let regularPanes: [PreferencePaneIdentifier] = {
            var panes: [PreferencePaneIdentifier] = [.appearance, .autofill, .accessibility, .dataClearing]

            if includingSync {
                panes.append(.sync)
            }

            if includingDuckPlayer {
                panes.append(.duckPlayer)
            }

            if includingAIChat {
                panes.append(.aiChat)
            }

            return [.general] + panes.sorted { $0.displayName.lowercased() < $1.displayName.lowercased() }
        }()

#if APPSTORE
        // App Store guidelines don't allow references to other platforms, so the Mac App Store build omits the otherPlatforms section.
        let otherPanes: [PreferencePaneIdentifier] = [.about]
#else
        let otherPanes: [PreferencePaneIdentifier] = [.about, .otherPlatforms]
#endif

        var sections: [PreferencesSection] = [
            .init(id: .privacyProtections, panes: privacyPanes),
            .init(id: .regularPreferencePanes, panes: regularPanes),
            .init(id: .about, panes: otherPanes)
        ]

        if let subscriptionSection = makeSubscriptionSection(subscriptionState: subscriptionState) {
            sections.insert(subscriptionSection, at: 1)
        }

        return sections
    }

    private static func makeSubscriptionSection(subscriptionState: PreferencesSidebarSubscriptionState) -> PreferencesSection? {
        if subscriptionState.hasSubscription {
            var subscriptionPanes: [PreferencePaneIdentifier] = []

            if subscriptionState.isNetworkProtectionRemovalAvailable {
                subscriptionPanes.append(.vpn)
            }
            if subscriptionState.isPersonalInformationRemovalAvailable {
                subscriptionPanes.append(.personalInformationRemoval)
            }
            if subscriptionState.isPaidAIChatAvailable {
                subscriptionPanes.append(.paidAIChat)
            }
            if subscriptionState.isIdentityTheftRestorationAvailable {
                subscriptionPanes.append(.identityTheftRestoration)
            }

            subscriptionPanes.append(.subscriptionSettings)
            return PreferencesSection(id: .privacyPro, panes: subscriptionPanes)
        } else if subscriptionState.shouldHideSubscriptionPurchase {
            // No active subscription and no option to purchase
            return nil
        } else {
            // No active subscription
            return PreferencesSection(id: .purchasePrivacyPro, panes: [.privacyPro])
        }
    }
}

enum PreferencesSectionIdentifier: Hashable, CaseIterable {
    case privacyProtections
    case purchasePrivacyPro
    case privacyPro
    case regularPreferencePanes
    case about

    var displayName: String? {
        switch self {
        case .privacyProtections:
            return UserText.privacyProtections
        case .purchasePrivacyPro:
            return nil
        case .privacyPro:
            return UserText.subscriptionDeprecated
        case .regularPreferencePanes:
            return UserText.mainSettings
        case .about:
            return nil
        }
    }

    @MainActor
    func displayName(isSubscriptionRebrandingOn: Bool) -> String? {
        switch self {
        case .privacyPro:
            return UserText.subscriptionSettingsHeader(isSubscriptionRebrandingOn: isSubscriptionRebrandingOn)
        default:
            return displayName
        }
    }

}

enum PreferencePaneIdentifier: String, Equatable, Hashable, Identifiable, CaseIterable {
    case defaultBrowser
    case privateSearch
    case webTrackingProtection
    case threatProtection
    case cookiePopupProtection
    case emailProtection

    case general
    case sync
    case appearance
    case dataClearing
    case privacyPro
    case vpn
    case personalInformationRemoval
    case paidAIChat
    case identityTheftRestoration
    case subscriptionSettings
    case autofill
    case accessibility
    case duckPlayer = "duckplayer"
    case otherPlatforms = "https://duckduckgo.com/app/devices?origin=funnel_app_macos"
    case aiChat = "aichat"
    case about

    var id: Self {
        self
    }

    init?(url: URL) {
        // manually extract path because URLs such as "about:settings" can't figure out their host or path
        for urlPrefix in [URL.settings, URL.Invalid.aboutPreferences, URL.Invalid.aboutConfig, URL.Invalid.aboutSettings, URL.Invalid.duckConfig, URL.Invalid.duckPreferences] {
            let prefix = urlPrefix.absoluteString + "/"
            guard url.absoluteString.hasPrefix(prefix) else { continue }

            let path = url.absoluteString.dropping(prefix: prefix)
            self.init(rawValue: path)
            return
        }
        return nil
    }

    @MainActor
    var displayName: String {
        switch self {
        case .defaultBrowser:
            return UserText.defaultBrowser
        case .privateSearch:
            return UserText.privateSearch
        case .webTrackingProtection:
            return UserText.webTrackingProtection
        case .threatProtection:
            return UserText.threatProtection
        case .cookiePopupProtection:
            return UserText.cookiePopUpProtection
        case .emailProtection:
            return UserText.emailProtectionPreferences
        case .general:
            return UserText.general
        case .sync:
            let isSyncBookmarksPaused = UserDefaults.standard.bool(forKey: UserDefaultsWrapper<Bool>.Key.syncBookmarksPaused.rawValue)
            let isSyncCredentialsPaused = UserDefaults.standard.bool(forKey: UserDefaultsWrapper<Bool>.Key.syncCredentialsPaused.rawValue)
            let isSyncPaused = UserDefaults.standard.bool(forKey: UserDefaultsWrapper<Bool>.Key.syncIsPaused.rawValue)
            let syncService = NSApp.delegateTyped.syncService
            let isDataSyncingDisabled = syncService?.featureFlags.contains(.dataSyncing) == false && syncService?.authState == .active
            if isSyncPaused || isSyncBookmarksPaused || isSyncCredentialsPaused || isDataSyncingDisabled {
                return UserText.sync + " ⚠️"
            }
            return UserText.sync
        case .appearance:
            return UserText.appearance
        case .dataClearing:
            return UserText.dataClearing
        case .privacyPro:
            return UserText.subscriptionDeprecated
        case .vpn:
            return UserText.vpn
        case .personalInformationRemoval:
            return UserText.personalInformationRemoval
        case .paidAIChat:
            return UserText.paidAIChat
        case .identityTheftRestoration:
            return UserText.identityTheftRestoration
        case .subscriptionSettings:
            return UserText.subscriptionSettings
        case .autofill:
            return UserText.passwordManagementTitle
        case .accessibility:
            return UserText.accessibility
        case .duckPlayer:
            return UserText.duckPlayer
        case .aiChat:
            return UserText.aiFeatures
        case .about:
            return UserText.about
        case .otherPlatforms:
            return UserText.duckduckgoOnOtherPlatforms
        }
    }

    /// Returns the display name with context-aware rebranding support
    @MainActor
    func displayName(isSubscriptionRebrandingOn: Bool) -> String {
        switch self {
        case .privacyPro:
            return UserText.purchaseSubscriptionPaneTitle(isSubscriptionRebrandingOn: isSubscriptionRebrandingOn)
        default:
            return displayName
        }
    }

    func preferenceIconName(for settingsIconProvider: SettingsIconsProviding, isSubscriptionRebrandingOn: Bool) -> NSImage {
        switch self {
        case .defaultBrowser:
            return settingsIconProvider.defaultBrowserIcon
        case .privateSearch:
            return settingsIconProvider.privateSearchIcon
        case .webTrackingProtection:
            return settingsIconProvider.webTrackingProtectionIcon
        case .threatProtection:
            return settingsIconProvider.threatProtectionIcon
        case .cookiePopupProtection:
            return settingsIconProvider.cookiePopUpProtectionIcon
        case .emailProtection:
            return settingsIconProvider.emailProtectionIcon
        case .general:
            return settingsIconProvider.generalIcon
        case .sync:
            return settingsIconProvider.syncAndBackupIcon
        case .appearance:
            return settingsIconProvider.appearanceIcon
        case .dataClearing:
            return settingsIconProvider.dataClearingIcon
        case .privacyPro:
            return settingsIconProvider.privacyProIcon
        case .vpn:
            return settingsIconProvider.vpnIcon
        case .personalInformationRemoval:
            return settingsIconProvider.personalInformationRemovalIcon
        case .paidAIChat:
            return settingsIconProvider.duckAIIcon
        case .identityTheftRestoration:
            return settingsIconProvider.identityTheftRestorationIcon
        case .subscriptionSettings:
            return settingsIconProvider.privacyProIcon
        case .autofill:
            return settingsIconProvider.passwordsAndAutoFillIcon
        case .accessibility:
            return settingsIconProvider.accessibilityIcon
        case .duckPlayer:
            return settingsIconProvider.duckPlayerIcon
        case .about:
            return settingsIconProvider.aboutIcon
        case .otherPlatforms:
            return settingsIconProvider.otherPlatformsIcon
        case .aiChat:
            if isSubscriptionRebrandingOn {
                return settingsIconProvider.aiGeneralIcon
            }
            return settingsIconProvider.duckAIIcon
        }
    }
}

//
//  SettingsIconsProviding.swift
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

protocol SettingsIconsProviding {
    var defaultBrowserIcon: NSImage { get }
    var privateSearchIcon: NSImage { get }
    var webTrackingProtectionIcon: NSImage { get }
    var cookiePopUpProtectionIcon: NSImage { get }
    var emailProtectionIcon: NSImage { get }
    var privacyProIcon: NSImage { get }
    var vpnIcon: NSImage { get }
    var personalInformationRemovalIcon: NSImage { get }
    var identityTheftRestorationIcon: NSImage { get }
    var generalIcon: NSImage { get }
    var syncAndBackupIcon: NSImage { get }
    var appearanceIcon: NSImage { get }
    var passwordsAndAutoFillIcon: NSImage { get }
    var accessibilityIcon: NSImage { get }
    var dataClearingIcon: NSImage { get }
    var duckPlayerIcon: NSImage { get }
    var duckAIIcon: NSImage { get }
    var aboutIcon: NSImage { get }
    var otherPlatformsIcon: NSImage { get }
}

final class LegacySettingsIconProvider: SettingsIconsProviding {
    var defaultBrowserIcon: NSImage = .defaultBrowser
    var privateSearchIcon: NSImage = .privateSearchIcon
    var webTrackingProtectionIcon: NSImage = .webTrackingProtectionIcon
    var cookiePopUpProtectionIcon: NSImage = .cookieProtectionIcon
    var emailProtectionIcon: NSImage = .emailProtectionIcon
    var privacyProIcon: NSImage = .privacyPro
    var vpnIcon: NSImage = .VPN
    var personalInformationRemovalIcon: NSImage = .personalInformationRemovalMulticolor16
    var identityTheftRestorationIcon: NSImage = .identityTheftRestorationMulticolor16
    var generalIcon: NSImage = .generalIcon
    var syncAndBackupIcon: NSImage = .sync
    var appearanceIcon: NSImage = .appearance
    var passwordsAndAutoFillIcon: NSImage = .autofill
    var accessibilityIcon: NSImage = .accessibility
    var dataClearingIcon: NSImage = .fireSettings
    var duckPlayerIcon: NSImage = .duckPlayerSettings
    var duckAIIcon: NSImage = .aiChatPreferences
    var aboutIcon: NSImage = .about
    var otherPlatformsIcon: NSImage = .otherPlatformsPreferences
}

final class CurrentSettingsIconProvider: SettingsIconsProviding {
    var defaultBrowserIcon: NSImage = DesignSystemImages.Color.Size16.defaultBrowser
    var privateSearchIcon: NSImage = DesignSystemImages.Color.Size16.findSearch
    var webTrackingProtectionIcon: NSImage = DesignSystemImages.Color.Size16.shieldCheck
    var cookiePopUpProtectionIcon: NSImage = DesignSystemImages.Color.Size16.cookie
    var emailProtectionIcon: NSImage = DesignSystemImages.Color.Size16.emailProtection
    var privacyProIcon: NSImage = DesignSystemImages.Color.Size16.privacyPro
    var vpnIcon: NSImage = DesignSystemImages.Color.Size16.vpn
    var personalInformationRemovalIcon: NSImage = DesignSystemImages.Color.Size16.identityBlockedPIR
    var identityTheftRestorationIcon: NSImage = DesignSystemImages.Color.Size16.identityTheftRestoration
    var generalIcon: NSImage = DesignSystemImages.Color.Size16.settings
    var syncAndBackupIcon: NSImage = DesignSystemImages.Color.Size16.sync
    var appearanceIcon: NSImage = DesignSystemImages.Color.Size16.appearance
    var passwordsAndAutoFillIcon: NSImage = DesignSystemImages.Color.Size16.key
    var accessibilityIcon: NSImage = DesignSystemImages.Color.Size16.accessibility
    var dataClearingIcon: NSImage = DesignSystemImages.Color.Size16.fireNewColor
    var duckPlayerIcon: NSImage = DesignSystemImages.Color.Size16.videoPlayer
    var duckAIIcon: NSImage = DesignSystemImages.Color.Size16.aiChat
    var aboutIcon: NSImage = DesignSystemImages.Color.Size16.duckDuckGo
    var otherPlatformsIcon: NSImage = DesignSystemImages.Color.Size16.downloads
}

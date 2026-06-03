//
//  MacOSWebExtensionPixelFiring.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

import PixelKit
import WebExtensions

enum WebExtensionPixel: PixelKitEvent {

    // MARK: - Installation

    case installed
    case installError(error: Error)

    // MARK: - Uninstallation

    case uninstalled
    case uninstallError(error: Error)
    case uninstalledAll
    case uninstallAllError(error: Error)

    // MARK: - Loading (Startup)

    case loaded
    case loadError(error: Error)

    // MARK: - Embedded Extensions

    case embeddedInstalled
    case embeddedUpgraded(fromVersion: String?, toVersion: String?)
    case embeddedInstallError(error: Error)

    // MARK: - DarkReader Extensions

    case darkReaderInstalled
    case darkReaderUpgraded(fromVersion: String?, toVersion: String?)
    case darkReaderInstallError(error: Error)
    case darkReaderEnabled
    case darkReaderDisabled

    // MARK: - Ad Blocking Extension

    case adBlockingExtensionInstalled
    case adBlockingExtensionUpgraded(fromVersion: String?, toVersion: String?)
    case adBlockingExtensionInstallError(error: Error)
    case adBlockingExtensionEnabled
    case adBlockingExtensionDisabled

    case adBlockingExtensionAddressBarActiveClicked
    case adBlockingExtensionAddressBarInactiveClicked
    case adBlockingExtensionPopoverAlwaysOn
    case adBlockingExtensionPopoverAlwaysOff
    case adBlockingExtensionPopoverDisableUntilRelaunch
    case adBlockingExtensionBreakageReportEntered

    // MARK: - Scriptlet Lifecycle

    case scriptletFetchSuccess(extensionType: String, version: String, count: Int)
    case scriptletFetchError(extensionType: String, error: Error)
    case scriptletValidationError(extensionType: String, error: Error)
    case scriptletInstalled(extensionType: String, version: String)
    case scriptletInstallError(extensionType: String, error: Error)

    // MARK: - Daily State

    case dailyAdBlockingState(isEnabled: Bool, analyticsEnabled: Bool)

    // MARK: - Ad Blocking Detection Events

    case adBlockingDetectedAdBlocker(loginState: String)
    case adBlockingDetectedPlayabilityError(loginState: String)
    case adBlockingDetectedVideoAd(loginState: String)
    case adBlockingDetectedStaticAd(loginState: String)
    case adBlockingDetectedBuffering(loginState: String)

    // MARK: - PixelKitEvent

    var name: String {
        switch self {
        case .installed:
            return "m_mac_web_extension_installed"
        case .installError:
            return "m_mac_web_extension_install_error"
        case .uninstalled:
            return "m_mac_web_extension_uninstalled"
        case .uninstallError:
            return "m_mac_web_extension_uninstall_error"
        case .uninstalledAll:
            return "m_mac_web_extension_uninstalled_all"
        case .uninstallAllError:
            return "m_mac_web_extension_uninstall_all_error"
        case .loaded:
            return "m_mac_web_extension_loaded"
        case .loadError:
            return "m_mac_web_extension_load_error"
        case .embeddedInstalled:
            return "m_mac_web_extension_embedded_installed"
        case .embeddedUpgraded:
            return "m_mac_web_extension_embedded_upgraded"
        case .embeddedInstallError:
            return "m_mac_web_extension_embedded_install_error"
        case .darkReaderInstalled:
            return "m_mac_web_extension_dark_reader_installed"
        case .darkReaderUpgraded:
            return "m_mac_web_extension_dark_reader_upgraded"
        case .darkReaderInstallError:
            return "m_mac_web_extension_dark_reader_install_error"
        case .darkReaderEnabled:
            return "m_mac_web_extension_dark_reader_enabled"
        case .darkReaderDisabled:
            return "m_mac_web_extension_dark_reader_disabled"
        case .adBlockingExtensionInstalled:
            return "m_mac_web_extension_ad_blocking_installed"
        case .adBlockingExtensionUpgraded:
            return "m_mac_web_extension_ad_blocking_upgraded"
        case .adBlockingExtensionInstallError:
            return "m_mac_web_extension_ad_blocking_install_error"
        case .adBlockingExtensionEnabled:
            return "m_mac_web_extension_ad_blocking_enabled"
        case .adBlockingExtensionDisabled:
            return "m_mac_web_extension_ad_blocking_disabled"
        case .adBlockingExtensionAddressBarActiveClicked:
            return "m_mac_web_extension_ad_blocking_addressbar_active_clicked"
        case .adBlockingExtensionAddressBarInactiveClicked:
            return "m_mac_web_extension_ad_blocking_addressbar_inactive_clicked"
        case .adBlockingExtensionPopoverAlwaysOn:
            return "m_mac_web_extension_ad_blocking_popover_always_on"
        case .adBlockingExtensionPopoverAlwaysOff:
            return "m_mac_web_extension_ad_blocking_popover_always_off"
        case .adBlockingExtensionPopoverDisableUntilRelaunch:
            return "m_mac_web_extension_ad_blocking_popover_disable_until_relaunch"
        case .adBlockingExtensionBreakageReportEntered:
            return "m_mac_web_extension_ad_blocking_breakage_report_entered"
        case .scriptletFetchSuccess:
            return "m_mac_web_extension_scriptlet_fetch_success"
        case .scriptletFetchError:
            return "m_mac_web_extension_scriptlet_fetch_error"
        case .scriptletValidationError:
            return "m_mac_web_extension_scriptlet_validation_error"
        case .scriptletInstalled:
            return "m_mac_web_extension_scriptlet_installed"
        case .scriptletInstallError:
            return "m_mac_web_extension_scriptlet_install_error"
        case .dailyAdBlockingState:
            return "m_mac_web_extension_daily_ad_blocking_state"
        case .adBlockingDetectedAdBlocker:
            return "m_mac_web_extension_adblocking_detected_ad_blocker"
        case .adBlockingDetectedPlayabilityError:
            return "m_mac_web_extension_adblocking_detected_playability_error"
        case .adBlockingDetectedVideoAd:
            return "m_mac_web_extension_adblocking_detected_video_ad"
        case .adBlockingDetectedStaticAd:
            return "m_mac_web_extension_adblocking_detected_static_ad"
        case .adBlockingDetectedBuffering:
            return "m_mac_web_extension_adblocking_detected_buffering"
        }
    }

    var parameters: [String: String]? {
        switch self {
        case .embeddedUpgraded(let fromVersion, let toVersion),
             .darkReaderUpgraded(let fromVersion, let toVersion),
             .adBlockingExtensionUpgraded(let fromVersion, let toVersion):
            var params: [String: String] = [:]
            if let fromVersion {
                params["from_version"] = fromVersion
            }
            if let toVersion {
                params["to_version"] = toVersion
            }
            return params.isEmpty ? nil : params
        case .scriptletFetchSuccess(let extensionType, let version, let count):
            return ["extension_type": extensionType, "version": version, "count": "\(count)"]
        case .scriptletFetchError(let extensionType, _),
             .scriptletValidationError(let extensionType, _),
             .scriptletInstallError(let extensionType, _):
            return ["extension_type": extensionType]
        case .scriptletInstalled(let extensionType, let version):
            return ["extension_type": extensionType, "version": version]
        case .dailyAdBlockingState(let isEnabled, let analyticsEnabled):
            return [
                "is_enabled": isEnabled ? "true" : "false",
                "analytics_enabled": analyticsEnabled ? "true" : "false"
            ]
        case .adBlockingDetectedAdBlocker(let loginState),
             .adBlockingDetectedPlayabilityError(let loginState),
             .adBlockingDetectedVideoAd(let loginState),
             .adBlockingDetectedStaticAd(let loginState),
             .adBlockingDetectedBuffering(let loginState):
            return ["loginState": loginState]
        default:
            return nil
        }
    }

    var standardParameters: [PixelKitStandardParameter]? {
        return [.pixelSource]
    }

    /// Maps a C-S-S `webEvent` `type` string to the matching pixel case.
    /// Returns `nil` for unknown types so the caller can no-op.
    static func adBlockingDetectedEvent(type: String, loginState: String) -> WebExtensionPixel? {
        switch type {
        case "youtube_adBlocker": return .adBlockingDetectedAdBlocker(loginState: loginState)
        case "youtube_playabilityError": return .adBlockingDetectedPlayabilityError(loginState: loginState)
        case "youtube_videoAd": return .adBlockingDetectedVideoAd(loginState: loginState)
        case "youtube_staticAd": return .adBlockingDetectedStaticAd(loginState: loginState)
        case "youtube_buffering": return .adBlockingDetectedBuffering(loginState: loginState)
        default: return nil
        }
    }
}

@available(macOS 15.4, *)
private extension DuckDuckGoWebExtensionType {

    var installedPixel: WebExtensionPixel? {
        switch self {
        case .embedded: return .embeddedInstalled
        case .darkReader: return .darkReaderInstalled
        case .adBlockingExtension: return .adBlockingExtensionInstalled
        }
    }

    func upgradedPixel(fromVersion: String?, toVersion: String?) -> WebExtensionPixel? {
        switch self {
        case .embedded: return .embeddedUpgraded(fromVersion: fromVersion, toVersion: toVersion)
        case .darkReader: return .darkReaderUpgraded(fromVersion: fromVersion, toVersion: toVersion)
        case .adBlockingExtension: return .adBlockingExtensionUpgraded(fromVersion: fromVersion, toVersion: toVersion)
        }
    }

    func installErrorPixel(error: Error) -> WebExtensionPixel? {
        switch self {
        case .embedded: return .embeddedInstallError(error: error)
        case .darkReader: return .darkReaderInstallError(error: error)
        case .adBlockingExtension: return .adBlockingExtensionInstallError(error: error)
        }
    }
}

// MARK: - WebExtensionPixelFiring Implementation

@available(macOS 15.4, *)
struct MacOSWebExtensionPixelFiring: WebExtensionPixelFiring {

    func fire(_ event: WebExtensionPixelEvent) {
        let pixel: WebExtensionPixel
        switch event {
        case .installed:
            pixel = .installed
        case .installError(let error):
            pixel = .installError(error: error)
        case .uninstalled:
            pixel = .uninstalled
        case .uninstallError(let error):
            pixel = .uninstallError(error: error)
        case .uninstalledAll:
            pixel = .uninstalledAll
        case .uninstallAllError(let error):
            pixel = .uninstallAllError(error: error)
        case .loaded:
            pixel = .loaded
        case .loadError(let error):
            pixel = .loadError(error: error)
        case .embeddedInstalled(let type):
            guard let macPixel = type.installedPixel else { return }
            pixel = macPixel
        case .embeddedUpgraded(let type, let fromVersion, let toVersion):
            guard let macPixel = type.upgradedPixel(fromVersion: fromVersion, toVersion: toVersion) else { return }
            pixel = macPixel
        case .embeddedInstallError(let type, let error):
            guard let macPixel = type.installErrorPixel(error: error) else { return }
            pixel = macPixel
        case .scriptletFetchSuccess(let type, let version, let count):
            pixel = .scriptletFetchSuccess(extensionType: type.rawValue, version: version, count: count)
        case .scriptletFetchError(let type, let error):
            pixel = .scriptletFetchError(extensionType: type.rawValue, error: error)
        case .scriptletValidationError(let type, let error):
            pixel = .scriptletValidationError(extensionType: type.rawValue, error: error)
        case .scriptletInstalled(let type, let version):
            pixel = .scriptletInstalled(extensionType: type.rawValue, version: version)
        case .scriptletInstallError(let type, let error):
            pixel = .scriptletInstallError(extensionType: type.rawValue, error: error)
        }
        PixelKit.fire(pixel, frequency: .dailyAndStandard)
    }
}

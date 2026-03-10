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
        }
    }

    var parameters: [String: String]? {
        switch self {
        case .embeddedUpgraded(let fromVersion, let toVersion),
             .darkReaderUpgraded(let fromVersion, let toVersion):
            var params: [String: String] = [:]
            if let fromVersion {
                params["from_version"] = fromVersion
            }
            if let toVersion {
                params["to_version"] = toVersion
            }
            return params.isEmpty ? nil : params
        default:
            return nil
        }
    }

    var standardParameters: [PixelKitStandardParameter]? {
        return [.pixelSource]
    }
}

@available(macOS 15.4, *)
private extension DuckDuckGoWebExtensionType {

    var installedPixel: WebExtensionPixel? {
        switch self {
        case .embedded: return .embeddedInstalled
        case .darkReader: return .darkReaderInstalled
        }
    }

    func upgradedPixel(fromVersion: String?, toVersion: String?) -> WebExtensionPixel? {
        switch self {
        case .embedded: return .embeddedUpgraded(fromVersion: fromVersion, toVersion: toVersion)
        case .darkReader: return .darkReaderUpgraded(fromVersion: fromVersion, toVersion: toVersion)
        }
    }

    func installErrorPixel(error: Error) -> WebExtensionPixel? {
        switch self {
        case .embedded: return .embeddedInstallError(error: error)
        case .darkReader: return .darkReaderInstallError(error: error)
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
        }
        PixelKit.fire(pixel, frequency: .dailyAndStandard)
    }
}

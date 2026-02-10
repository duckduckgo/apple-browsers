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
        }
    }

    var parameters: [String: String]? {
        return nil
    }

    var standardParameters: [PixelKitStandardParameter]? {
        return [.pixelSource]
    }
}

// MARK: - WebExtensionPixelFiring Implementation

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
        }
        PixelKit.fire(pixel, frequency: .dailyAndStandard)
    }
}

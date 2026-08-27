//
//  WebExtensionPixelFiring+iOS.swift
//  DuckDuckGo
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

import Foundation
import Core
import WebExtensions
import PixelKit

@available(iOS 18.4, *)
private extension DuckDuckGoWebExtensionType {

    var installedPixel: Pixel.Event {
        switch self {
        case .embedded: return .webExtensionEmbeddedInstalled
        case .darkReader: return .webExtensionDarkReaderInstalled
        case .adBlockingExtension: return .webExtensionAdBlockingInstalled
        }
    }

    var upgradedPixel: Pixel.Event {
        switch self {
        case .embedded: return .webExtensionEmbeddedUpgraded
        case .darkReader: return .webExtensionDarkReaderUpgraded
        case .adBlockingExtension: return .webExtensionAdBlockingUpgraded
        }
    }

    var installErrorPixel: Pixel.Event {
        switch self {
        case .embedded: return .webExtensionEmbeddedInstallError
        case .darkReader: return .webExtensionDarkReaderInstallError
        case .adBlockingExtension: return .webExtensionAdBlockingInstallError
        }
    }

    var notLoadedPixel: Pixel.Event {
        switch self {
        case .embedded: return .webExtensionEmbeddedNotLoaded
        case .darkReader: return .webExtensionDarkReaderNotLoaded
        case .adBlockingExtension: return .webExtensionAdBlockingNotLoaded
        }
    }
}

@available(iOS 18.4, *)
struct iOSWebExtensionPixelFiring: WebExtensionPixelFiring {

    func fire(_ event: WebExtensionPixelEvent) {
        switch event {
        case .installed:
            PixelKit.fire(Pixel.Event.webExtensionInstalled,
                          frequency: .dailyAndStandard)
        case .installError(let error):
            PixelKit.fire(Pixel.Event.webExtensionInstallError.withError(error),
                          frequency: .dailyAndStandard)
        case .uninstalled:
            PixelKit.fire(Pixel.Event.webExtensionUninstalled,
                          frequency: .dailyAndStandard)
        case .uninstallError(let error):
            PixelKit.fire(Pixel.Event.webExtensionUninstallError.withError(error),
                          frequency: .dailyAndStandard)
        case .uninstalledAll:
            PixelKit.fire(Pixel.Event.webExtensionUninstalledAll,
                          frequency: .dailyAndStandard)
        case .uninstallAllError(let error):
            PixelKit.fire(Pixel.Event.webExtensionUninstallAllError.withError(error),
                          frequency: .dailyAndStandard)
        case .loaded:
            PixelKit.fire(Pixel.Event.webExtensionLoaded,
                          frequency: .dailyAndStandard)
        case .loadError(let error):
            PixelKit.fire(Pixel.Event.webExtensionLoadError.withError(error),
                          frequency: .dailyAndStandard)
        case .embeddedInstalled(let type):
            PixelKit.fire(type.installedPixel,
                          frequency: .dailyAndStandard)
        case .embeddedUpgraded(let type, let fromVersion, let toVersion):
            var params: [String: String] = [:]
            if let fromVersion {
                params["from_version"] = fromVersion
            }
            if let toVersion {
                params["to_version"] = toVersion
            }
            PixelKit.fire(type.upgradedPixel,
                          frequency: .dailyAndStandard,
                          options: .parameters(params))
        case .embeddedInstallError(let type, let error):
            PixelKit.fire(type.installErrorPixel.withError(error),
                          frequency: .dailyAndStandard)
        case .scriptletFetchSuccess(let type, let version, let count):
            PixelKit.fire(Pixel.Event.webExtensionScriptletFetchSuccess,
                          frequency: .dailyAndStandard,
                          options: .parameters(["extension_type": type.rawValue, "version": version, "count": "\(count)"]))
        case .scriptletFetchError(let type, let error):
            PixelKit.fire(Pixel.Event.webExtensionScriptletFetchError.withError(error),
                          frequency: .dailyAndStandard,
                          options: .parameters(["extension_type": type.rawValue]))
        case .scriptletValidationError(let type, let error):
            PixelKit.fire(Pixel.Event.webExtensionScriptletValidationError.withError(error),
                          frequency: .dailyAndStandard,
                          options: .parameters(["extension_type": type.rawValue]))
        case .scriptletInstalled(let type, let version):
            PixelKit.fire(Pixel.Event.webExtensionScriptletInstalled,
                          frequency: .dailyAndStandard,
                          options: .parameters(["extension_type": type.rawValue, "version": version]))
        case .scriptletInstallError(let type, let error):
            PixelKit.fire(Pixel.Event.webExtensionScriptletInstallError.withError(error),
                          frequency: .dailyAndStandard,
                          options: .parameters(["extension_type": type.rawValue]))
        case .stateChecked:
            PixelKit.fire(Pixel.Event.webExtensionStateChecked,
                          frequency: .dailyAndStandard)
        case .expectedExtensionNotLoaded(let type):
            PixelKit.fire(type.notLoadedPixel,
                          frequency: .dailyAndStandard)
        case .adBlockingScriptletsNotFetched(let extensionLoaded):
            PixelKit.fire(Pixel.Event.webExtensionAdBlockingScriptletsNotFetched,
                          frequency: .dailyAndStandard,
                          options: .parameters(["extension_loaded": extensionLoaded ? "true" : "false"]))
        }
    }
}

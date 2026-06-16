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
            DailyPixel.fireDailyAndCount(
                pixel: .webExtensionInstalled,
                pixelNameSuffixes: DailyPixel.Constant.dailyAndStandardSuffixes
            )
        case .installError(let error):
            DailyPixel.fireDailyAndCount(
                pixel: .webExtensionInstallError,
                pixelNameSuffixes: DailyPixel.Constant.dailyAndStandardSuffixes,
                error: error
            )
        case .uninstalled:
            DailyPixel.fireDailyAndCount(
                pixel: .webExtensionUninstalled,
                pixelNameSuffixes: DailyPixel.Constant.dailyAndStandardSuffixes
            )
        case .uninstallError(let error):
            DailyPixel.fireDailyAndCount(
                pixel: .webExtensionUninstallError,
                pixelNameSuffixes: DailyPixel.Constant.dailyAndStandardSuffixes,
                error: error
            )
        case .uninstalledAll:
            DailyPixel.fireDailyAndCount(
                pixel: .webExtensionUninstalledAll,
                pixelNameSuffixes: DailyPixel.Constant.dailyAndStandardSuffixes
            )
        case .uninstallAllError(let error):
            DailyPixel.fireDailyAndCount(
                pixel: .webExtensionUninstallAllError,
                pixelNameSuffixes: DailyPixel.Constant.dailyAndStandardSuffixes,
                error: error
            )
        case .loaded:
            DailyPixel.fireDailyAndCount(
                pixel: .webExtensionLoaded,
                pixelNameSuffixes: DailyPixel.Constant.dailyAndStandardSuffixes
            )
        case .loadError(let error):
            DailyPixel.fireDailyAndCount(
                pixel: .webExtensionLoadError,
                pixelNameSuffixes: DailyPixel.Constant.dailyAndStandardSuffixes,
                error: error
            )
        case .embeddedInstalled(let type):
            DailyPixel.fireDailyAndCount(
                pixel: type.installedPixel,
                pixelNameSuffixes: DailyPixel.Constant.dailyAndStandardSuffixes
            )
        case .embeddedUpgraded(let type, let fromVersion, let toVersion):
            var params: [String: String] = [:]
            if let fromVersion {
                params["from_version"] = fromVersion
            }
            if let toVersion {
                params["to_version"] = toVersion
            }
            DailyPixel.fireDailyAndCount(
                pixel: type.upgradedPixel,
                pixelNameSuffixes: DailyPixel.Constant.dailyAndStandardSuffixes,
                withAdditionalParameters: params
            )
        case .embeddedInstallError(let type, let error):
            DailyPixel.fireDailyAndCount(
                pixel: type.installErrorPixel,
                pixelNameSuffixes: DailyPixel.Constant.dailyAndStandardSuffixes,
                error: error
            )
        case .scriptletFetchSuccess(let type, let version, let count):
            DailyPixel.fireDailyAndCount(
                pixel: .webExtensionScriptletFetchSuccess,
                pixelNameSuffixes: DailyPixel.Constant.dailyAndStandardSuffixes,
                withAdditionalParameters: ["extension_type": type.rawValue, "version": version, "count": "\(count)"]
            )
        case .scriptletFetchError(let type, let error):
            DailyPixel.fireDailyAndCount(
                pixel: .webExtensionScriptletFetchError,
                pixelNameSuffixes: DailyPixel.Constant.dailyAndStandardSuffixes,
                error: error,
                withAdditionalParameters: ["extension_type": type.rawValue]
            )
        case .scriptletValidationError(let type, let error):
            DailyPixel.fireDailyAndCount(
                pixel: .webExtensionScriptletValidationError,
                pixelNameSuffixes: DailyPixel.Constant.dailyAndStandardSuffixes,
                error: error,
                withAdditionalParameters: ["extension_type": type.rawValue]
            )
        case .scriptletInstalled(let type, let version):
            DailyPixel.fireDailyAndCount(
                pixel: .webExtensionScriptletInstalled,
                pixelNameSuffixes: DailyPixel.Constant.dailyAndStandardSuffixes,
                withAdditionalParameters: ["extension_type": type.rawValue, "version": version]
            )
        case .scriptletInstallError(let type, let error):
            DailyPixel.fireDailyAndCount(
                pixel: .webExtensionScriptletInstallError,
                pixelNameSuffixes: DailyPixel.Constant.dailyAndStandardSuffixes,
                error: error,
                withAdditionalParameters: ["extension_type": type.rawValue]
            )
        case .stateChecked:
            DailyPixel.fireDailyAndCount(
                pixel: .webExtensionStateChecked,
                pixelNameSuffixes: DailyPixel.Constant.dailyAndStandardSuffixes
            )
        case .expectedExtensionNotLoaded(let type):
            DailyPixel.fireDailyAndCount(
                pixel: type.notLoadedPixel,
                pixelNameSuffixes: DailyPixel.Constant.dailyAndStandardSuffixes
            )
        case .adBlockingScriptletsNotFetched(let extensionLoaded):
            DailyPixel.fireDailyAndCount(
                pixel: .webExtensionAdBlockingScriptletsNotFetched,
                pixelNameSuffixes: DailyPixel.Constant.dailyAndStandardSuffixes,
                withAdditionalParameters: ["extension_loaded": extensionLoaded ? "true" : "false"]
            )
        }
    }
}

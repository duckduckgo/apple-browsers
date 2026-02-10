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
        }
    }
}

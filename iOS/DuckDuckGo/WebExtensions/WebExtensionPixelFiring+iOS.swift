//
//  WebExtensionPixelFiring+iOS.swift
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

import Foundation
import Core
import WebExtensions

struct iOSWebExtensionPixelFiring: WebExtensionPixelFiring {

    func fire(_ event: WebExtensionPixelEvent) {
        switch event {
        case .installed:
            Pixel.fire(pixel: .webExtensionInstalled)
            Pixel.fire(pixel: .webExtensionInstalledDaily)
        case .installError(let error):
            Pixel.fire(pixel: .webExtensionInstallError, error: error)
            Pixel.fire(pixel: .webExtensionInstallErrorDaily, error: error)
        case .uninstalled:
            Pixel.fire(pixel: .webExtensionUninstalled)
            Pixel.fire(pixel: .webExtensionUninstalledDaily)
        case .uninstallError(let error):
            Pixel.fire(pixel: .webExtensionUninstallError, error: error)
            Pixel.fire(pixel: .webExtensionUninstallErrorDaily, error: error)
        case .uninstalledAll:
            Pixel.fire(pixel: .webExtensionUninstalledAll)
            Pixel.fire(pixel: .webExtensionUninstalledAllDaily)
        case .uninstallAllError(let error):
            Pixel.fire(pixel: .webExtensionUninstallAllError, error: error)
            Pixel.fire(pixel: .webExtensionUninstallAllErrorDaily, error: error)
        case .loaded:
            Pixel.fire(pixel: .webExtensionLoaded)
            Pixel.fire(pixel: .webExtensionLoadedDaily)
        case .loadError(let error):
            Pixel.fire(pixel: .webExtensionLoadError, error: error)
            Pixel.fire(pixel: .webExtensionLoadErrorDaily, error: error)
        }
    }
}

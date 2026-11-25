//
//  OtherDistributionInstalledPixel.swift
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

import AppKit
import Common
import PixelKit

/// Reports whether the other distribution of the browser (DMG or App Store) is installed in `/Applications`.
///
/// With both installed, an App Store update can replace the DMG app, so this sizes how many users are exposed.
/// See the definition in `daily_pixels.json5`.
enum OtherDistributionInstalledPixel: PixelKit.Event {
    case daily(installed: Bool)

    var namePrefix: PixelKitNamePrefix { .none }

    var name: String { "other_distribution_installed_macos" }

    var parameters: [String: String]? {
        switch self {
        case .daily(let installed):
            return ["installed": String(installed)]
        }
    }

    var standardParameters: [PixelKitStandardParameter]? { [.pixelSource] }
}

struct OtherDistributionInstalledPixelReporter {
    static let dmgBundleIdentifier = "com.duckduckgo.macos.browser"
    static let appStoreBundleIdentifier = "com.duckduckgo.mobile.ios"
    /// Debug, Review and Alpha builds append these to the bundle ID (see `DeveloperID.xcconfig` and `AppStore.xcconfig`).
    static let bundleIdentifierSuffixes = ["", ".debug", ".review", ".alpha"]

    private let isAppStoreBuild: Bool
    private let applicationURLs: (_ bundleIdentifier: String) -> [URL]
    private let pixelFiring: PixelFiring?

    init(isAppStoreBuild: Bool = AppVersion.isAppStoreBuild,
         applicationURLs: @escaping (_ bundleIdentifier: String) -> [URL] = { NSWorkspace.shared.urlsForApplications(withBundleIdentifier: $0) },
         pixelFiring: PixelFiring? = PixelKit.shared) {
        self.isAppStoreBuild = isAppStoreBuild
        self.applicationURLs = applicationURLs
        self.pixelFiring = pixelFiring
    }

    func fireDailyPixel() {
        let otherBundleIdentifier = isAppStoreBuild ? Self.dmgBundleIdentifier : Self.appStoreBundleIdentifier
        let isInstalled = Self.bundleIdentifierSuffixes.contains { suffix in
            applicationURLs(otherBundleIdentifier + suffix).contains {
                $0.deletingLastPathComponent().standardizedFileURL.path == "/Applications"
            }
        }
        pixelFiring?.fire(OtherDistributionInstalledPixel.daily(installed: isInstalled), frequency: .daily)
    }
}

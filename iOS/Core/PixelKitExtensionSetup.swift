//
//  PixelKitExtensionSetup.swift
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

import Common
import Foundation
import Networking
import Persistence
import PixelKit
import UIKit

/// Configures PixelKit inside an app extension.
///
/// Extensions run in their own processes, so each has to call this before firing anything:
/// `PixelKit.fire` silently no-ops when `PixelKit.shared` is nil.
public enum PixelKitExtensionSetup {

    /// - Parameters:
    ///   - session: a stable identifier unique to this process, keying its retry queue's storage and
    ///     throttle so two processes never share or overwrite one queue. Must differ from
    ///     `"ios-browser"` and `"ios-vpn-tunnel"`.
    ///   - defaults: where PixelKit keeps its throttling state. Use a store the extension can
    ///     actually write, which normally means its app group's defaults.
    public static func setUp(session: String, defaults: ThrowingKeyValueStoring) {
        let isTablet = UIDevice.current.userInterfaceIdiom == .pad
        PixelKit.setUp(dryRun: PixelKitConfig.isDryRun(isProductionBuild: BuildFlags.isProductionBuild),
                       appVersion: AppVersion.shared.versionNumber,
                       source: (isTablet ? PixelKit.Source.iPadOS : PixelKit.Source.iOS).rawValue,
                       session: session,
                       defaultHeaders: [:],
                       defaults: defaults) { pixelName, headers, parameters, _, _, onComplete in
            let url = URL.pixelUrl(forPixelNamed: pixelName)
            let apiHeaders = APIRequestV2.HeadersV2(userAgent: PixelUserAgent.default,
                                                   additionalHeaders: headers)
            guard let request = APIRequestV2(url: url,
                                            method: .get,
                                            queryItems: parameters.toQueryItems(),
                                            headers: apiHeaders) else {
                onComplete(false, nil)
                return
            }
            Task {
                do {
                    _ = try await DefaultAPIService().fetch(request: request)
                    onComplete(true, nil)
                } catch {
                    onComplete(false, error)
                }
            }
        }

        // Each process has its own copy of these suites; `UserDefaults(suiteName:)` does not share
        // them across processes. Without this migration, an already-throttled pixel in this
        // process fires once more on the release that moves it to PixelKit.
        LegacyPixelStateMigration(
            destination: defaults,
            dailyStore: UserDefaultsLegacyPixelStore(suiteName: LegacyPixelStateMigration.LegacySuiteName.daily),
            uniqueStore: UserDefaultsLegacyPixelStore(suiteName: LegacyPixelStateMigration.LegacySuiteName.unique),
            debounceStore: UserDefaultsLegacyPixelStore(suiteName: LegacyPixelStateMigration.LegacySuiteName.debounce),
            completionFlagStore: defaults
        ).run()
    }
}

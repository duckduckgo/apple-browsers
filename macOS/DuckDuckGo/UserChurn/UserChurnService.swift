//
//  UserChurnService.swift
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
import os.log
import Persistence
import PixelKit
import Common

final class UserChurnService {

    private enum Key: String {
        case wasDefaultBrowser = "user-churn.was-default-browser"
    }

    private let defaultBrowserProvider: DefaultBrowserProvider
    private let keyValueStore: ThrowingKeyValueStoring
    private let pixelFiring: PixelFiring?
    private let atbProvider: () -> String?
    private let bundleIdentifierProvider: (URL) -> String?

    private var wasDefaultBrowser: Bool? {
        get {
            do {
                return try keyValueStore.object(forKey: Key.wasDefaultBrowser.rawValue) as? Bool
            } catch {
                Logger.general.error("Failed to read wasDefaultBrowser from keyValueStore: \(error)")
                return nil
            }
        }
        set {
            do {
                try keyValueStore.set(newValue, forKey: Key.wasDefaultBrowser.rawValue)
            } catch {
                Logger.general.error("Failed to write wasDefaultBrowser to keyValueStore: \(error)")
            }
        }
    }

    init(
        defaultBrowserProvider: DefaultBrowserProvider,
        keyValueStore: ThrowingKeyValueStoring,
        pixelFiring: PixelFiring?,
        atbProvider: @escaping () -> String?,
        bundleIdentifierProvider: @escaping (URL) -> String? = { Bundle(url: $0)?.bundleIdentifier }
    ) {
        self.defaultBrowserProvider = defaultBrowserProvider
        self.keyValueStore = keyValueStore
        self.pixelFiring = pixelFiring
        self.atbProvider = atbProvider
        self.bundleIdentifierProvider = bundleIdentifierProvider
    }

    /// Checks if the user has changed the default browser away from DuckDuckGo and fires a pixel if so.
    ///
    /// Logic:
    /// 1. Check if any DuckDuckGo build is currently the default browser
    /// 2. If the stored state is not initialized, initialize it and exit early
    /// 3. If any DuckDuckGo build is currently the default, update stored state if needed and return (no churn)
    /// 4. If no DuckDuckGo build is the default and one was previously, fire the churn pixel
    /// 5. Update the stored state if needed
    func checkForDefaultBrowserChange() {
        let defaultBrowserURL = defaultBrowserProvider.defaultBrowserURL
        let isAnyDuckDuckGoBuildDefault = isDuckDuckGoBuild(url: defaultBrowserURL)

        guard let wasDefault = wasDefaultBrowser else {
            wasDefaultBrowser = isAnyDuckDuckGoBuildDefault
            return
        }

        // Only update stored state if it changed
        if isAnyDuckDuckGoBuildDefault != wasDefault {
            wasDefaultBrowser = isAnyDuckDuckGoBuildDefault
        }

        // Fire churn pixel only if no DDG build is default AND one was previously
        guard !isAnyDuckDuckGoBuildDefault, wasDefault else {
            return
        }

        let bundleId = defaultBrowserURL.flatMap { bundleIdentifierProvider($0) }
        pixelFiring?.fire(UserChurnPixel.unsetAsDefault(
            newDefaultBrowserBundleId: bundleId,
            atb: atbProvider()
        ))
    }

    /// Returns true if the app at the given URL is a DuckDuckGo build.
    ///
    /// All DuckDuckGo builds share the `com.duckduckgo` bundle identifier prefix.
    private func isDuckDuckGoBuild(url: URL?) -> Bool {
        guard let url,
              let bundleIdentifier = bundleIdentifierProvider(url) else {
            return false
        }
        return bundleIdentifier.hasPrefix("com.duckduckgo")
    }
}

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
        atbProvider: @escaping () -> String?
    ) {
        self.defaultBrowserProvider = defaultBrowserProvider
        self.keyValueStore = keyValueStore
        self.pixelFiring = pixelFiring
        self.atbProvider = atbProvider
    }

    /// Checks if the user has changed the default browser away from DuckDuckGo and fires a pixel if so.
    ///
    /// Logic:
    /// 1. If the stored state is not initialized, initialize it and exit early
    /// 2. If DuckDuckGo is currently the default, update stored state if needed and return (no churn)
    /// 3. If DuckDuckGo is not the default and it was previously, fire the churn pixel
    /// 4. Update the stored state if needed
    func checkForDefaultBrowserChange() {
        let isDefault = defaultBrowserProvider.isDefault
        guard let wasDefault = wasDefaultBrowser else {
            wasDefaultBrowser = isDefault
            return
        }

        // Only update stored state if it changed
        if isDefault != wasDefault {
            wasDefaultBrowser = isDefault
        }

        // If DuckDuckGo is not the default and it was previously the default, fire the churn pixel
        guard !isDefault, wasDefault else {
            return
        }

        pixelFiring?.fire(UserChurnPixel.unsetAsDefault(
            newDefaultBrowserURL: defaultBrowserProvider.defaultBrowserURL,
            atb: atbProvider()
        ))
    }
}

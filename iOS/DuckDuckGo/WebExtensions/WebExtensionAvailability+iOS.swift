//
//  WebExtensionAvailability+iOS.swift
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
import WebKit
import Core
import PrivacyConfig
import WebExtensions

/// Holds a reference to the WebExtensionManager that can be set after initialization.
/// This allows WebExtensionAvailability to be created before the manager exists,
/// with the manager reference populated later during app startup.
final class WebExtensionManagerHolder {
    weak var manager: WebExtensionManaging?
}

/// Determines whether web extensions are available and should be used on iOS.
final class WebExtensionAvailability: WebExtensionAvailabilityProviding {

    private let featureFlagger: FeatureFlagger
    private let webExtensionManagerProvider: () -> WebExtensionManaging?

    init(
        featureFlagger: FeatureFlagger,
        webExtensionManagerProvider: @escaping () -> WebExtensionManaging?
    ) {
        self.featureFlagger = featureFlagger
        self.webExtensionManagerProvider = webExtensionManagerProvider
    }

    var isAvailable: Bool {
        guard #available(iOS 18.4, *) else { return false }
        return featureFlagger.isFeatureOn(.webExtensions)
    }

    var hasInstalledExtensions: Bool {
        guard isAvailable else { return false }

        if #available(iOS 18.4, *) {
            return webExtensionManagerProvider()?.hasInstalledExtensions ?? false
        }
        return false
    }

    var isAutoconsentExtensionAvailable: Bool {
        guard isAvailable else { return false }

        if #available(iOS 18.4, *) {
            guard let manager = webExtensionManagerProvider() else { return false }

            return manager.loadedExtensions.contains { context in
                context.duckDuckGoWebExtensionType == .embedded
            }
        }
        return false
    }
}

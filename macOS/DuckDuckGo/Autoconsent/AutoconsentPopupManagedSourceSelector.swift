//
//  AutoconsentPopupManagedSourceSelector.swift
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
import PrivacyConfig
import WebExtensions

/// Protocol for determining which autoconsent source (user script or web extension) is currently active.
protocol AutoconsentPopupManagedSourceSelecting {
    /// Returns true if the web extension should be used as the autoconsent source,
    /// false if the user script should be used.
    var isWebExtensionActive: Bool { get }
}

/// Default implementation that checks feature flags and web extension availability.
@available(macOS 15.4, *)
final class DefaultAutoconsentPopupManagedSourceSelector: AutoconsentPopupManagedSourceSelecting {

    private let featureFlagger: FeatureFlagger
    private let webExtensionManagerProvider: () -> WebExtensionManager?

    init(
        featureFlagger: FeatureFlagger,
        webExtensionManagerProvider: @escaping () -> WebExtensionManager?
    ) {
        self.featureFlagger = featureFlagger
        self.webExtensionManagerProvider = webExtensionManagerProvider
    }

    var isWebExtensionActive: Bool {
        guard featureFlagger.isFeatureOn(.webExtensions) else {
            return false
        }

        guard let webExtensionManager = webExtensionManagerProvider() else {
            return false
        }

        return webExtensionManager.hasInstalledExtensions
    }
}

/// Fallback implementation for older macOS versions where web extensions are not available.
final class LegacyAutoconsentPopupManagedSourceSelector: AutoconsentPopupManagedSourceSelecting {
    var isWebExtensionActive: Bool { false }
}

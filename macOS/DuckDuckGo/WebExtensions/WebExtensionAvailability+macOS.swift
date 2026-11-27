//
//  WebExtensionAvailability+macOS.swift
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
import PrivacyConfig
import WebExtensions

/// Determines whether web extensions are available and should be used on macOS.
final class WebExtensionAvailability: WebExtensionAvailabilityProviding {

    private let featureFlagger: FeatureFlagger
    private let webExtensionManagerProvider: () -> WebExtensionManaging?
    private let isSurrogateRedirectionOSSupported: Bool

    init(
        featureFlagger: FeatureFlagger,
        isSurrogateRedirectionOSSupported: Bool = { if #available(macOS 26, *) { true } else { false } }(),
        webExtensionManagerProvider: @escaping () -> WebExtensionManaging?
    ) {
        self.featureFlagger = featureFlagger
        self.isSurrogateRedirectionOSSupported = isSurrogateRedirectionOSSupported
        self.webExtensionManagerProvider = webExtensionManagerProvider
    }

    var isAvailable: Bool {
        guard #available(macOS 15.4, *) else { return false }
        return true
    }

    var isAutoconsentExtensionAvailable: Bool {
        guard isAvailable, featureFlagger.isFeatureOn(.embeddedExtension) else { return false }

        if #available(macOS 15.4, *) {
            guard let manager = webExtensionManagerProvider() else { return false }

            return manager.loadedExtensions.contains { context in
                context.duckDuckGoWebExtensionType == .embedded
            }
        }
        return false
    }

    var isExtensionManagementAvailable: Bool {
        isAvailable && (featureFlagger.isFeatureOn(.webExtensions) || featureFlagger.isFeatureOn(.webExtensionsInternal))
    }

    /// macOS 26+, `webExtensions.embeddedExtension` and `trackerProtection.appleSurrogateRedirection`.
    var isAppleSurrogateRedirectionConfigured: Bool {
        isSurrogateRedirectionOSSupported
            && featureFlagger.isFeatureOn(.embeddedExtension)
            && featureFlagger.isFeatureOn(.appleSurrogateRedirection)
    }

    /// `isAppleSurrogateRedirectionConfigured`, and the embedded extension being loaded. Requiring it loaded (not just
    /// flagged on) means C-S-S keeps injecting surrogates if the extension fails to load or is removed.
    var isAppleSurrogateRedirectionEnabled: Bool {
        isAppleSurrogateRedirectionConfigured && isAutoconsentExtensionAvailable
    }
}

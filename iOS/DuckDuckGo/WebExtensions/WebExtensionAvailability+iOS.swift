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

/// Whether this build can run web extensions that talk to the app over native messaging.
///
/// Native messaging from an MV3 service worker only works with the web-browser entitlement, which
/// the Alpha app identifier does not carry. There the extension still installs and loads, but its
/// service worker never delivers a message, so it cannot read the privacy config it needs and
/// silently does nothing - while its presence suppresses the native implementation it replaced.
struct NativeMessagingSupport {

    let isSupported: Bool

    init(isSupported: Bool = Self.isSupportedByBuildConfiguration) {
        self.isSupported = isSupported
    }

    private static var isSupportedByBuildConfiguration: Bool {
#if ALPHA
        return false
#else
        return true
#endif
    }
}

/// Holds a reference to the WebExtensionManager that can be set after initialization.
/// This allows WebExtensionAvailability to be created before the manager exists,
/// with the manager reference populated later during app startup.
final class WebExtensionManagerHolder {
    weak var manager: WebExtensionManaging?
}

/// Determines whether web extensions are available and should be used on iOS.
final class WebExtensionAvailability: WebExtensionAvailabilityProviding {

    private let featureFlagger: FeatureFlagger
    private let nativeMessagingSupport: NativeMessagingSupport
    private let webExtensionManagerProvider: () -> WebExtensionManaging?

    init(
        featureFlagger: FeatureFlagger,
        nativeMessagingSupport: NativeMessagingSupport = NativeMessagingSupport(),
        webExtensionManagerProvider: @escaping () -> WebExtensionManaging?
    ) {
        self.featureFlagger = featureFlagger
        self.nativeMessagingSupport = nativeMessagingSupport
        self.webExtensionManagerProvider = webExtensionManagerProvider
    }

    var isAvailable: Bool {
        guard #available(iOS 18.4, *) else { return false }
        return featureFlagger.isFeatureOn(.webExtensions)
    }

    var isAutoconsentExtensionAvailable: Bool {
        guard isAvailable,
              nativeMessagingSupport.isSupported,
              featureFlagger.isFeatureOn(.embeddedExtension) else { return false }

        if #available(iOS 18.4, *) {
            guard let manager = webExtensionManagerProvider() else { return false }

            return manager.loadedExtensions.contains { context in
                context.duckDuckGoWebExtensionType == .embedded
            }
        }
        return false
    }
}

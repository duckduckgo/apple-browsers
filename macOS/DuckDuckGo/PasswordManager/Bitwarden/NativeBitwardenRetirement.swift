//
//  NativeBitwardenRetirement.swift
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

import Combine
import ConcurrencyExtensions
import Foundation
import WebExtensions

/// Switches a native Bitwarden integration user to DuckDuckGo once they install the Bitwarden extension,
/// which replaces the integration. Web extensions need macOS 15.4, and there the switch is permanent.
@available(macOS 15.4, *)
@MainActor
final class NativeBitwardenRetirement {

    private var persistor: AutofillPreferencesPersistor
    private let notificationCenter: NotificationCenter
    private let isBitwardenExtensionInstalled: () -> Bool
    private let disableNativeIntegration: () -> Void
    private var extensionChangeCancellable: AnyCancellable?

    init(persistor: AutofillPreferencesPersistor = AutofillPreferences(),
         notificationCenter: NotificationCenter = .default,
         isBitwardenExtensionInstalled: @escaping () -> Bool,
         disableNativeIntegration: @escaping () -> Void) {
        self.persistor = persistor
        self.notificationCenter = notificationCenter
        self.isBitwardenExtensionInstalled = isBitwardenExtensionInstalled
        self.disableNativeIntegration = disableNativeIntegration

        extensionChangeCancellable = notificationCenter.publisher(for: .chromeWebStoreExtensionChanged)
            .sink { [weak self] _ in
                MainActor.assumeMainThread {
                    self?.retireIfNeeded()
                }
            }
    }

    func retireIfNeeded() {
        guard persistor.passwordManager == .bitwarden, isBitwardenExtensionInstalled() else { return }

        persistor.passwordManager = .duckduckgo
        disableNativeIntegration()
        notificationCenter.post(name: .autofillUserSettingsDidChange, object: nil)
    }
}

extension WebExtensionManaging {

    @available(macOS 15.4, *)
    var isBitwardenExtensionInstalled: Bool {
        let bitwarden = WebExtensionStoreIdentity(store: .chromeWebStore, id: ChromeWebStoreID.bitwarden.rawValue)
        return webExtensionIdentifiers.contains { installedExtension(identifier: $0)?.storeIdentity == bitwarden }
    }
}

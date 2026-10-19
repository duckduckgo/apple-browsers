//
//  CPMExtensionBaseURLPolicy.swift
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

/// Keeps the CPM origin stable across context reloads without making it predictable across installations.
@available(macOS 15.4, iOS 18.4, *)
@MainActor
final class CPMExtensionBaseURLPolicy {
    private let installationStore: InstalledWebExtensionStoring
    private let isEnabled: @MainActor () -> Bool
    // A first install has not reached the persistent registry when the loader creates its context.
    var pendingInstallations: [String: DuckDuckGoWebExtensionType] = [:]

    init(installationStore: InstalledWebExtensionStoring, isEnabled: @escaping @MainActor () -> Bool) {
        self.installationStore = installationStore
        self.isEnabled = isEnabled
    }

    func baseURL(for identifier: String, webExtension: WKWebExtension) -> URL? {
        guard isEnabled(),
              (pendingInstallations[identifier] ?? installationStore.installedExtension(withUniqueIdentifier: identifier)?.embeddedType) == .embedded,
              webExtension.duckDuckGoWebExtensionType == .embedded,
              let uuid = UUID(uuidString: identifier) else { return nil }

        // Never stabilize a web-observable resource origin, even if a future bundled version adds resources.
        if let resources = webExtension.manifest["web_accessible_resources"] {
            guard let resources = resources as? [Any], resources.isEmpty else { return nil }
        }

        return URL(string: "webkit-extension://\(uuid.uuidString.lowercased())/")
    }
}

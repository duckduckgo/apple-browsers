//
//  NativeMessagingAlertSuppressionStore.swift
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

/// Remembers, for this app session only, the extensions whose native messaging alert the user asked not to see again.
@MainActor
protocol NativeMessagingAlertSuppressionStoreProtocol: AnyObject {
    func isSuppressed(for extensionIdentifier: String) -> Bool
    func suppress(for extensionIdentifier: String)
}

@MainActor
final class NativeMessagingAlertSuppressionStore: NativeMessagingAlertSuppressionStoreProtocol {
    private var suppressedExtensionIdentifiers: Set<String> = []

    nonisolated init() {}

    func isSuppressed(for extensionIdentifier: String) -> Bool {
        suppressedExtensionIdentifiers.contains(extensionIdentifier)
    }

    func suppress(for extensionIdentifier: String) {
        suppressedExtensionIdentifiers.insert(extensionIdentifier)
    }
}

//
//  DuckAiUserDefaultModelStore.swift
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
import Foundation

/// The user's "Default AI Model" setting from Duck.ai settings.
public protocol AIChatUserDefaultModelProviding {
    /// `nil` when the user hasn't set one.
    var modelId: String? { get }
    /// Emits after the setting changes.
    var changes: AnyPublisher<Void, Never> { get }
}

/// Reads the setting web keeps in Duck.ai native storage as a JSON-encoded model id.
public struct DuckAiUserDefaultModelStore: AIChatUserDefaultModelProviding {

    private static let entryKey = DuckAiNativeStorageReservedEntryKeys.defaultDuckaiModel

    private let storage: DuckAiNativeStorageHandling

    public init(storage: DuckAiNativeStorageHandling) {
        self.storage = storage
    }

    /// Read from storage each time, so a default changed on the settings page applies to the next new chat.
    public var modelId: String? {
        Self.modelId(fromEntryValue: try? storage.getEntry(key: Self.entryKey.rawValue))
    }

    public var changes: AnyPublisher<Void, Never> {
        guard let observing = storage as? DuckAiNativeEntriesObserving else { return Empty().eraseToAnyPublisher() }
        return observing.reservedEntryUpdatesPublisher
            .filter { $0 == Self.entryKey }
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    /// `nil` unless the value is a JSON-encoded, non-empty string.
    static func modelId(fromEntryValue value: Any?) -> String? {
        guard let json = value as? String, let data = json.data(using: .utf8),
              let modelId = (try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)) as? String,
              !modelId.isEmpty else { return nil }
        return modelId
    }
}

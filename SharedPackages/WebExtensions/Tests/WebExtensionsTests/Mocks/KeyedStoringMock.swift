//
//  KeyedStoringMock.swift
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
import Persistence
@testable import WebExtensions

@available(macOS 15.4, *)
final class KeyedStoringMock: KeyedStoring {
    typealias Keys = WebExtensionPathsSettings

    private static let pathsStorageKey = WebExtensionStorageKeys.storedPaths.rawValue
    private var storage: [String: Any] = [:]

    var paths: [String]? {
        get { storage[Self.pathsStorageKey] as? [String] }
        set { storage[Self.pathsStorageKey] = newValue }
    }

    subscript<Value>(dynamicMember keyPath: KeyPath<Keys, StorageKey<Value>>) -> Value? {
        get {
            // For WebExtensionPathsSettings, we only have one key: paths
            return storage[Self.pathsStorageKey] as? Value
        }
        set {
            storage[Self.pathsStorageKey] = newValue
        }
    }

    func value<Value>(for keyPath: KeyPath<Keys, StorageKey<Value>>) -> Value? {
        return storage[Self.pathsStorageKey] as? Value
    }

    func removeValue<Value>(for keyPath: KeyPath<Keys, StorageKey<Value>>) {
        storage.removeValue(forKey: Self.pathsStorageKey)
    }
}

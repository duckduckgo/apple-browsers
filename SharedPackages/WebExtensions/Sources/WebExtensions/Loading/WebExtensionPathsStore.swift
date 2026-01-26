//
//  WebExtensionPathsStore.swift
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

@available(macOS 15.4, *)
public protocol WebExtensionPathsStoring: AnyObject {
    var paths: [String] { get }
    func add(_ url: String)
    func remove(_ url: String)
}

@available(macOS 15.4, *)
public struct WebExtensionPathsSettings: StoringKeys {
    let paths = StorageKey<[String]>(WebExtensionStorageKeys.storedPaths, assertionHandler: { _ in })

    public init() {}
}

@available(macOS 15.4, *)
public final class WebExtensionPathsStore: WebExtensionPathsStoring {

    private let storage: any KeyedStoring<WebExtensionPathsSettings>

    public var paths: [String] {
        storage.paths ?? []
    }

    public init(storage: (any KeyedStoring<WebExtensionPathsSettings>)? = nil) {
        self.storage = if let storage { storage } else { UserDefaults.standard.keyedStoring() }
    }

    public func add(_ url: String) {
        guard !paths.contains(url) else {
            assertionFailure("Cannot add path as it is already stored: \(url)")
            return
        }

        var currentPaths = paths
        currentPaths.append(url)
        storage.paths = currentPaths
    }

    public func remove(_ url: String) {
        guard paths.contains(url) else {
            assertionFailure("Cannot remove path as it is already absent: \(url)")
            return
        }

        var currentPaths = paths
        currentPaths.removeAll(where: { $0 == url })
        storage.paths = currentPaths
    }
}

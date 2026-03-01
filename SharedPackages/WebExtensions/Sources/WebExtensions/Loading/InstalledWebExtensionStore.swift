//
//  InstalledWebExtensionStore.swift
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

@available(macOS 15.4, iOS 18.4, *)
public protocol InstalledWebExtensionStoring: AnyObject {
    var installedExtensions: [InstalledWebExtension] { get }
    func add(_ extension: InstalledWebExtension)
    func remove(uniqueIdentifier: String)
    func installedExtension(withUniqueIdentifier uniqueIdentifier: String) -> InstalledWebExtension?
}

@available(macOS 15.4, iOS 18.4, *)
public struct InstalledWebExtensionSettings: StoringKeys {
    let extensions = StorageKey<[InstalledWebExtension]>(WebExtensionStorageKeys.installedExtensions, assertionHandler: { _ in })

    public init() {}
}

@available(macOS 15.4, iOS 18.4, *)
public final class InstalledWebExtensionStore: InstalledWebExtensionStoring {

    private let storage: any KeyedStoring<InstalledWebExtensionSettings>

    public var installedExtensions: [InstalledWebExtension] {
        storage.extensions ?? []
    }

    public init(storage: (any KeyedStoring<InstalledWebExtensionSettings>)? = nil) {
        self.storage = if let storage { storage } else { UserDefaults.standard.keyedStoring() }
    }

    public func add(_ extension: InstalledWebExtension) {
        let identifiers = installedExtensions.map(\.uniqueIdentifier)
        guard !identifiers.contains(`extension`.uniqueIdentifier) else {
            assertionFailure("Extension already installed: \(`extension`.uniqueIdentifier)")
            return
        }

        var current = installedExtensions
        current.append(`extension`)
        storage.extensions = current
    }

    public func remove(uniqueIdentifier: String) {
        let identifiers = installedExtensions.map(\.uniqueIdentifier)
        guard identifiers.contains(uniqueIdentifier) else {
            assertionFailure("Extension not found: \(uniqueIdentifier)")
            return
        }

        var current = installedExtensions
        current.removeAll { $0.uniqueIdentifier == uniqueIdentifier }
        storage.extensions = current
    }

    public func installedExtension(withUniqueIdentifier uniqueIdentifier: String) -> InstalledWebExtension? {
        installedExtensions.first { $0.uniqueIdentifier == uniqueIdentifier }
    }
}

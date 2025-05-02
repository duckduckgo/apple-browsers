//
//  ExtensionConfiguration.swift
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

enum ExtensionVariant {
    case both(appexBundleID: String, sysexBundleID: String)
    case sysex(sysexBundleID: String)
}

protocol ExtensionConfigurationStore {
    var isUsingSystemExtension: Bool { get set }
}

final class UserDefaultsExtensionConfigurationStore {
    private let usingSystemExtensionKey: String
    private let userDefaults: UserDefaults

    init(extensionID: String, userDefaults: UserDefaults) {
        usingSystemExtensionKey = "ExtensionConfiguration_\(extensionID)_isUsingSystemExtension"
        self.userDefaults = userDefaults
    }

    var isUsingSystemExtension: Bool {
        get {
            userDefaults.bool(forKey: usingSystemExtensionKey)
        } set {
            userDefaults.set(newValue, forKey: usingSystemExtensionKey)
        }
    }
}

protocol ExtensionConfiguration {
    var isUsingSystemExtension: Bool { get }
}

/// Extension configuration updater
///
final class ExtensionConfigurationUpdater: ExtensionConfiguration {

    private let availableExtensionVariants: ExtensionVariant
    private var store: ExtensionConfigurationStore
    private let updateIsUsingSystemExtension: () -> Bool

    init(extensionID: String,
         availableExtensionVariants: ExtensionVariant,
         store: ExtensionConfigurationStore,
         updateIsUsingSystemExtension: @escaping () -> Bool) {

        self.availableExtensionVariants = availableExtensionVariants
        self.store = store
        self.updateIsUsingSystemExtension = updateIsUsingSystemExtension
    }

    var isUsingSystemExtension: Bool {
        switch availableExtensionVariants {
        case .both:
            let isUsingSystemExtension = updateIsUsingSystemExtension()
            store.isUsingSystemExtension = isUsingSystemExtension
            return isUsingSystemExtension
        case .sysex:
            store.isUsingSystemExtension = true
            return true
        }
    }
}

/// Extension configuration reader
///
final class ExtensionConfigurationReader: ExtensionConfiguration {

    private let availableExtensionVariants: ExtensionVariant
    private var store: ExtensionConfigurationStore
    private let updateIsUsingSystemExtension: () -> Bool

    init(extensionID: String,
         availableExtensionVariants: ExtensionVariant,
         store: ExtensionConfigurationStore,
         updateIsUsingSystemExtension: @escaping () -> Bool) {

        self.availableExtensionVariants = availableExtensionVariants
        self.store = store
        self.updateIsUsingSystemExtension = updateIsUsingSystemExtension
    }

    var isUsingSystemExtension: Bool {
        switch availableExtensionVariants {
        case .both:
            let isUsingSystemExtension = updateIsUsingSystemExtension()
            store.isUsingSystemExtension = isUsingSystemExtension
            return isUsingSystemExtension
        case .sysex:
            store.isUsingSystemExtension = true
            return true
        }
    }
}

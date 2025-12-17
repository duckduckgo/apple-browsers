//
//  FireConfirmationSettingsStore.swift
//  DuckDuckGo
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
import Common

protocol FireConfirmationSettingsStoring: AnyObject {
    var clearTabs: Bool { get set }
    var clearData: Bool { get set }
    var clearAIChats: Bool { get set }
}

final class FireConfirmationSettingsStore: FireConfirmationSettingsStoring {
    
    enum StorageKey: String {
        case clearTabs = "com_duckduckgo_ios_fireConfirmation_toggle_clearTabs"
        case clearData = "com_duckduckgo_ios_fireConfirmation_toggle_clearData"
        case clearAIChats = "com_duckduckgo_ios_fireConfirmation_toggle_clearAIChats"
    }
    
    private let keyValueFilesStore: ThrowingKeyValueStoring
    
    init(keyValueFilesStore: ThrowingKeyValueStoring) {
        self.keyValueFilesStore = keyValueFilesStore
    }
    
    var clearTabs: Bool {
        get {
            getValue(forKey: .clearTabs) ?? true
        }
        set {
            write(value: newValue, forKey: .clearTabs)
        }
    }
    
    var clearData: Bool {
        get {
            getValue(forKey: .clearData) ?? true
        }
        set {
            write(value: newValue, forKey: .clearData)
        }
    }
    
    var clearAIChats: Bool {
        get {
            getValue(forKey: .clearAIChats) ?? false
        }
        set {
            write(value: newValue, forKey: .clearAIChats)
        }
    }
    
    private func getValue<T>(forKey key: StorageKey) -> T? {
        do {
            return try keyValueFilesStore.object(forKey: key.rawValue) as? T
        } catch {
            Logger.general.error("Failed to retrieve fire confirmation setting for key \(key.rawValue): \(error.localizedDescription)")
            return nil
        }
    }
    
    private func write<T>(value: T?, forKey key: StorageKey) {
        do {
            try keyValueFilesStore.set(value, forKey: key.rawValue)
        } catch {
            Logger.general.error("Failed to save fire confirmation setting for key \(key.rawValue): \(error.localizedDescription)")
        }
    }
}

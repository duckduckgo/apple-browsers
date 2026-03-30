//
//  AIChatPreferencesPersistor.swift
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
import Persistence

public protocol AIChatPreferencesPersisting {
    var selectedModelId: String? { get set }
    /// The short display name of the last selected model, used to show the button before models are fetched.
    var selectedModelShortName: String? { get set }
}

public struct AIChatPreferencesPersistor: AIChatPreferencesPersisting {

    enum Key: String {
        case selectedModelId = "aichat.omnibar.selected-model-id"
        case selectedModelShortName = "aichat.omnibar.selected-model-short-name"
    }

    private let keyValueStore: ThrowingKeyValueStoring

    public init(keyValueStore: ThrowingKeyValueStoring = UserDefaults.standard) {
        self.keyValueStore = keyValueStore
    }

    public var selectedModelId: String? {
        get { try? keyValueStore.object(forKey: Key.selectedModelId.rawValue) as? String }
        set {
            if let value = newValue {
                try? keyValueStore.set(value, forKey: Key.selectedModelId.rawValue)
            } else {
                try? keyValueStore.removeObject(forKey: Key.selectedModelId.rawValue)
            }
        }
    }

    public var selectedModelShortName: String? {
        get { try? keyValueStore.object(forKey: Key.selectedModelShortName.rawValue) as? String }
        set {
            if let value = newValue {
                try? keyValueStore.set(value, forKey: Key.selectedModelShortName.rawValue)
            } else {
                try? keyValueStore.removeObject(forKey: Key.selectedModelShortName.rawValue)
            }
        }
    }
}

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

import Combine
import Foundation
import Persistence

public protocol AIChatPreferencesPersisting {
    var selectedModelId: String? { get set }
    /// Emits the new value whenever `selectedModelId` changes through this persistor instance.
    /// Consumers that need cross-component sync must share the same instance.
    var selectedModelIdPublisher: AnyPublisher<String?, Never> { get }
    /// The short display name of the last selected model, used to show the button before models are fetched.
    var selectedModelShortName: String? { get set }
    /// The last selected reasoning effort (e.g. "none", "minimal", "low", "medium").
    var selectedReasoningEffort: String? { get set }
    /// Emits the new value whenever `selectedReasoningEffort` changes through this persistor instance.
    /// Consumers that need cross-component sync must share the same instance.
    var selectedReasoningEffortPublisher: AnyPublisher<String?, Never> { get }
    var selectedReasoningMode: AIChatReasoningMode? { get set }
    /// The last user-selected RAG tool, used to seed `LastUsedInputDefaults` after relaunch
    /// so new tabs inherit the previous session's tool choice rather than nil.
    var selectedTool: AIChatRAGTool? { get set }
}

/// Reference type so that a single instance can be shared across components (e.g. the native address-bar
/// omnibar and the New Tab Page omnibar) and both observe the same `selectedModelIdPublisher`.
public final class AIChatPreferencesPersistor: AIChatPreferencesPersisting {

    enum Key: String {
        case selectedModelId = "aichat.omnibar.selected-model-id"
        case selectedModelShortName = "aichat.omnibar.selected-model-short-name"
        case selectedReasoningEffort = "aichat.omnibar.selected-reasoning-effort"
        case selectedReasoningMode = "aichat.omnibar.selected-reasoning-mode"
        case selectedTool = "aichat.omnibar.selected-tool"
    }

    private let keyValueStore: ThrowingKeyValueStoring
    private let selectedModelIdSubject = PassthroughSubject<String?, Never>()
    private let selectedReasoningEffortSubject = PassthroughSubject<String?, Never>()

    public init(keyValueStore: ThrowingKeyValueStoring = UserDefaults.standard) {
        self.keyValueStore = keyValueStore
    }

    public var selectedModelId: String? {
        get { try? keyValueStore.object(forKey: Key.selectedModelId.rawValue) as? String }
        set {
            let current = try? keyValueStore.object(forKey: Key.selectedModelId.rawValue) as? String
            guard newValue != current else { return }
            if let value = newValue {
                try? keyValueStore.set(value, forKey: Key.selectedModelId.rawValue)
            } else {
                try? keyValueStore.removeObject(forKey: Key.selectedModelId.rawValue)
            }
            selectedModelIdSubject.send(newValue)
        }
    }

    public var selectedModelIdPublisher: AnyPublisher<String?, Never> {
        selectedModelIdSubject.eraseToAnyPublisher()
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

    public var selectedReasoningEffort: String? {
        get { try? keyValueStore.object(forKey: Key.selectedReasoningEffort.rawValue) as? String }
        set {
            let current = try? keyValueStore.object(forKey: Key.selectedReasoningEffort.rawValue) as? String
            guard newValue != current else { return }
            if let value = newValue {
                try? keyValueStore.set(value, forKey: Key.selectedReasoningEffort.rawValue)
            } else {
                try? keyValueStore.removeObject(forKey: Key.selectedReasoningEffort.rawValue)
            }
            selectedReasoningEffortSubject.send(newValue)
        }
    }

    public var selectedReasoningEffortPublisher: AnyPublisher<String?, Never> {
        selectedReasoningEffortSubject.eraseToAnyPublisher()
    }

    public var selectedReasoningMode: AIChatReasoningMode? {
        get {
            guard let rawValue = try? keyValueStore.object(forKey: Key.selectedReasoningMode.rawValue) as? String else {
                return nil
            }

            return AIChatReasoningMode(rawValue: rawValue)
        }
        set {
            let current = try? keyValueStore.object(forKey: Key.selectedReasoningMode.rawValue) as? String
            guard newValue?.rawValue != current else { return }
            if let value = newValue?.rawValue {
                try? keyValueStore.set(value, forKey: Key.selectedReasoningMode.rawValue)
            } else {
                try? keyValueStore.removeObject(forKey: Key.selectedReasoningMode.rawValue)
            }
        }
    }

    public var selectedTool: AIChatRAGTool? {
        get {
            guard let rawValue = try? keyValueStore.object(forKey: Key.selectedTool.rawValue) as? String else {
                return nil
            }
            return AIChatRAGTool(rawValue: rawValue)
        }
        set {
            let current = try? keyValueStore.object(forKey: Key.selectedTool.rawValue) as? String
            guard newValue?.rawValue != current else { return }
            if let value = newValue?.rawValue {
                try? keyValueStore.set(value, forKey: Key.selectedTool.rawValue)
            } else {
                try? keyValueStore.removeObject(forKey: Key.selectedTool.rawValue)
            }
        }
    }
}

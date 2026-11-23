//
//  AIChatLocalModelEngineOverride.swift
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

/// Debug menu: which engine runs local summaries, on any device. Switching keeps the downloaded
/// model, so switching back is instant.
public enum LocalModelEngineOverride: String, CaseIterable {
    case automatic
    case appleIntelligence
    case llama

    public var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .appleIntelligence: return "Apple Intelligence"
        case .llama: return "Downloadable Model (llama.cpp)"
        }
    }

    public var engineKind: AIChatLocalModelEngineKind? {
        switch self {
        case .automatic: return nil
        case .appleIntelligence: return .appleIntelligence
        case .llama: return .llama
        }
    }
}

public struct LocalModelEngineOverridePersistor {

    public static let key = "aichat.localModel.engineOverride"
    public static let didChangeNotification = Notification.Name("LocalModelEngineOverrideDidChange")

    private let keyValueStore: KeyValueStoring
    private let notificationCenter: NotificationCenter

    public init(keyValueStore: KeyValueStoring = UserDefaults.standard, notificationCenter: NotificationCenter = .default) {
        self.keyValueStore = keyValueStore
        self.notificationCenter = notificationCenter
    }

    public var current: LocalModelEngineOverride {
        get {
            (keyValueStore.object(forKey: Self.key) as? String).flatMap(LocalModelEngineOverride.init) ?? .automatic
        }
        nonmutating set {
            if newValue == .automatic {
                keyValueStore.removeObject(forKey: Self.key)
            } else {
                keyValueStore.set(newValue.rawValue, forKey: Self.key)
            }
            notificationCenter.post(name: Self.didChangeNotification, object: nil)
        }
    }

    public var updates: AnyPublisher<Void, Never> {
        notificationCenter.publisher(for: Self.didChangeNotification).map { _ in () }.eraseToAnyPublisher()
    }
}

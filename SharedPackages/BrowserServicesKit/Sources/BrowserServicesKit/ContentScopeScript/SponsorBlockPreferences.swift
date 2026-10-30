//
//  SponsorBlockPreferences.swift
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

public enum SponsorBlockSkipMode: String, CaseIterable {
    case manual
    case auto
}

public struct SponsorBlockSettings: StoringKeys {
    public let isEnabled = StorageKey<Bool>(SponsorBlockStorageKey.isEnabled)
    public let skipMode = StorageKey<SponsorBlockSkipMode>(SponsorBlockStorageKey.skipMode)

    public init() {}
}

enum SponsorBlockStorageKey: String, StorageKeyDescribing {
    case isEnabled = "sponsorBlockEnabled"
    case skipMode = "sponsorBlockSkipMode"
}

/// User settings for sponsor skipping, shared by both apps. Unset values fall back to the MVP defaults: on, manual.
///
/// Changes are posted on `didChangeNotification`, so observers re-read the store (the file-backed iOS store has no publisher).
public final class SponsorBlockPreferences {

    public static let didChangeNotification = Notification.Name("sponsorBlockPreferencesDidChange")

    private let settings: any ThrowingKeyedStoring<SponsorBlockSettings>
    private let notificationCenter: NotificationCenter

    public init(store: ThrowingKeyValueStoring, notificationCenter: NotificationCenter = .default) {
        self.settings = store.throwingKeyedStoring()
        self.notificationCenter = notificationCenter
    }

    public var isEnabled: Bool {
        get { (try? settings.isEnabled) ?? true }
        set { set(newValue, for: \.isEnabled) }
    }

    public var skipMode: SponsorBlockSkipMode {
        get { (try? settings.skipMode) ?? .manual }
        set { set(newValue, for: \.skipMode) }
    }

    /// Emits after every write through this or any other instance backed by the same store.
    public var updates: AnyPublisher<Void, Never> {
        notificationCenter.publisher(for: Self.didChangeNotification).map { _ in () }.eraseToAnyPublisher()
    }

    private func set<Value>(_ value: Value, for keyPath: KeyPath<SponsorBlockSettings, StorageKey<Value>>) {
        try? settings.set(value, for: keyPath)
        notificationCenter.post(name: Self.didChangeNotification, object: nil)
    }
}

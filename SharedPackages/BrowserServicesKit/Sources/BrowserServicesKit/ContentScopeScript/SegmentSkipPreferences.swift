//
//  SegmentSkipPreferences.swift
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

/// The user's choice, shown in Settings and the address bar popover.
public enum SegmentSkipSetting: String, CaseIterable {
    case always
    case askToSkip
    case off
}

public struct SegmentSkipSettings: StoringKeys {
    public let setting = StorageKey<SegmentSkipSetting>(SegmentSkipStorageKey.setting)

    public init() {}
}

enum SegmentSkipStorageKey: String, StorageKeyDescribing {
    case setting = "segmentSkipSetting"
}

/// User settings for sponsor skipping, shared by both apps. An unset value falls back to `.askToSkip`.
///
/// Changes are posted on `didChangeNotification`, so observers re-read the store (the file-backed iOS store has no publisher).
public final class SegmentSkipPreferences {

    public static let didChangeNotification = Notification.Name("segmentSkipPreferencesDidChange")

    private let settings: any ThrowingKeyedStoring<SegmentSkipSettings>
    private let notificationCenter: NotificationCenter

    public init(store: ThrowingKeyValueStoring, notificationCenter: NotificationCenter = .default) {
        self.settings = store.throwingKeyedStoring()
        self.notificationCenter = notificationCenter
    }

    public var setting: SegmentSkipSetting {
        get { (try? settings.setting) ?? .askToSkip }
        set {
            try? settings.set(newValue, for: \.setting)
            notificationCenter.post(name: Self.didChangeNotification, object: nil)
        }
    }

    /// Emits after every write through this or any other instance backed by the same store.
    public var updates: AnyPublisher<Void, Never> {
        notificationCenter.publisher(for: Self.didChangeNotification).map { _ in () }.eraseToAnyPublisher()
    }
}

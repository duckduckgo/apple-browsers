//
//  WebsitePermissionDefaultsStorage.swift
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

/// Storage for the per-category "Default" behaviour chosen in Settings > Website Permissions.
protocol WebsitePermissionDefaultsStorage {
    func decisionRawValue(for category: WebsitePermissionCategory) -> String?
    func setDecisionRawValue(_ rawValue: String, for category: WebsitePermissionCategory)
}

struct WebsitePermissionDefaultsUserDefaultsStorage: WebsitePermissionDefaultsStorage {

    enum Key: String {
        case notifications = "website-permissions.default.notifications"
        case location = "website-permissions.default.location"
        case camera = "website-permissions.default.camera"
        case microphone = "website-permissions.default.microphone"
        case externalApps = "website-permissions.default.external-apps"
        case popups = "website-permissions.default.popups"

        /// `nil` for Autoplay, whose default is the all-sites blocking mode owned by `AutoplayPreferences`.
        init?(category: WebsitePermissionCategory) {
            switch category {
            case .notifications: self = .notifications
            case .location: self = .location
            case .camera: self = .camera
            case .microphone: self = .microphone
            case .externalApps: self = .externalApps
            case .popups: self = .popups
            case .autoplay: return nil
            }
        }
    }

    private let keyValueStore: ThrowingKeyValueStoring

    init(keyValueStore: ThrowingKeyValueStoring) {
        self.keyValueStore = keyValueStore
    }

    func decisionRawValue(for category: WebsitePermissionCategory) -> String? {
        guard let key = Key(category: category) else { return nil }
        return try? keyValueStore.object(forKey: key.rawValue) as? String
    }

    func setDecisionRawValue(_ rawValue: String, for category: WebsitePermissionCategory) {
        guard let key = Key(category: category) else { return }
        try? keyValueStore.set(rawValue, forKey: key.rawValue)
    }
}

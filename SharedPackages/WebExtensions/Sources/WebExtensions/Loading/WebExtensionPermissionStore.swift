//
//  WebExtensionPermissionStore.swift
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

/// Browser-owned consent, separate from the extension's own WebKit storage.
/// Retained across restarts, reloads, and browsing-data clearing, until the installation is removed.
/// Updates copy these settings to the replacement installation before removing the old one.
public struct WebExtensionPermissionSettings: Codable, Equatable {
    public var hasAccessToPrivateData = false
    public var grantedPermissions: [String: Date] = [:]
    public var grantedMatchPatterns: [String: Date] = [:]
    public var hasRequestedOptionalAccessToAllHosts = false
    /// Permissions the app implements itself, which WebKit doesn't keep (see `WebExtensionAppPermission`).
    public var grantedAppPermissions: [String: Date] = [:]

    public init() {}

    /// Settings saved before a property existed decode with its default.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hasAccessToPrivateData = try container.decodeIfPresent(Bool.self, forKey: .hasAccessToPrivateData) ?? false
        grantedPermissions = try container.decodeIfPresent([String: Date].self, forKey: .grantedPermissions) ?? [:]
        grantedMatchPatterns = try container.decodeIfPresent([String: Date].self, forKey: .grantedMatchPatterns) ?? [:]
        hasRequestedOptionalAccessToAllHosts = try container.decodeIfPresent(Bool.self, forKey: .hasRequestedOptionalAccessToAllHosts) ?? false
        grantedAppPermissions = try container.decodeIfPresent([String: Date].self, forKey: .grantedAppPermissions) ?? [:]
    }
}

public protocol WebExtensionPermissionStoring {
    func settings(for identifier: String) throws -> WebExtensionPermissionSettings?
    func save(_ settings: WebExtensionPermissionSettings, for identifier: String) throws
    func removeSettings(for identifier: String) throws
}

public struct WebExtensionPermissionStore: WebExtensionPermissionStoring {
    private enum Key: String {
        case permissions = "web-extension-permissions"
    }

    private let keyValueStore: any ThrowingKeyValueStoring

    public init(keyValueStore: any ThrowingKeyValueStoring) {
        self.keyValueStore = keyValueStore
    }

    public func settings(for identifier: String) throws -> WebExtensionPermissionSettings? {
        guard let data = try keyValueStore.object(forKey: key(for: identifier)) as? Data else { return nil }
        return try JSONDecoder().decode(WebExtensionPermissionSettings.self, from: data)
    }

    public func save(_ settings: WebExtensionPermissionSettings, for identifier: String) throws {
        try keyValueStore.set(JSONEncoder().encode(settings), forKey: key(for: identifier))
    }

    public func removeSettings(for identifier: String) throws {
        try keyValueStore.removeObject(forKey: key(for: identifier))
    }

    private func key(for identifier: String) -> String {
        "\(Key.permissions.rawValue).\(identifier)"
    }
}

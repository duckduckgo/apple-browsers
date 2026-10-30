//
//  InstalledWebExtension.swift
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

@available(macOS 15.4, iOS 18.4, *)
public struct InstalledWebExtension: Codable, Equatable, Identifiable {

    /// Unique identifier for the extension (UUID)
    public let uniqueIdentifier: String

    /// Original filename from the source URL (e.g., "extension.zip")
    public let filename: String

    /// Display name of the extension
    public let name: String?

    /// Version string
    public let version: String?

    /// If this is an embedded (bundled) extension, stores its type.
    /// Nil for user-installed extensions.
    public let embeddedType: DuckDuckGoWebExtensionType?

    /// Stable identity supplied by the store installer, shared by successive versions.
    /// Nil for bundled extensions, manual installations, and records saved before this field existed.
    public let storeIdentity: WebExtensionStoreIdentity?

    /// Whether the extension is disabled, by the user or by remote configuration. A disabled extension
    /// stays on disk and keeps its permissions, but it is not loaded until the user enables it again.
    /// False for records saved before this field existed.
    public var isDisabled: Bool

    /// CPM's private origin after data clearing, rollback or a background-load failure.
    /// Nil preserves the installation UUID for existing records.
    public var cpmOriginIdentifier: UUID?

    private enum CodingKeys: String, CodingKey {
        case uniqueIdentifier, filename, name, version, embeddedType, storeIdentity, isDisabled
        case cpmOriginIdentifier = "cpmStableOriginIdentifier"
    }

    public var id: String { uniqueIdentifier }

    /// Whether this extension was installed from the app bundle (embedded).
    public var isEmbedded: Bool {
        embeddedType != nil
    }

    public init(
        uniqueIdentifier: String,
        filename: String,
        name: String?,
        version: String?,
        embeddedType: DuckDuckGoWebExtensionType? = nil,
        storeIdentity: WebExtensionStoreIdentity? = nil,
        isDisabled: Bool = false,
        cpmOriginIdentifier: UUID? = nil
    ) {
        self.uniqueIdentifier = uniqueIdentifier
        self.filename = filename
        self.name = name
        self.version = version
        self.embeddedType = embeddedType
        self.storeIdentity = storeIdentity
        self.isDisabled = isDisabled
        self.cpmOriginIdentifier = cpmOriginIdentifier
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uniqueIdentifier = try container.decode(String.self, forKey: .uniqueIdentifier)
        filename = try container.decode(String.self, forKey: .filename)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        embeddedType = try container.decodeIfPresent(DuckDuckGoWebExtensionType.self, forKey: .embeddedType)
        storeIdentity = try container.decodeIfPresent(WebExtensionStoreIdentity.self, forKey: .storeIdentity)
        cpmOriginIdentifier = try container.decodeIfPresent(UUID.self, forKey: .cpmOriginIdentifier)
        isDisabled = try container.decodeIfPresent(Bool.self, forKey: .isDisabled) ?? false
    }
}

/// Identifies an extension across versions without replacing its per-installation UUID.
public struct WebExtensionStoreIdentity: Codable, Equatable, Hashable, Sendable {
    public enum Store: String, Codable, Sendable {
        case chromeWebStore
    }

    public let store: Store
    public let id: String

    public init(store: Store, id: String) {
        self.store = store
        self.id = id
    }
}

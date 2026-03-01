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
        embeddedType: DuckDuckGoWebExtensionType? = nil
    ) {
        self.uniqueIdentifier = uniqueIdentifier
        self.filename = filename
        self.name = name
        self.version = version
        self.embeddedType = embeddedType
    }
}

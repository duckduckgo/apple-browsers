//
//  EmbeddedWebExtensionRegistry.swift
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

/// Describes an embedded web extension bundled with the app.
@available(macOS 15.4, iOS 18.4, *)
public struct EmbeddedWebExtensionDescriptor {

    /// The type identifier for this embedded extension.
    public let type: DuckDuckGoWebExtensionType

    /// Resource name (without extension) in the bundle.
    public let resourceName: String

    /// Resource file extension (e.g., "zip").
    public let resourceExtension: String

    /// Returns the URL to the bundled extension, or nil if not found.
    public var bundledURL: URL? {
        Bundle.module.url(forResource: resourceName, withExtension: resourceExtension, subdirectory: "Resources")
    }

    public init(type: DuckDuckGoWebExtensionType, resourceName: String, resourceExtension: String) {
        self.type = type
        self.resourceName = resourceName
        self.resourceExtension = resourceExtension
    }
}

/// Registry of all embedded web extensions bundled with the app.
/// Add new embedded extensions here as needed.
@available(macOS 15.4, iOS 18.4, *)
public enum EmbeddedWebExtensionRegistry {

    /// All embedded extensions that should be installed/updated on app launch.
    public static let all: [EmbeddedWebExtensionDescriptor] = [
        EmbeddedWebExtensionDescriptor(
            type: .embedded,
            resourceName: "autoconsent",
            resourceExtension: "zip"
        )
    ]

    /// Find descriptor for a given extension type.
    public static func descriptor(for type: DuckDuckGoWebExtensionType) -> EmbeddedWebExtensionDescriptor? {
        all.first { $0.type == type }
    }
}

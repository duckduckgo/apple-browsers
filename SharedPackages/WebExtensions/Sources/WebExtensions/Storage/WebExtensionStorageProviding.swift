//
//  WebExtensionStorageProviding.swift
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

/// Protocol defining platform-specific storage for web extensions.
/// Each platform (iOS, macOS) provides its own implementation that determines
/// where extensions are stored on disk.
@available(macOS 15.4, iOS 18.4, *)
public protocol WebExtensionStorageProviding: AnyObject {

    /// Base directory where extensions are stored.
    var extensionsDirectory: URL { get }

    /// Resolves an extension identifier to its storage path if the extension exists.
    /// - Parameter identifier: The extension identifier (e.g., filename for zip files).
    /// - Returns: The full URL where the extension is stored, or nil if not found.
    func resolveInstalledExtension(identifier: String) -> URL?

    /// Copies an extension from a source URL to platform storage.
    /// This only handles file operations - it does not load the extension or persist metadata.
    /// - Parameters:
    ///   - sourceURL: The source URL of the extension (e.g., from document picker).
    ///   - identifier: The unique identifier used to build the destination path.
    /// - Returns: The destination URL where the extension was copied.
    /// - Throws: If the copy operation fails.
    func copyExtension(from sourceURL: URL, identifier: String) throws -> URL

    /// Removes an extension from storage.
    /// - Parameter identifier: The extension identifier to remove.
    /// - Throws: If the removal fails.
    func removeExtension(identifier: String) throws
}

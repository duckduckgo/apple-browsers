//
//  WebExtensionManaging.swift
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
import WebKit

/// Protocol defining the interface for managing web extensions.
public protocol WebExtensionManaging: AnyObject {

    /// The set of currently loaded extension contexts.
    @available(macOS 15.4, iOS 18.4, *)
    var loadedExtensions: Set<WKWebExtensionContext> { get }

    /// The identifiers of installed web extensions.
    @available(macOS 15.4, iOS 18.4, *)
    var webExtensionIdentifiers: [String] { get }

    /// The web extension controller.
    @available(macOS 15.4, iOS 18.4, *)
    var controller: WKWebExtensionController { get }

    /// The events listener for web extension events.
    @available(macOS 15.4, iOS 18.4, *)
    var eventsListener: WebExtensionEventsListening { get }

    /// The base directory where extensions are stored on disk.
    @available(macOS 15.4, iOS 18.4, *)
    var extensionsDirectory: URL { get }

    /// An async stream that yields when extensions are updated.
    @available(macOS 15.4, iOS 18.4, *)
    var extensionUpdates: AsyncStream<Void> { get }

    /// Loads all installed extensions.
    @available(macOS 15.4, iOS 18.4, *)
    @MainActor
    func loadInstalledExtensions() async

    /// Installs an extension from a source URL, copying it to platform storage.
    /// - Parameter sourceURL: The source URL of the extension (e.g., from document picker).
    @available(macOS 15.4, iOS 18.4, *)
    func installExtension(from sourceURL: URL) async throws

    /// Uninstalls an extension with the given identifier.
    @available(macOS 15.4, iOS 18.4, *)
    func uninstallExtension(identifier: String) throws

    /// Uninstalls all extensions.
    @available(macOS 15.4, iOS 18.4, *)
    @discardableResult
    func uninstallAllExtensions() -> [Result<Void, Error>]

    /// Syncs embedded extensions from the registry based on the enabled types.
    /// Installs/upgrades enabled extensions and uninstalls disabled ones.
    @available(macOS 15.4, iOS 18.4, *)
    @MainActor
    func syncEmbeddedExtensions(enabledTypes: Set<DuckDuckGoWebExtensionType>) async

    /// Uninstalls an embedded extension of the given type if it's currently installed.
    @available(macOS 15.4, iOS 18.4, *)
    func uninstallEmbeddedExtension(type: DuckDuckGoWebExtensionType)

    /// Finds an installed extension by its embedded type.
    @available(macOS 15.4, iOS 18.4, *)
    func installedEmbeddedExtension(for type: DuckDuckGoWebExtensionType) -> InstalledWebExtension?

    /// Returns the installed path for an embedded extension type.
    @available(macOS 15.4, iOS 18.4, *)
    func installedExtensionPath(for type: DuckDuckGoWebExtensionType) -> URL?

    /// Unloads all currently loaded extensions from memory without uninstalling them.
    /// This is useful when clearing browser data to ensure extensions don't interfere.
    @available(macOS 15.4, iOS 18.4, *)
    func unloadAllExtensions()

    /// Reloads an extension by unloading it from memory and loading it again from disk.
    /// Useful when extension files have been modified on disk.
    @available(macOS 15.4, iOS 18.4, *)
    @MainActor
    func reloadExtension(identifier: String) async throws

    /// Returns the extension name for the given identifier.
    @available(macOS 15.4, iOS 18.4, *)
    func extensionName(for identifier: String) -> String?

    /// Returns the extension version for the given identifier.
    @available(macOS 15.4, iOS 18.4, *)
    func extensionVersion(for identifier: String) -> String?

    /// Returns the extension context for the given URL.
    @available(macOS 15.4, iOS 18.4, *)
    func extensionContext(for url: URL) -> WKWebExtensionContext?

    /// Returns the extension context for the given identifier.
    @available(macOS 15.4, iOS 18.4, *)
    func context(for identifier: String) -> WKWebExtensionContext?
}

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

    /// Whether there are any installed extensions.
    @available(macOS 15.4, iOS 18.4, *)
    var hasInstalledExtensions: Bool { get }

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

    /// Returns the extension name from the given path.
    @available(macOS 15.4, iOS 18.4, *)
    func extensionName(for identifier: String) -> String?

    /// Returns the extension context for the given URL.
    @available(macOS 15.4, iOS 18.4, *)
    func extensionContext(for url: URL) -> WKWebExtensionContext?

    /// Returns the extension context for the given identifier.
    @available(macOS 15.4, iOS 18.4, *)
    func context(for identifier: String) -> WKWebExtensionContext?
}

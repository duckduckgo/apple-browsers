//
//  MockWebExtensionManaging.swift
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
import WebExtensions
import WebKit

@available(macOS 15.4, iOS 18.4, *)
public final class MockWebExtensionManaging: WebExtensionManaging {

    public var uninstallAllExtensionsCalled = false
    public var uninstallEmbeddedExtensionCalled = false
    public var uninstalledEmbeddedType: DuckDuckGoWebExtensionType?
    public var uninstallEmbeddedExtensionHandler: (() -> Void)?
    public var syncEmbeddedExtensionsCalled = false

    public var loadedExtensions: Set<WKWebExtensionContext> = []
    public var webExtensionIdentifiers: [String] = []
    public lazy var controller = WKWebExtensionController()
    public lazy var eventsListener: WebExtensionEventsListening = WebExtensionEventsListener()
    public var extensionsDirectory = FileManager.default.temporaryDirectory
    public var extensionUpdates = AsyncStream<Void> { $0.finish() }

    public init() {}

    public func loadInstalledExtensions() async {}
    public func reloadInstalledExtensions() async {}
    public func installExtension(from sourceURL: URL) async throws {}
    @MainActor public func uninstallExtension(identifier: String) throws {}

    @MainActor
    @discardableResult
    public func uninstallAllExtensions() -> [Result<Void, Error>] {
        uninstallAllExtensionsCalled = true
        return []
    }

    @MainActor
    public func syncEmbeddedExtensions(enabledTypes: Set<DuckDuckGoWebExtensionType>) async {
        syncEmbeddedExtensionsCalled = true
    }

    @MainActor
    public func uninstallEmbeddedExtension(type: DuckDuckGoWebExtensionType) {
        uninstallEmbeddedExtensionCalled = true
        uninstalledEmbeddedType = type
        uninstallEmbeddedExtensionHandler?()
    }

    public func installedEmbeddedExtension(for type: DuckDuckGoWebExtensionType) -> InstalledWebExtension? {
        nil
    }

    public func installedExtensionPath(for type: DuckDuckGoWebExtensionType) -> URL? {
        nil
    }

    public func unloadAllExtensions() {}

    public func reloadExtension(identifier: String) async throws {}

    public func extensionName(for identifier: String) -> String? { nil }
    public func extensionVersion(for identifier: String) -> String? { nil }
    public func extensionContext(for url: URL) -> WKWebExtensionContext? { nil }
    public func context(for identifier: String) -> WKWebExtensionContext? { nil }
    @MainActor public func clearCachedScriptlets() {}
    @MainActor public func scriptletDebugInfo() -> [ScriptletDebugInfo] { [] }
}

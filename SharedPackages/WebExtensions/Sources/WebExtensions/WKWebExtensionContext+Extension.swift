//
//  WKWebExtensionContext+Extension.swift
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
import ObjectiveC
import WebKit
import ZIPFoundation

private let browserSpecificSettingsKey = "browser_specific_settings"
private let duckduckgoKey = "duckduckgo"
private let idKey = "id"
private let requiresExtractionKey = "appleRequiresExtraction"
private let actionKey = "action"
private let browserActionKey = "browser_action"
private let pageActionKey = "page_action"
private let permissionsKey = "permissions"
private let optionalPermissionsKey = "optional_permissions"

/// Extension types identified via manifest `browser_specific_settings.duckduckgo.id`.
@available(macOS 15.4, iOS 18.4, *)
public enum DuckDuckGoWebExtensionType: String, Codable, CaseIterable, Sendable {
    /// Embedded web extension (e.g. autoconsent/CPM).
    case embedded = "com.duckduckgo.web-extension.embedded"
    case darkReader = "org.duckduckgo.web-extension.darkreader"
    case adBlockingExtension = "com.duckduckgo.content-blocker-extension"
    case searchToken = "com.duckduckgo.web-extension.search-token"

    /// Short human-readable label used in breakage reports.
    public var shortLabel: String {
        switch self {
        case .embedded: return "embedded"
        case .darkReader: return "darkMode"
        case .adBlockingExtension: return "adBlocking"
        case .searchToken: return "searchToken"
        }
    }
}

/// Returns whether a raw manifest dictionary declares `browser_specific_settings.duckduckgo`, which only our own
/// extensions do. Any such extension is ours, even one whose id `DuckDuckGoWebExtensionType` does not know yet.
///
/// Shared by everything that must decide whether an extension gets the Chrome-compatibility shims, including code
/// that runs before a `WKWebExtension` exists (see `WebExtensionBackgroundPagePatcher`).
func declaresDuckDuckGoSettings(inManifest manifest: [String: Any]) -> Bool {
    let browserSpecific = manifest[browserSpecificSettingsKey] as? [String: Any]
    return browserSpecific?[duckduckgoKey] is [String: Any]
}

/// Metadata extracted from a web extension without loading it into a controller.
@available(macOS 15.4, iOS 18.4, *)
public struct WebExtensionMetadata: Sendable {
    public let type: DuckDuckGoWebExtensionType?
    public let version: String?
    public let requiresExtraction: Bool
}

@available(macOS 15.4, iOS 18.4, *)
extension WebExtensionMetadata {

    /// Parses metadata from a manifest dictionary.
    /// Type and extraction come from `browser_specific_settings.duckduckgo`, e.g.
    /// `"browser_specific_settings": { "duckduckgo": { "id": "com.duckduckgo.web-extension.embedded", "appleRequiresExtraction": true } }`
    init(manifest: [String: Any]) {
        let browserSpecific = manifest[browserSpecificSettingsKey] as? [String: Any]
        let duckduckgo = browserSpecific?[duckduckgoKey] as? [String: Any]
        self.init(
            type: (duckduckgo?[idKey] as? String).flatMap(DuckDuckGoWebExtensionType.init(rawValue:)),
            version: manifest["version"] as? String,
            requiresExtraction: duckduckgo?[requiresExtractionKey] as? Bool ?? false
        )
    }

    /// Reads metadata from the `manifest.json` at the root of a zipped extension.
    /// Unlike `WKWebExtension.metadata(from:)`, this doesn't make WebKit unzip the whole archive
    /// on the main thread, and it runs off the main actor.
    static func fromZip(at url: URL) async throws -> WebExtensionMetadata {
        let archive = try Archive(url: url, accessMode: .read)
        guard let entry = archive["manifest.json"] else {
            throw WebExtensionError.invalidManifest
        }

        var data = Data()
        _ = try archive.extract(entry) { data.append($0) }

        guard let manifest = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WebExtensionError.invalidManifest
        }
        return WebExtensionMetadata(manifest: manifest)
    }
}

@available(macOS 15.4, iOS 18.4, *)
public extension WKWebExtension {

    /// Returns the extension type from manifest `browser_specific_settings.duckduckgo.id`, if present and recognized.
    var duckDuckGoWebExtensionType: DuckDuckGoWebExtensionType? {
        WebExtensionMetadata(manifest: manifest).type
    }

    /// Whether the extension is a third-party one, which gets the Chrome-compatibility behavior
    /// such as native messaging pass-through. Extensions that declare `browser_specific_settings.duckduckgo` are ours.
    var needsChromeCompatibility: Bool {
        !declaresDuckDuckGoSettings(inManifest: manifest)
    }

    /// The manifest's required permissions, including the names WebKit leaves out of `requestedPermissions`.
    var requiredPermissionNames: [String] {
        (manifest[permissionsKey] as? [Any])?.compactMap { $0 as? String } ?? []
    }

    /// Whether the manifest asks for `permission`, as a required or an optional permission.
    ///
    /// Reads the manifest itself, because WebKit leaves out of `requestedPermissions` and
    /// `optionalPermissions` the names it doesn't implement, such as `privacy`.
    func declaresPermission(_ permission: String) -> Bool {
        [permissionsKey, optionalPermissionsKey].contains { key in
            (manifest[key] as? [Any])?.contains { $0 as? String == permission } ?? false
        }
    }

    /// Whether the manifest asks for `permission` as a required permission, which is granted on installation.
    func requiresPermission(_ permission: String) -> Bool {
        requiredPermissionNames.contains(permission)
    }

    /// Returns whether the extension declares a toolbar action in its manifest.
    ///
    /// Manifest V3 uses `action`; Manifest V2 uses `browser_action` or `page_action`.
    /// Extensions without one of these keys have no user-facing button, so the browser
    /// must not put them in the navigation bar.
    ///
    /// Our own embedded extensions are currently forced to not display a toolbar action at all.
    var declaresToolbarAction: Bool {
        if duckDuckGoWebExtensionType != nil {
            return false
        }
        return manifest[actionKey] != nil || manifest[browserActionKey] != nil || manifest[pageActionKey] != nil
    }

    /// Returns whether the extension requires extraction from zip before loading.
    /// Read from manifest `browser_specific_settings.duckduckgo.appleRequiresExtraction`.
    var requiresExtraction: Bool {
        WebExtensionMetadata(manifest: manifest).requiresExtraction
    }

    /// Reads metadata from a web extension at the given URL without loading it into a controller.
    /// This can be used to inspect version and type before deciding whether to install/upgrade.
    /// Given a zip, WebKit unzips the whole archive on the main thread, so prefer
    /// `WebExtensionMetadata.fromZip(at:)` for zips known to have `manifest.json` at the root.
    /// - Parameter url: URL to the extension (folder or zip file)
    /// - Returns: Metadata containing type, version and whether extraction is required
    @MainActor
    static func metadata(from url: URL) async throws -> WebExtensionMetadata {
        let webExtension = try await WKWebExtension.makeCopyingErrors(at: url)
        return WebExtensionMetadata(manifest: webExtension.manifest)
    }
}

@available(macOS 15.4, iOS 18.4, *)
public extension WKWebExtensionContext {

    /// Convenience proxy to the underlying web extension's type.
    var duckDuckGoWebExtensionType: DuckDuckGoWebExtensionType? {
        webExtension.duckDuckGoWebExtensionType
    }

    /// Convenience proxy to `WKWebExtension.needsChromeCompatibility`.
    var needsChromeCompatibility: Bool {
        webExtension.needsChromeCompatibility
    }

    /// Convenience proxy to the underlying web extension's toolbar action declaration.
    var declaresToolbarAction: Bool {
        webExtension.declaresToolbarAction
    }
}

// WebKit vends `WKWebExtension.errors` and `WKWebExtensionContext.errors` as
// `WKNSError` proxies, which crash on x86_64 when bridged to Swift `Error`
// (see NSError+Copying.swift). Swizzling both getters to return real `NSError`
// copies makes every reader safe, including app code that receives contexts
// from WebKit callbacks.

@available(macOS 15.4, iOS 18.4, *)
enum WebExtensionErrorsSwizzling {

    /// Swizzles `errors` of both classes; runs once, later calls do nothing.
    static func install() {
        _ = installation
    }

    private static let installation: Void = {
        let extensionErrors = #selector(getter: WKWebExtension.errors)
        let contextErrors = #selector(getter: WKWebExtensionContext.errors)
        swizzleErrors(of: WKWebExtension.self, getter: extensionErrors)
        swizzleErrors(of: WKWebExtensionContext.self, getter: contextErrors)
    }()

}

private func swizzleErrors(of type: AnyClass, getter selector: Selector) {
    guard let method = class_getInstanceMethod(type, selector) else {
        assertionFailure("\(type) has no `errors` getter")
        return
    }
    typealias Getter = @convention(c) (AnyObject, Selector) -> NSArray
    let implementation = method_getImplementation(method)
    let originalGetter = unsafeBitCast(implementation, to: Getter.self)
    let copyingGetter: @convention(block) (AnyObject) -> NSArray = {
        let errors = originalGetter($0, selector) as [AnyObject]
        return errors.map(NSError.init(copyingObject:)) as NSArray
    }
    let block = imp_implementationWithBlock(copyingGetter)
    method_setImplementation(method, block)
}

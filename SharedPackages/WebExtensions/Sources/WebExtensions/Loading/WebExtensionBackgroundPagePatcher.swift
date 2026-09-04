//
//  WebExtensionBackgroundPagePatcher.swift
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
import os.log

/// Rewrites a Manifest V3 `background.service_worker` declaration into an equivalent
/// `background.page` declaration in an installed extension's manifest.
///
/// Our `WKWebExtension` host does start a `service_worker` background — measured on macOS 26.6.2 —
/// but it is unforgiving: a throw at the top level of the worker aborts its registration outright,
/// so `loadBackgroundContent()` never completes and `WKWebExtensionContext` reports error code 6. A
/// background page running the same script survives the same throw and keeps whatever the script
/// managed to set up before it. Extension vendors work around the same brittleness in Safari the
/// same way — 1Password's Safari build, for instance, ships the very same worker code as a
/// background page.
///
/// The conversion therefore buys one thing: a top-level exception in a Chrome build becomes
/// survivable rather than fatal.
///
/// The patch is deliberately generic and conservative:
/// - it only applies when `background.service_worker` is the *only* background declaration, so a
///   manifest that already uses `background.scripts` or `background.page` (our embedded extensions,
///   such as Dark Reader) is left byte-for-byte untouched;
/// - it is idempotent, because a patched manifest no longer declares a service worker.
///
/// The generated page loads nothing but the extension's own script. `WebExtensionAPIStubScript`,
/// which keeps a Chrome build's top-level startup code alive when it touches a `chrome.*` namespace
/// WebKit does not implement, reaches this page like any other extension page: as a user script on
/// the extension controller's configuration (see `WebExtensionManager`).
struct WebExtensionBackgroundPagePatcher {

    /// Name of the generated background page, written next to `manifest.json`.
    static let backgroundPageFilename = "ddg-background-page.html"

    private static let manifestFilename = "manifest.json"

    private enum ManifestKey {
        static let background = "background"
        static let serviceWorker = "service_worker"
        static let scripts = "scripts"
        static let page = "page"
        static let type = "type"
        static let moduleType = "module"
    }

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Patches the manifest of the extension installed at `installedExtensionURL` when it declares
    /// its background as a service worker only.
    /// - Parameter installedExtensionURL: The installed extension directory, as
    ///   `WebExtensionStorageProviding.resolveInstalledExtension` resolved it — so the manifest sits
    ///   directly in it, and any top-level wrapper folder an archive carried is already unwrapped.
    /// - Returns: `true` when the manifest was rewritten, `false` when nothing needed patching or
    ///   the patch could not be applied.
    @discardableResult
    func patchIfNeeded(installedExtensionURL: URL) -> Bool {
        guard let manifestDirectory = manifestDirectory(in: installedExtensionURL) else {
            return false
        }

        let manifestURL = manifestDirectory.appendingPathComponent(Self.manifestFilename)

        do {
            let manifestData = try Data(contentsOf: manifestURL)

            guard var manifest = try JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
                  var background = manifest[ManifestKey.background] as? [String: Any],
                  let serviceWorkerPath = background[ManifestKey.serviceWorker] as? String,
                  !serviceWorkerPath.isEmpty,
                  background[ManifestKey.scripts] == nil,
                  background[ManifestKey.page] == nil else {
                return false
            }

            let isModule = background[ManifestKey.type] as? String == ManifestKey.moduleType
            let backgroundPage = Self.backgroundPage(loading: serviceWorkerPath, asModule: isModule)
            let backgroundPageURL = manifestDirectory.appendingPathComponent(Self.backgroundPageFilename)
            try backgroundPage.write(to: backgroundPageURL, atomically: true, encoding: .utf8)

            background[ManifestKey.page] = Self.backgroundPageFilename
            background[ManifestKey.serviceWorker] = nil
            background[ManifestKey.type] = nil
            manifest[ManifestKey.background] = background

            let patchedData = try JSONSerialization.data(withJSONObject: manifest,
                                                         options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            try patchedData.write(to: manifestURL, options: .atomic)

            Logger.webExtensions.info("""
            🔧 Patched manifest at \(manifestURL.path): service worker background '\(serviceWorkerPath)' \
            rewritten as background page '\(Self.backgroundPageFilename)' (module: \(isModule))
            """)
            return true
        } catch {
            Logger.webExtensions.error("❌ Failed to patch manifest at \(manifestURL.path): \(error.localizedDescription)")
            return false
        }
    }

    /// Returns `directory` when it is a directory holding `manifest.json`, and `nil` otherwise.
    ///
    /// The directory check is not redundant: an installed extension can also be an archive file,
    /// which has no manifest to patch.
    private func manifestDirectory(in directory: URL) -> URL? {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }

        guard fileManager.fileExists(atPath: directory.appendingPathComponent(Self.manifestFilename).path) else {
            return nil
        }

        return directory
    }

    /// Builds a background page that loads `scriptPath` with a root-absolute `src`, so the page
    /// resolves the script the same way the manifest's service worker path did.
    private static func backgroundPage(loading scriptPath: String, asModule isModule: Bool) -> String {
        var normalizedPath = scriptPath
        while normalizedPath.hasPrefix("./") {
            normalizedPath.removeFirst(2)
        }
        while normalizedPath.hasPrefix("/") {
            normalizedPath.removeFirst()
        }

        let source = htmlEscaped("/" + normalizedPath)
        let typeAttribute = isModule ? " type=\"module\"" : ""

        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <title>Background</title>
        </head>
        <body>
            <script defer\(typeAttribute) src="\(source)"></script>
        </body>
        </html>

        """
    }

    private static func htmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

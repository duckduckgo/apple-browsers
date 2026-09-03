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
/// The conversion therefore buys two things:
/// - a top-level exception in a Chrome build becomes survivable rather than fatal;
/// - the generated page is a manifest-level place to load scripts *before* the extension's own
///   code, which a module service worker offers no hook for, so a classic worker's `importScripts`
///   can be served without editing the extension's own sources.
///
/// The patch is deliberately generic and conservative:
/// - it only applies when `background.service_worker` is the *only* background declaration, so a
///   manifest that already uses `background.scripts` or `background.page` (our embedded extensions,
///   such as Dark Reader) is left byte-for-byte untouched;
/// - it is idempotent, because a patched manifest no longer declares a service worker.
///
/// For a classic (non-module) worker the generated page also loads `WebExtensionImportScriptsShim`
/// plus the bundle's split chunks ahead of the extension's own script, so a worker bundle calling
/// `importScripts` still bootstraps. `WebExtensionAPIStubScript`, which keeps a Chrome build's
/// top-level startup code alive when it touches a `chrome.*` namespace WebKit does not implement,
/// reaches this page like any other extension page: as a user script on the extension controller's
/// configuration (see `WebExtensionManager`).
///
/// The same pass also restores a missing Chrome Web Store `key`, see `WebExtensionManifestKeyPatcher`.
/// That part is independent of the background rewrite and runs even when the manifest declares no
/// service worker at all.
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
    private let keyPatcher: WebExtensionManifestKeyPatcher

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.keyPatcher = WebExtensionManifestKeyPatcher(fileManager: fileManager)
    }

    /// Patches the manifest of the extension installed at `installedExtensionURL`: rewrites a
    /// service-worker-only background into a background page, and restores a missing Web Store `key`.
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

            guard var manifest = try JSONSerialization.jsonObject(with: manifestData) as? [String: Any] else {
                return false
            }

            let backgroundWasPatched = try patchBackground(in: &manifest, manifestDirectory: manifestDirectory)
            let keyWasPatched = keyPatcher.insertKnownPublicKeyIfNeeded(in: &manifest, manifestDirectory: manifestDirectory)

            guard backgroundWasPatched || keyWasPatched else {
                return false
            }

            let patchedData = try JSONSerialization.data(withJSONObject: manifest,
                                                         options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            try patchedData.write(to: manifestURL, options: .atomic)
            return true
        } catch {
            Logger.webExtensions.error("❌ Failed to patch manifest at \(manifestURL.path): \(error.localizedDescription)")
            return false
        }
    }

    /// Rewrites `manifest`'s background section into a background page and writes the page and the
    /// scripts it loads, when the manifest declares a service worker and nothing else.
    /// - Returns: `true` when `manifest` was changed.
    private func patchBackground(in manifest: inout [String: Any], manifestDirectory: URL) throws -> Bool {
        guard var background = manifest[ManifestKey.background] as? [String: Any],
              let serviceWorkerPath = background[ManifestKey.serviceWorker] as? String,
              !serviceWorkerPath.isEmpty,
              background[ManifestKey.scripts] == nil,
              background[ManifestKey.page] == nil else {
            return false
        }

        // A module worker loads its chunks with `import()`, which a page supports natively, so
        // neither the shim nor preloaded chunks are needed — or wanted — there.
        let isModule = background[ManifestKey.type] as? String == ManifestKey.moduleType
        let normalizedWorkerPath = Self.normalizedExtensionPath(serviceWorkerPath)
        let chunkPaths = isModule ? [] : chunkScriptPaths(forWorkerAt: normalizedWorkerPath, in: manifestDirectory)

        if !isModule {
            let shimURL = manifestDirectory.appendingPathComponent(WebExtensionImportScriptsShim.filename)
            try WebExtensionImportScriptsShim.source.write(to: shimURL, atomically: true, encoding: .utf8)
        }

        let backgroundPage = Self.backgroundPage(loading: normalizedWorkerPath,
                                                 asModule: isModule,
                                                 preloadingChunksAt: chunkPaths)
        let backgroundPageURL = manifestDirectory.appendingPathComponent(Self.backgroundPageFilename)
        try backgroundPage.write(to: backgroundPageURL, atomically: true, encoding: .utf8)

        background[ManifestKey.page] = Self.backgroundPageFilename
        background[ManifestKey.serviceWorker] = nil
        background[ManifestKey.type] = nil
        manifest[ManifestKey.background] = background

        Logger.webExtensions.info("""
        🔧 Patched manifest in \(manifestDirectory.path): service worker background '\(serviceWorkerPath)' \
        rewritten as background page '\(Self.backgroundPageFilename)' (module: \(isModule)), \
        preloading \(chunkPaths.count) webpack chunk(s): [\(chunkPaths.joined(separator: ", "))]
        """)
        return true
    }

    /// Chunk files a classic worker bundle would load with `importScripts`, as extension-root-relative
    /// paths sorted by chunk id.
    ///
    /// webpack names a split chunk `<chunk id>.<worker basename>` and emits it next to the worker, so
    /// `background.js` is accompanied by `719.background.js`. The bundle computes that name at runtime
    /// from an id we cannot see from here, which is why the page preloads every candidate it finds
    /// rather than the one file a given `importScripts` call asks for.
    private func chunkScriptPaths(forWorkerAt normalizedWorkerPath: String, in manifestDirectory: URL) -> [String] {
        let workerFilename = (normalizedWorkerPath as NSString).lastPathComponent
        let workerDirectoryPath = (normalizedWorkerPath as NSString).deletingLastPathComponent
        let workerDirectory = workerDirectoryPath.isEmpty
            ? manifestDirectory
            : manifestDirectory.appendingPathComponent(workerDirectoryPath)

        guard let filenames = try? fileManager.contentsOfDirectory(atPath: workerDirectory.path) else {
            return []
        }

        let suffix = "." + workerFilename
        let chunks: [(id: Int, filename: String)] = filenames.compactMap { filename in
            guard filename.hasSuffix(suffix) else { return nil }
            let identifier = filename.dropLast(suffix.count)
            guard !identifier.isEmpty,
                  identifier.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let id = Int(identifier) else {
                return nil
            }
            return (id, filename)
        }

        return chunks
            .sorted { $0.id < $1.id }
            .map { workerDirectoryPath.isEmpty ? $0.filename : workerDirectoryPath + "/" + $0.filename }
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

    /// Strips the leading `./` and `/` a manifest path may carry, leaving a path relative to the
    /// extension root.
    private static func normalizedExtensionPath(_ path: String) -> String {
        var normalizedPath = path
        while normalizedPath.hasPrefix("./") {
            normalizedPath.removeFirst(2)
        }
        while normalizedPath.hasPrefix("/") {
            normalizedPath.removeFirst()
        }
        return normalizedPath
    }

    /// Builds a background page that loads `normalizedWorkerPath` with a root-absolute `src`, so the
    /// page resolves the script the same way the manifest's service worker path did.
    ///
    /// Every script the page adds is classic and non-deferred, so all of them finish executing before
    /// the extension's own script starts — whether that one is a module (always deferred) or a classic
    /// deferred script. Order matters: the `importScripts` shim first (which the chunks do not need
    /// but the bundle does), then the chunk payloads the shim will replay, then the bundle itself.
    private static func backgroundPage(loading normalizedWorkerPath: String,
                                       asModule isModule: Bool,
                                       preloadingChunksAt chunkPaths: [String]) -> String {
        let source = htmlEscaped("/" + normalizedWorkerPath)
        let typeAttribute = isModule ? " type=\"module\"" : ""

        var preloadedScripts: [String] = []
        if !isModule {
            preloadedScripts.append("    <script src=\"/\(WebExtensionImportScriptsShim.filename)\"></script>")
        }
        preloadedScripts += chunkPaths.map { "    <script src=\"\(htmlEscaped("/" + $0))\"></script>" }

        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <title>Background</title>
        </head>
        <body>
        \(preloadedScripts.joined(separator: "\n"))
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

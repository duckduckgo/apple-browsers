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
import ZIPFoundation

/// Makes Chrome extensions start their background script in WebKit.
///
/// Chrome's Manifest V3 extensions run their background code in a service worker
/// (`"background": { "service_worker": "background.js" }`). In WebKit, if that script throws
/// while starting, for example because it calls a Chrome API WebKit doesn't have, the whole
/// background is discarded and the extension doesn't work.
///
/// A background page doesn't have that problem: when its script throws, the page stays loaded.
/// So when a third-party extension is installed, this rewrites its manifest to load the same
/// script from a generated page, `ddg-background-page.html`.
///
/// It leaves the manifest unchanged when:
/// - the extension is one of ours (its manifest has `browser_specific_settings.duckduckgo`);
/// - the background is not just a service worker (it already uses `scripts` or `page`).
///
/// Running it twice is harmless: after the first run there is no service worker left to rewrite.
///
/// Extensions installed from the Chrome Web Store are kept as a ZIP, which can't be rewritten. Those
/// are unpacked into a folder next to the ZIP, and the rewrite and WebKit use that folder instead
/// (see `loadableExtensionURL(for:)`).
///
/// Some service workers load extra files with `importScripts`, which pages don't have. For those,
/// the page first loads `WebExtensionImportScriptsShim` and the extra files, then the
/// extension's script.
struct WebExtensionBackgroundPagePatcher {

    /// Name of the generated background page, written next to `manifest.json`.
    static let backgroundPageFilename = "ddg-background-page.html"

    private static let manifestFilename = "manifest.json"

    /// Name of the folder an archived extension is unpacked into, next to the archive.
    static let unpackedFolderName = "unpacked"

    /// File in the unpacked folder recording the modification date of the archive it came from.
    private static let archiveDateFilename = ".ddg-archive-date"

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

    /// Returns the URL WebKit should load the installed extension from, rewriting its background first
    /// when needed.
    ///
    /// For a folder, that's the folder itself, patched in place. For a ZIP whose background must be
    /// rewritten, it's an unpacked copy next to the ZIP, with the rewrite applied; the ZIP itself is never
    /// changed. The copy is reused until the ZIP changes, and it lives in the extension's install folder,
    /// so uninstalling removes it too. Any other ZIP, and any failure, returns the ZIP as it is.
    func loadableExtensionURL(for installedExtensionURL: URL) -> URL {
        guard installedExtensionURL.pathExtension.lowercased() == "zip" else {
            patchIfNeeded(installedExtensionURL: installedExtensionURL)
            return installedExtensionURL
        }

        do {
            let archive = try Archive(url: installedExtensionURL, accessMode: .read)
            guard let manifest = try Self.manifest(in: archive),
                  !declaresDuckDuckGoSettings(inManifest: manifest),
                  Self.hasServiceWorkerOnlyBackground(manifest) else {
                return installedExtensionURL
            }

            let unpackedURL = installedExtensionURL.deletingLastPathComponent()
                .appendingPathComponent(Self.unpackedFolderName, isDirectory: true)
            try unpackIfNeeded(installedExtensionURL, to: unpackedURL)
            guard let extensionDirectory = extensionDirectory(in: unpackedURL) else {
                return installedExtensionURL
            }

            patchIfNeeded(installedExtensionURL: extensionDirectory)
            return extensionDirectory
        } catch {
            Logger.webExtensions.error("❌ Failed to unpack \(installedExtensionURL.path) for its background rewrite: \(error.localizedDescription)")
            return installedExtensionURL
        }
    }

    /// Unpacks `archiveURL` into `unpackedURL`, unless it already holds this version of the archive.
    private func unpackIfNeeded(_ archiveURL: URL, to unpackedURL: URL) throws {
        // Read from disk each time: `URL` resource values are cached and would miss an updated archive.
        let archiveDate = try fileManager.attributesOfItem(atPath: archiveURL.path)[.modificationDate] as? Date
        let dateStamp = archiveDate.map { String($0.timeIntervalSinceReferenceDate) } ?? ""
        let stampURL = unpackedURL.appendingPathComponent(Self.archiveDateFilename)
        if let unpackedStamp = try? String(contentsOf: stampURL, encoding: .utf8), unpackedStamp == dateStamp {
            return
        }

        if fileManager.fileExists(atPath: unpackedURL.path) {
            try fileManager.removeItem(at: unpackedURL)
        }
        try fileManager.createDirectory(at: unpackedURL, withIntermediateDirectories: true)
        try fileManager.unzipItem(at: archiveURL, to: unpackedURL)
        try dateStamp.write(to: stampURL, atomically: true, encoding: .utf8)
    }

    /// The folder holding `manifest.json`: `directory` itself, or the single top-level folder an archive
    /// wrapped its contents in.
    private func extensionDirectory(in directory: URL) -> URL? {
        if let manifestDirectory = manifestDirectory(in: directory) {
            return manifestDirectory
        }
        let contents = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil,
                                                              options: [.skipsHiddenFiles])) ?? []
        return contents.lazy.compactMap { manifestDirectory(in: $0) }.first
    }

    /// The manifest of an archived extension, at its root or inside a single top-level folder.
    private static func manifest(in archive: Archive) throws -> [String: Any]? {
        let entry = archive[manifestFilename]
            ?? archive.first { $0.type == .file && $0.path.split(separator: "/").count == 2 && $0.path.hasSuffix("/" + manifestFilename) }
        guard let entry else { return nil }

        var data = Data()
        _ = try archive.extract(entry) { data.append($0) }
        return try JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// Whether the manifest declares a service worker and no other background, which is what gets rewritten.
    private static func hasServiceWorkerOnlyBackground(_ manifest: [String: Any]) -> Bool {
        guard let background = manifest[ManifestKey.background] as? [String: Any],
              let serviceWorkerPath = background[ManifestKey.serviceWorker] as? String else {
            return false
        }
        return !serviceWorkerPath.isEmpty && background[ManifestKey.scripts] == nil && background[ManifestKey.page] == nil
    }

    /// Patches the manifest of the extension installed at `installedExtensionURL`: rewrites a
    /// service-worker-only background into a background page.
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

            // Only third-party extensions get the Chrome-compatibility rewrite. This runs before a
            // `WKWebExtension` exists, so it reads the raw manifest.
            guard !declaresDuckDuckGoSettings(inManifest: manifest) else {
                return false
            }

            guard try patchBackground(in: &manifest, manifestDirectory: manifestDirectory) else {
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
        guard Self.hasServiceWorkerOnlyBackground(manifest),
              var background = manifest[ManifestKey.background] as? [String: Any],
              let serviceWorkerPath = background[ManifestKey.serviceWorker] as? String else {
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

    /// Finds the extra files a webpack-built service worker loads with `importScripts`.
    ///
    /// webpack names them `<number>.<worker file name>` and puts them next to the worker, so
    /// `background.js` comes with files like `719.background.js`. We can't tell which ones the worker
    /// will ask for, so this returns all of them, sorted by number, as paths from the extension folder.
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
    /// which `loadableExtensionURL(for:)` unpacks first.
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

    /// Builds the HTML of the background page.
    ///
    /// For a classic worker, the page loads the `importScripts` shim, then the extra files, then the
    /// extension's script. The extension's script is deferred, so it runs only after the others.
    /// A module worker loads its extra files itself, so its page loads only the extension's script.
    ///
    /// Paths start with `/` so they resolve from the extension folder, like the manifest's path does.
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

//
//  WebExtensionBackgroundPagePatcherTests.swift
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

import XCTest
import WebKit
import ZIPFoundation
@testable import WebExtensions

final class WebExtensionBackgroundPagePatcherTests: XCTestCase {

    private var temporaryDirectory: URL!
    private var patcher: WebExtensionBackgroundPagePatcher!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WebExtensionBackgroundPagePatcherTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        patcher = WebExtensionBackgroundPagePatcher()
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
        patcher = nil
        try super.tearDownWithError()
    }

    // MARK: - Patching

    func testWhenManifestDeclaresModuleServiceWorker_ThenBackgroundPageIsGeneratedAndManifestIsRewritten() throws {
        let extensionDirectory = try makeExtensionDirectory(manifest: """
        {
            "manifest_version": 3,
            "name": "Test Extension",
            "version": "1.2.3",
            "permissions": ["storage", "nativeMessaging"],
            "background": {
                "service_worker": "background/background.js",
                "type": "module"
            }
        }
        """)

        XCTAssertTrue(patcher.patchIfNeeded(installedExtensionURL: extensionDirectory))

        let background = try backgroundSection(in: extensionDirectory)
        XCTAssertEqual(background["page"] as? String, WebExtensionBackgroundPagePatcher.backgroundPageFilename)
        XCTAssertNil(background["service_worker"])
        XCTAssertNil(background["type"])

        // Other keys survive the rewrite.
        let manifest = try loadManifest(in: extensionDirectory)
        XCTAssertEqual(manifest["manifest_version"] as? Int, 3)
        XCTAssertEqual(manifest["name"] as? String, "Test Extension")
        XCTAssertEqual(manifest["version"] as? String, "1.2.3")
        XCTAssertEqual(manifest["permissions"] as? [String], ["storage", "nativeMessaging"])

        let backgroundPage = try loadBackgroundPage(in: extensionDirectory)
        XCTAssertTrue(backgroundPage.contains("type=\"module\""), backgroundPage)
        XCTAssertTrue(backgroundPage.contains("src=\"/background/background.js\""), backgroundPage)
    }

    func testWhenManifestDeclaresServiceWorkerWithoutType_ThenBackgroundPageUsesClassicScript() throws {
        let extensionDirectory = try makeExtensionDirectory(manifest: """
        {
            "manifest_version": 3,
            "background": {
                "service_worker": "worker.js"
            }
        }
        """)

        XCTAssertTrue(patcher.patchIfNeeded(installedExtensionURL: extensionDirectory))

        let background = try backgroundSection(in: extensionDirectory)
        XCTAssertEqual(background["page"] as? String, WebExtensionBackgroundPagePatcher.backgroundPageFilename)
        XCTAssertNil(background["service_worker"])

        let backgroundPage = try loadBackgroundPage(in: extensionDirectory)
        XCTAssertFalse(backgroundPage.contains("type="), backgroundPage)
        XCTAssertTrue(backgroundPage.contains("src=\"/worker.js\""), backgroundPage)
    }

    func testWhenManifestIsPatchedTwice_ThenSecondRunChangesNothing() throws {
        let extensionDirectory = try makeExtensionDirectory(manifest: """
        {
            "manifest_version": 3,
            "background": {
                "service_worker": "background/background.js",
                "type": "module"
            }
        }
        """)

        XCTAssertTrue(patcher.patchIfNeeded(installedExtensionURL: extensionDirectory))

        let patchedManifest = try Data(contentsOf: manifestURL(in: extensionDirectory))
        let patchedPage = try Data(contentsOf: backgroundPageURL(in: extensionDirectory))

        XCTAssertFalse(patcher.patchIfNeeded(installedExtensionURL: extensionDirectory))

        XCTAssertEqual(try Data(contentsOf: manifestURL(in: extensionDirectory)), patchedManifest)
        XCTAssertEqual(try Data(contentsOf: backgroundPageURL(in: extensionDirectory)), patchedPage)
    }

    // MARK: - importScripts Shim And Webpack Chunks

    func testWhenClassicWorkerHasChunkFiles_ThenShimAndChunksArePreloadedInChunkIdOrder() throws {
        let extensionDirectory = try makeExtensionDirectory(manifest: """
        {
            "manifest_version": 3,
            "background": {
                "service_worker": "background.js"
            }
        }
        """)
        try writeFile(named: "719.background.js", in: extensionDirectory)
        try writeFile(named: "12.background.js", in: extensionDirectory)
        try writeFile(named: "719.background.js.map", in: extensionDirectory)
        try writeFile(named: "vendor.js", in: extensionDirectory)

        XCTAssertTrue(patcher.patchIfNeeded(installedExtensionURL: extensionDirectory))

        let backgroundPage = try loadBackgroundPage(in: extensionDirectory)
        assertScriptSources(["/\(WebExtensionImportScriptsShim.filename)",
                             "/12.background.js",
                             "/719.background.js",
                             "/background.js"],
                            appearInOrderIn: backgroundPage)
        XCTAssertFalse(backgroundPage.contains("719.background.js.map"), backgroundPage)
        XCTAssertFalse(backgroundPage.contains("vendor.js"), backgroundPage)

        XCTAssertEqual(try loadImportScriptsShim(in: extensionDirectory), WebExtensionImportScriptsShim.source)
    }

    func testWhenClassicWorkerHasNoChunkFiles_ThenShimIsStillPreloaded() throws {
        let extensionDirectory = try makeExtensionDirectory(manifest: """
        {
            "manifest_version": 3,
            "background": {
                "service_worker": "background.js"
            }
        }
        """)

        XCTAssertTrue(patcher.patchIfNeeded(installedExtensionURL: extensionDirectory))

        let backgroundPage = try loadBackgroundPage(in: extensionDirectory)
        assertScriptSources(["/\(WebExtensionImportScriptsShim.filename)",
                             "/background.js"],
                            appearInOrderIn: backgroundPage)
        XCTAssertEqual(backgroundPage.components(separatedBy: "<script").count - 1, 2, backgroundPage)
        XCTAssertEqual(try loadImportScriptsShim(in: extensionDirectory), WebExtensionImportScriptsShim.source)
    }

    func testWhenWorkerIsAModule_ThenNeitherShimNorChunksArePreloaded() throws {
        let extensionDirectory = try makeExtensionDirectory(manifest: """
        {
            "manifest_version": 3,
            "background": {
                "service_worker": "background.js",
                "type": "module"
            }
        }
        """)
        try writeFile(named: "719.background.js", in: extensionDirectory)

        XCTAssertTrue(patcher.patchIfNeeded(installedExtensionURL: extensionDirectory))

        let backgroundPage = try loadBackgroundPage(in: extensionDirectory)
        XCTAssertFalse(backgroundPage.contains(WebExtensionImportScriptsShim.filename), backgroundPage)
        XCTAssertFalse(backgroundPage.contains("719.background.js"), backgroundPage)
        XCTAssertFalse(FileManager.default.fileExists(atPath: importScriptsShimURL(in: extensionDirectory).path))
    }

    func testWhenWorkerIsInASubdirectory_ThenChunksArePreloadedFromThatSubdirectory() throws {
        let extensionDirectory = try makeExtensionDirectory(manifest: """
        {
            "manifest_version": 3,
            "background": {
                "service_worker": "background/worker.js"
            }
        }
        """)
        let workerDirectory = extensionDirectory.appendingPathComponent("background")
        try FileManager.default.createDirectory(at: workerDirectory, withIntermediateDirectories: true)
        try writeFile(named: "3.worker.js", in: workerDirectory)

        XCTAssertTrue(patcher.patchIfNeeded(installedExtensionURL: extensionDirectory))

        let backgroundPage = try loadBackgroundPage(in: extensionDirectory)
        assertScriptSources(["/\(WebExtensionImportScriptsShim.filename)",
                             "/background/3.worker.js",
                             "/background/worker.js"],
                            appearInOrderIn: backgroundPage)

        // The shim lives next to the manifest, not next to the worker.
        XCTAssertEqual(try loadImportScriptsShim(in: extensionDirectory), WebExtensionImportScriptsShim.source)
    }

    // MARK: - Manifests Left Untouched

    func testWhenManifestDeclaresBackgroundScripts_ThenManifestIsUntouched() throws {
        try assertManifestIsUntouched("""
        {
            "manifest_version": 3,
            "background": {
                "service_worker": "background/index.js",
                "scripts": ["background/index.js"],
                "persistent": false
            }
        }
        """)
    }

    func testWhenManifestDeclaresBackgroundPage_ThenManifestIsUntouched() throws {
        try assertManifestIsUntouched("""
        {
            "manifest_version": 3,
            "background": {
                "service_worker": "background/index.js",
                "page": "background/index.html"
            }
        }
        """)
    }

    func testWhenManifestIsADuckDuckGoExtensionWithServiceWorker_ThenManifestIsUntouched() throws {
        try assertManifestIsUntouched("""
        {
            "manifest_version": 3,
            "name": "Content Blocker",
            "browser_specific_settings": {
                "duckduckgo": { "id": "com.duckduckgo.content-blocker-extension" }
            },
            "background": {
                "service_worker": "background.js",
                "type": "module"
            }
        }
        """)
    }

    func testWhenManifestHasNoBackgroundKey_ThenManifestIsUntouched() throws {
        try assertManifestIsUntouched("""
        {
            "manifest_version": 3,
            "name": "Content Script Only"
        }
        """)
    }

    // MARK: - Loadable Copies

    private let serviceWorkerManifest = """
    { "manifest_version": 3, "name": "Copied", "version": "1.0", "background": { "service_worker": "background.js" } }
    """

    private let duckDuckGoManifest = """
    { "manifest_version": 3, "name": "Ours", "version": "1.0", "background": { "service_worker": "background.js" },
      "browser_specific_settings": { "duckduckgo": { "id": "com.duckduckgo.test" } } }
    """

    func testWhenArchiveDeclaresServiceWorker_ThenARewrittenCopyIsLoadedAndTheArchiveIsUntouched() throws {
        let archiveURL = try makeArchive(files: ["manifest.json": serviceWorkerManifest, "background.js": "1;"])
        let archiveData = try Data(contentsOf: archiveURL)

        let loadableURL = patcher.loadableExtensionURL(for: archiveURL, installFolder: installFolder(of: archiveURL))

        XCTAssertEqual(loadableURL.standardizedFileURL, loadableFolder(of: archiveURL).standardizedFileURL)
        XCTAssertEqual(try backgroundSection(in: loadableURL)["page"] as? String, WebExtensionBackgroundPagePatcher.backgroundPageFilename)
        XCTAssertTrue(FileManager.default.fileExists(atPath: loadableURL.appendingPathComponent("background.js").path))
        XCTAssertEqual(try Data(contentsOf: archiveURL), archiveData)
    }

    func testWhenArchiveWrapsItsFilesInAFolder_ThenThatFolderOfTheCopyIsLoaded() throws {
        let archiveURL = try makeArchive(files: ["bitwarden/manifest.json": serviceWorkerManifest, "bitwarden/background.js": "1;"])

        let loadableURL = patcher.loadableExtensionURL(for: archiveURL, installFolder: installFolder(of: archiveURL))

        XCTAssertEqual(loadableURL.standardizedFileURL,
                       loadableFolder(of: archiveURL).appendingPathComponent("bitwarden").standardizedFileURL)
        XCTAssertEqual(try backgroundSection(in: loadableURL)["page"] as? String, WebExtensionBackgroundPagePatcher.backgroundPageFilename)
    }

    func testWhenFolderDeclaresServiceWorker_ThenARewrittenCopyIsLoadedAndTheFolderIsUntouched() throws {
        let installFolder = try makeInstallFolder()
        let extensionDirectory = installFolder.appendingPathComponent("extension")
        try writeFiles(["manifest.json": serviceWorkerManifest, "background.js": "1;"], in: extensionDirectory)

        let loadableURL = patcher.loadableExtensionURL(for: extensionDirectory, installFolder: installFolder)

        XCTAssertEqual(loadableURL.standardizedFileURL,
                       installFolder.appendingPathComponent(WebExtensionBackgroundPagePatcher.loadableFolderName).standardizedFileURL)
        XCTAssertEqual(try backgroundSection(in: loadableURL)["page"] as? String, WebExtensionBackgroundPagePatcher.backgroundPageFilename)
        XCTAssertEqual(try backgroundSection(in: extensionDirectory)["service_worker"] as? String, "background.js")
        XCTAssertFalse(FileManager.default.fileExists(atPath: backgroundPageURL(in: extensionDirectory).path))
    }

    func testWhenFolderIsTheInstallFolder_ThenTheCopyLeavesItselfOut() throws {
        let installFolder = try makeInstallFolder()
        try writeFiles(["manifest.json": serviceWorkerManifest, "background.js": "1;"], in: installFolder)

        let loadableURL = patcher.loadableExtensionURL(for: installFolder, installFolder: installFolder)
        _ = patcher.loadableExtensionURL(for: installFolder, installFolder: installFolder)

        let copiedItems = try FileManager.default.contentsOfDirectory(atPath: loadableURL.path)
        XCTAssertFalse(copiedItems.contains(WebExtensionBackgroundPagePatcher.loadableFolderName))
        XCTAssertEqual(try backgroundSection(in: installFolder)["service_worker"] as? String, "background.js")
    }

    func testWhenExtensionIsOneOfOurs_ThenItIsLoadedAsIs() throws {
        let archiveURL = try makeArchive(files: ["manifest.json": duckDuckGoManifest])

        XCTAssertEqual(patcher.loadableExtensionURL(for: archiveURL, installFolder: installFolder(of: archiveURL)), archiveURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: loadableFolder(of: archiveURL).path))
    }

    func testWhenExtensionNeedsNoRewrite_ThenItIsLoadedAsIsAndAnOldCopyIsRemoved() throws {
        let archiveURL = try makeArchive(files: ["manifest.json": """
        { "manifest_version": 3, "name": "Page", "version": "1.0", "background": { "page": "background.html" } }
        """])
        try FileManager.default.createDirectory(at: loadableFolder(of: archiveURL), withIntermediateDirectories: true)

        XCTAssertEqual(patcher.loadableExtensionURL(for: archiveURL, installFolder: installFolder(of: archiveURL)), archiveURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: loadableFolder(of: archiveURL).path))
    }

    func testWhenInstallationIsUnchanged_ThenTheCopyIsReused() throws {
        let archiveURL = try makeArchive(files: ["manifest.json": serviceWorkerManifest, "background.js": "1;"])
        let loadableURL = patcher.loadableExtensionURL(for: archiveURL, installFolder: installFolder(of: archiveURL))
        let markerURL = loadableURL.appendingPathComponent("marker")
        try Data().write(to: markerURL)

        XCTAssertEqual(patcher.loadableExtensionURL(for: archiveURL, installFolder: installFolder(of: archiveURL)), loadableURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: markerURL.path))
    }

    func testWhenInstallationChanges_ThenItIsCopiedAgain() throws {
        let archiveURL = try makeArchive(files: ["manifest.json": serviceWorkerManifest, "background.js": "1;"])
        let loadableURL = patcher.loadableExtensionURL(for: archiveURL, installFolder: installFolder(of: archiveURL))
        let markerURL = loadableURL.appendingPathComponent("marker")
        try Data().write(to: markerURL)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: archiveURL.path)

        XCTAssertEqual(patcher.loadableExtensionURL(for: archiveURL, installFolder: installFolder(of: archiveURL)), loadableURL)

        XCTAssertFalse(FileManager.default.fileExists(atPath: markerURL.path))
        XCTAssertEqual(try backgroundSection(in: loadableURL)["page"] as? String, WebExtensionBackgroundPagePatcher.backgroundPageFilename)
    }

    @available(macOS 15.4, iOS 18.4, *)
    func testWhenAFolderInstallHasACopy_ThenTheInstallationIsStillResolved() throws {
        let installFolder = try makeInstallFolder()
        let extensionDirectory = installFolder.appendingPathComponent("extension")
        try writeFiles(["manifest.json": serviceWorkerManifest, "background.js": "1;"], in: extensionDirectory)
        _ = patcher.loadableExtensionURL(for: extensionDirectory, installFolder: installFolder)
        let storage = ExtensionsDirectoryStorage(extensionsDirectory: installFolder.deletingLastPathComponent())

        let resolvedURL = storage.resolveInstalledExtension(identifier: installFolder.lastPathComponent)

        XCTAssertEqual(resolvedURL?.standardizedFileURL, extensionDirectory.standardizedFileURL)
    }

    func testWhenAnInstallationHasAWorkerWrapper_ThenTheCopyIsRebuiltAsABackgroundPage() throws {
        for isArchive in [false, true] {
            for isModule in [false, true] {
                let manifest = """
                { "manifest_version": 3, "name": "Installed Extension", "version": "1.0",
                  "background": { "service_worker": "background.js"\(isModule ? ", \"type\": \"module\"" : "") } }
                """
                let installedURL: URL
                let sourceURL: URL
                if isArchive {
                    installedURL = try makeArchive(files: ["manifest.json": manifest, "background.js": "1;"])
                    sourceURL = installedURL
                } else {
                    installedURL = try makeExtensionDirectory(manifest: manifest)
                    try writeFile(named: "background.js", in: installedURL)
                    sourceURL = manifestURL(in: installedURL)
                }
                let installFolder = isArchive ? installFolder(of: installedURL) : installedURL
                let loadableURL = installFolder.appendingPathComponent(WebExtensionBackgroundPagePatcher.loadableFolderName, isDirectory: true)
                try writeFiles([
                    "manifest.json": """
                    { "manifest_version": 3, "background": { "service_worker": "ddg-service-worker.js" } }
                    """,
                    "ddg-service-worker.js": "importScripts('/background.js');",
                    "ddg-worker-port-probe.js": "// obsolete worker diagnostics"
                ], in: loadableURL)
                let sourceDate = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: sourceURL.path)[.modificationDate] as? Date)
                let workerStamp = "\(sourceDate.timeIntervalSinceReferenceDate)-service-worker-compatibility-v1-port-probe-v3"
                try workerStamp.write(to: loadableURL.appendingPathComponent(".ddg-source-date"), atomically: true, encoding: .utf8)
                let originalManifest = try Data(contentsOf: sourceURL)

                XCTAssertEqual(patcher.loadableExtensionURL(for: installedURL, installFolder: installFolder), loadableURL)

                let background = try backgroundSection(in: loadableURL)
                XCTAssertEqual(background["page"] as? String, WebExtensionBackgroundPagePatcher.backgroundPageFilename)
                XCTAssertNil(background["service_worker"])
                XCTAssertNil(background["type"])
                XCTAssertEqual(try loadManifest(in: loadableURL)["manifest_version"] as? Int, 3)
                let page = try loadBackgroundPage(in: loadableURL)
                XCTAssertTrue(page.contains("src=\"/background.js\""))
                XCTAssertEqual(page.contains("type=\"module\""), isModule)
                XCTAssertFalse(FileManager.default.fileExists(atPath: loadableURL.appendingPathComponent("ddg-service-worker.js").path))
                XCTAssertFalse(FileManager.default.fileExists(atPath: loadableURL.appendingPathComponent("ddg-worker-port-probe.js").path))
                XCTAssertEqual(try Data(contentsOf: sourceURL), originalManifest)
                XCTAssertEqual(patcher.loadableExtensionURL(for: installedURL, installFolder: installFolder), loadableURL)
                XCTAssertEqual(try backgroundSection(in: loadableURL)["page"] as? String,
                               WebExtensionBackgroundPagePatcher.backgroundPageFilename)
            }
        }
    }

    @available(macOS 15.4, iOS 18.4, *)
    @MainActor
    func testClassicBackgroundPageImportsScriptsAndConstructsAWebSocket() async throws {
        try await assertBackgroundPageSupportsWebSockets(isModule: false)
    }

    @available(macOS 15.4, iOS 18.4, *)
    @MainActor
    func testModuleBackgroundPageImportsScriptsAndConstructsAWebSocket() async throws {
        try await assertBackgroundPageSupportsWebSockets(isModule: true)
    }

    // MARK: - Helpers

    @available(macOS 15.4, iOS 18.4, *)
    @MainActor
    private func assertBackgroundPageSupportsWebSockets(isModule: Bool) async throws {
        let directory = try makeExtensionDirectory(manifest: """
        { "manifest_version": 3, "name": "Background Page Test", "version": "1.0",
          "permissions": ["nativeMessaging"],
          "background": { "service_worker": "background.js"\(isModule ? ", \"type\": \"module\"" : "") } }
        """)
        let importLine = isModule ? "import './123.background.js';\n" : "importScripts('123.background.js');\n"
        try writeFiles([
            "123.background.js": "globalThis.backgroundImported = true;",
            "background.js": importLine + """
            (async function() {
                const api = globalThis.chrome || globalThis.browser;
                const socket = new WebSocket("wss://127.0.0.1:65534");
                const report = {
                    document: typeof document,
                    imported: globalThis.backgroundImported === true,
                    readyState: socket.readyState
                };
                socket.close();
                await api.runtime.sendNativeMessage("background.page.test", report);
            })();
            """
        ], in: directory)
        XCTAssertTrue(patcher.patchIfNeeded(installedExtensionURL: directory))
        let bundle = try await WKWebExtension.makeCopyingErrors(at: directory)
        let context = WKWebExtensionContext(for: bundle)
        context.setPermissionStatus(.grantedExplicitly, for: .nativeMessaging)
        let constructed = expectation(description: "Background page executes after WebSocket construction")
        let delegate = BackgroundPageTestDelegate { message in
            let report = message as? [String: Any]
            XCTAssertEqual(report?["document"] as? String, "object")
            XCTAssertEqual(report?["imported"] as? Bool, true)
            XCTAssertEqual(report?["readyState"] as? Int, 0)
            constructed.fulfill()
        }
        let controller = WKWebExtensionController(configuration: .nonPersistent())
        controller.delegate = delegate
        try controller.loadCopyingErrors(context)
        defer { try? controller.unloadCopyingErrors(context) }
        await fulfillment(of: [constructed], timeout: 10)
        withExtendedLifetime(delegate) {}
    }

    private func assertManifestIsUntouched(_ manifest: String,
                                           file: StaticString = #filePath,
                                           line: UInt = #line) throws {
        let extensionDirectory = try makeExtensionDirectory(manifest: manifest)
        let originalManifest = try Data(contentsOf: manifestURL(in: extensionDirectory))

        XCTAssertFalse(patcher.patchIfNeeded(installedExtensionURL: extensionDirectory), file: file, line: line)

        XCTAssertEqual(try Data(contentsOf: manifestURL(in: extensionDirectory)),
                       originalManifest,
                       file: file,
                       line: line)
        XCTAssertFalse(FileManager.default.fileExists(atPath: backgroundPageURL(in: extensionDirectory).path),
                       file: file,
                       line: line)
        XCTAssertFalse(FileManager.default.fileExists(atPath: importScriptsShimURL(in: extensionDirectory).path),
                       file: file,
                       line: line)
    }

    /// Asserts that `<script src="…">` tags for `sources` appear in the page, in the given order.
    private func assertScriptSources(_ sources: [String],
                                     appearInOrderIn backgroundPage: String,
                                     file: StaticString = #filePath,
                                     line: UInt = #line) {
        var searchStart = backgroundPage.startIndex
        for source in sources {
            guard let range = backgroundPage.range(of: "src=\"\(source)\"", range: searchStart..<backgroundPage.endIndex) else {
                XCTFail("Expected 'src=\"\(source)\"' after position \(backgroundPage.distance(from: backgroundPage.startIndex, to: searchStart)) in:\n\(backgroundPage)",
                        file: file,
                        line: line)
                return
            }
            searchStart = range.upperBound
        }
    }

    private func makeInstallFolder() throws -> URL {
        let installFolder = temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: installFolder, withIntermediateDirectories: true)
        return installFolder
    }

    private func writeFiles(_ files: [String: String], in directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, contents) in files {
            try Data(contents.utf8).write(to: directory.appendingPathComponent(name))
        }
    }

    /// An archive in its own install folder, like the ones the Chrome Web Store flow stores.
    private func makeArchive(files: [String: String]) throws -> URL {
        let archiveURL = try makeInstallFolder().appendingPathComponent("extension.zip")
        let archive = try Archive(url: archiveURL, accessMode: .create)
        for (path, contents) in files.sorted(by: { $0.key < $1.key }) {
            let data = Data(contents.utf8)
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count)) { position, size in
                data.subdata(in: Int(position)..<Int(position) + size)
            }
        }
        return archiveURL
    }

    private func installFolder(of archiveURL: URL) -> URL {
        archiveURL.deletingLastPathComponent()
    }

    private func loadableFolder(of archiveURL: URL) -> URL {
        installFolder(of: archiveURL).appendingPathComponent(WebExtensionBackgroundPagePatcher.loadableFolderName)
    }

    private func makeExtensionDirectory(manifest: String) throws -> URL {
        let directory = temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try write(manifest: manifest, to: directory)
        return directory
    }

    private func write(manifest: String, to directory: URL) throws {
        try manifest.write(to: directory.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
    }

    private func writeFile(named filename: String, in directory: URL) throws {
        try "// \(filename)".write(to: directory.appendingPathComponent(filename), atomically: true, encoding: .utf8)
    }

    private func manifestURL(in directory: URL) -> URL {
        directory.appendingPathComponent("manifest.json")
    }

    private func backgroundPageURL(in directory: URL) -> URL {
        directory.appendingPathComponent(WebExtensionBackgroundPagePatcher.backgroundPageFilename)
    }

    private func loadManifest(in directory: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: manifestURL(in: directory))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func backgroundSection(in directory: URL) throws -> [String: Any] {
        try XCTUnwrap(try loadManifest(in: directory)["background"] as? [String: Any])
    }

    private func loadBackgroundPage(in directory: URL) throws -> String {
        try String(contentsOf: backgroundPageURL(in: directory), encoding: .utf8)
    }

    private func importScriptsShimURL(in directory: URL) -> URL {
        directory.appendingPathComponent(WebExtensionImportScriptsShim.filename)
    }

    private func loadImportScriptsShim(in directory: URL) throws -> String {
        try String(contentsOf: importScriptsShimURL(in: directory), encoding: .utf8)
    }
}

@available(macOS 15.4, iOS 18.4, *)
@MainActor
private final class BackgroundPageTestDelegate: NSObject, WKWebExtensionControllerDelegate {
    let receive: (Any) -> Void

    init(receive: @escaping (Any) -> Void) {
        self.receive = receive
    }

    func webExtensionController(_ controller: WKWebExtensionController,
                                sendMessage message: Any,
                                toApplicationWithIdentifier applicationIdentifier: String?,
                                for extensionContext: WKWebExtensionContext) async throws -> Any? {
        receive(message)
        return nil
    }
}

/// The default storage behavior over a given extensions directory.
@available(macOS 15.4, iOS 18.4, *)
private final class ExtensionsDirectoryStorage: WebExtensionStorageProviding {
    let fileManager = FileManager.default
    let extensionsDirectory: URL

    init(extensionsDirectory: URL) {
        self.extensionsDirectory = extensionsDirectory
    }
}

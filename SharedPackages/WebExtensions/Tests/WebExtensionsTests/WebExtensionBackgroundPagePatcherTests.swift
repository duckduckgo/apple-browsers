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

    // MARK: - Known Public Keys

    func testWhenKnownExtensionHasNoKey_ThenLocalizedNameResolvesTheKey() throws {
        // No `short_name`, so only the localized name can match.
        let extensionDirectory = try makeExtensionDirectory(manifest: """
        {
            "manifest_version": 3,
            "name": "__MSG_extName__",
            "default_locale": "en",
            "background": {
                "page": "background/index.html"
            }
        }
        """)
        try writeMessages("""
        {
            "extName": { "message": "Bitwarden", "description": "Extension name" }
        }
        """, locale: "en", in: extensionDirectory)

        XCTAssertTrue(patcher.patchIfNeeded(installedExtensionURL: extensionDirectory))

        let manifest = try loadManifest(in: extensionDirectory)
        XCTAssertEqual(manifest["key"] as? String, WebExtensionKnownPublicKeys.publicKey(forDisplayName: "Bitwarden"))
    }

    func testWhenLocalizedNameIsTheStoreListingTitle_ThenShortNameStillResolvesTheKey() throws {
        // Bitwarden's own shape: `extName` is the store listing, `short_name` the product name.
        let extensionDirectory = try makeExtensionDirectory(manifest: """
        {
            "manifest_version": 3,
            "name": "__MSG_extName__",
            "short_name": "Bitwarden",
            "default_locale": "en"
        }
        """)
        try writeMessages("""
        {
            "extName": { "message": "Bitwarden Password Manager" }
        }
        """, locale: "en", in: extensionDirectory)

        XCTAssertTrue(patcher.patchIfNeeded(installedExtensionURL: extensionDirectory))

        let manifest = try loadManifest(in: extensionDirectory)
        XCTAssertEqual(manifest["key"] as? String, WebExtensionKnownPublicKeys.publicKey(forDisplayName: "Bitwarden"))
    }

    func testWhenNoCandidateNameIsKnown_ThenNoKeyIsInserted() throws {
        let extensionDirectory = try makeExtensionDirectory(manifest: """
        {
            "manifest_version": 3,
            "name": "__MSG_extName__",
            "short_name": "Bitwarden Password Manager",
            "default_locale": "en"
        }
        """)
        try writeMessages("""
        {
            "extName": { "message": "Bitwarden Password Manager" }
        }
        """, locale: "en", in: extensionDirectory)
        let originalManifest = try Data(contentsOf: manifestURL(in: extensionDirectory))

        XCTAssertFalse(patcher.patchIfNeeded(installedExtensionURL: extensionDirectory))

        XCTAssertEqual(try Data(contentsOf: manifestURL(in: extensionDirectory)), originalManifest)
    }

    func testWhenKnownExtensionHasNoKeyAndNoLocales_ThenShortNameResolvesTheKey() throws {
        let extensionDirectory = try makeExtensionDirectory(manifest: """
        {
            "manifest_version": 3,
            "name": "__MSG_extName__",
            "short_name": "1Password"
        }
        """)

        XCTAssertTrue(patcher.patchIfNeeded(installedExtensionURL: extensionDirectory))

        let manifest = try loadManifest(in: extensionDirectory)
        XCTAssertEqual(manifest["key"] as? String, WebExtensionKnownPublicKeys.publicKey(forDisplayName: "1Password"))
    }

    func testWhenKnownExtensionAlreadyHasKey_ThenManifestIsUntouched() throws {
        let extensionDirectory = try makeExtensionDirectory(manifest: """
        {
            "manifest_version": 3,
            "name": "__MSG_extName__",
            "default_locale": "en",
            "key": "AN-EXISTING-KEY"
        }
        """)
        try writeMessages("""
        {
            "extName": { "message": "Bitwarden" }
        }
        """, locale: "en", in: extensionDirectory)
        let originalManifest = try Data(contentsOf: manifestURL(in: extensionDirectory))

        XCTAssertFalse(patcher.patchIfNeeded(installedExtensionURL: extensionDirectory))

        XCTAssertEqual(try Data(contentsOf: manifestURL(in: extensionDirectory)), originalManifest)
    }

    func testWhenExtensionIsUnknown_ThenNoKeyIsInserted() throws {
        let extensionDirectory = try makeExtensionDirectory(manifest: """
        {
            "manifest_version": 3,
            "name": "Some Other Password Manager",
            "short_name": "Other"
        }
        """)
        let originalManifest = try Data(contentsOf: manifestURL(in: extensionDirectory))

        XCTAssertFalse(patcher.patchIfNeeded(installedExtensionURL: extensionDirectory))

        XCTAssertEqual(try Data(contentsOf: manifestURL(in: extensionDirectory)), originalManifest)
    }

    func testWhenKeyIsInsertedTwice_ThenSecondRunChangesNothing() throws {
        let extensionDirectory = try makeExtensionDirectory(manifest: """
        {
            "manifest_version": 3,
            "name": "Bitwarden"
        }
        """)

        XCTAssertTrue(patcher.patchIfNeeded(installedExtensionURL: extensionDirectory))
        let patchedManifest = try Data(contentsOf: manifestURL(in: extensionDirectory))

        XCTAssertFalse(patcher.patchIfNeeded(installedExtensionURL: extensionDirectory))

        XCTAssertEqual(try Data(contentsOf: manifestURL(in: extensionDirectory)), patchedManifest)
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

    func testWhenManifestHasNoBackgroundKey_ThenManifestIsUntouched() throws {
        try assertManifestIsUntouched("""
        {
            "manifest_version": 3,
            "name": "Content Script Only"
        }
        """)
    }

    // MARK: - Helpers

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

    private func writeMessages(_ messages: String, locale: String, in directory: URL) throws {
        let localeDirectory = directory
            .appendingPathComponent("_locales")
            .appendingPathComponent(locale)
        try FileManager.default.createDirectory(at: localeDirectory, withIntermediateDirectories: true)
        try messages.write(to: localeDirectory.appendingPathComponent("messages.json"), atomically: true, encoding: .utf8)
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

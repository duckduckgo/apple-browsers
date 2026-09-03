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
        assertStubScriptIsLoadedFirst(in: backgroundPage, beforeScriptAt: "/background/background.js")
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
        assertStubScriptIsLoadedFirst(in: backgroundPage, beforeScriptAt: "/worker.js")
    }

    func testWhenManifestIsInWrappedSubfolder_ThenManifestIsFoundAndPatched() throws {
        let installedDirectory = temporaryDirectory.appendingPathComponent("installed")
        let wrappedDirectory = installedDirectory.appendingPathComponent("1password-extension")
        try FileManager.default.createDirectory(at: wrappedDirectory, withIntermediateDirectories: true)
        try write(manifest: """
        {
            "manifest_version": 3,
            "background": {
                "service_worker": "background/background.js",
                "type": "module"
            }
        }
        """, to: wrappedDirectory)

        XCTAssertTrue(patcher.patchIfNeeded(installedExtensionURL: installedDirectory))

        let background = try backgroundSection(in: wrappedDirectory)
        XCTAssertEqual(background["page"] as? String, WebExtensionBackgroundPagePatcher.backgroundPageFilename)
        XCTAssertNil(background["service_worker"])

        let backgroundPage = try loadBackgroundPage(in: wrappedDirectory)
        XCTAssertTrue(backgroundPage.contains("src=\"/background/background.js\""), backgroundPage)
        assertStubScriptIsLoadedFirst(in: backgroundPage, beforeScriptAt: "/background/background.js")

        XCTAssertEqual(try loadStubScript(in: wrappedDirectory), WebExtensionAPIStubScript.source)
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

        // A rewritten stub script would be overwritten with identical bytes, so also check that the
        // patcher does not touch the file at all on a second run.
        let stubScriptModificationDate = try modificationDate(of: stubScriptURL(in: extensionDirectory))

        XCTAssertFalse(patcher.patchIfNeeded(installedExtensionURL: extensionDirectory))

        XCTAssertEqual(try Data(contentsOf: manifestURL(in: extensionDirectory)), patchedManifest)
        XCTAssertEqual(try Data(contentsOf: backgroundPageURL(in: extensionDirectory)), patchedPage)
        XCTAssertEqual(try modificationDate(of: stubScriptURL(in: extensionDirectory)), stubScriptModificationDate)
    }

    // MARK: - API Stub Script

    func testWhenManifestIsPatched_ThenStubScriptIsWrittenNextToManifest() throws {
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

        XCTAssertEqual(try loadStubScript(in: extensionDirectory), WebExtensionAPIStubScript.source)
    }

    func testWhenManifestIsPatched_ThenStubScriptIsReferencedBeforeTheWorkerScript() throws {
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

        let backgroundPage = try loadBackgroundPage(in: extensionDirectory)
        XCTAssertTrue(backgroundPage.contains("<script src=\"/ddg-api-stubs.js\"></script>"), backgroundPage)
        assertStubScriptIsLoadedFirst(in: backgroundPage, beforeScriptAt: "/background/background.js")
    }

    func testWhenManifestIsNotPatched_ThenStubScriptIsNotWritten() throws {
        let extensionDirectory = try makeExtensionDirectory(manifest: """
        {
            "manifest_version": 3,
            "background": {
                "page": "background/index.html"
            }
        }
        """)

        XCTAssertFalse(patcher.patchIfNeeded(installedExtensionURL: extensionDirectory))

        XCTAssertFalse(FileManager.default.fileExists(atPath: stubScriptURL(in: extensionDirectory).path))
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
        XCTAssertFalse(FileManager.default.fileExists(atPath: stubScriptURL(in: extensionDirectory).path),
                       file: file,
                       line: line)
    }

    private func assertStubScriptIsLoadedFirst(in backgroundPage: String,
                                               beforeScriptAt scriptPath: String,
                                               file: StaticString = #filePath,
                                               line: UInt = #line) {
        guard let stubRange = backgroundPage.range(of: "src=\"/\(WebExtensionAPIStubScript.filename)\""),
              let scriptRange = backgroundPage.range(of: "src=\"\(scriptPath)\"") else {
            XCTFail("Expected both script tags in:\n\(backgroundPage)", file: file, line: line)
            return
        }
        XCTAssertTrue(stubRange.lowerBound < scriptRange.lowerBound, backgroundPage, file: file, line: line)
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

    private func stubScriptURL(in directory: URL) -> URL {
        directory.appendingPathComponent(WebExtensionAPIStubScript.filename)
    }

    private func loadBackgroundPage(in directory: URL) throws -> String {
        try String(contentsOf: backgroundPageURL(in: directory), encoding: .utf8)
    }

    private func loadStubScript(in directory: URL) throws -> String {
        try String(contentsOf: stubScriptURL(in: directory), encoding: .utf8)
    }

    private func modificationDate(of url: URL) throws -> Date {
        try XCTUnwrap(try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)
    }
}

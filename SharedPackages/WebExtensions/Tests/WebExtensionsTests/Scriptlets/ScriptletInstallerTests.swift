//
//  ScriptletInstallerTests.swift
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

final class ScriptletInstallerTests: XCTestCase {

    var tempDirectory: URL!
    var installer: ScriptletInstaller!
    var cacheRootDirectory: URL!
    var installationDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        cacheRootDirectory = tempDirectory.appendingPathComponent("cache")
        installationDirectory = tempDirectory.appendingPathComponent("install")

        try? FileManager.default.createDirectory(at: cacheRootDirectory, withIntermediateDirectories: true)

        installer = ScriptletInstaller()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        installer = nil
        installationDirectory = nil
        cacheRootDirectory = nil
        tempDirectory = nil
        super.tearDown()
    }

    func testWhenScriptletsInstalledThenFilesAreCopiedToExtensionDirectory() async throws {
        let scriptlets = [
            Scriptlet(path: "test1.js", relativeCachedPath: "ext/1.0/test1.js"),
            Scriptlet(path: "test2.js", relativeCachedPath: "ext/1.0/test2.js")
        ]

        for scriptlet in scriptlets {
            try writeCacheFile(at: scriptlet.relativeCachedPath, content: "content")
        }

        try await installer.installScriptlets(scriptlets, cacheRootDirectory: cacheRootDirectory, to: installationDirectory)

        let files = try FileManager.default.contentsOfDirectory(at: installationDirectory, includingPropertiesForKeys: nil)

        XCTAssertEqual(files.count, 2)
        XCTAssertTrue(files.contains(where: { $0.lastPathComponent == "test1.js" }))
        XCTAssertTrue(files.contains(where: { $0.lastPathComponent == "test2.js" }))
    }

    func testWhenTargetPathHasSubdirectoriesThenDirectoryStructureIsPreserved() async throws {
        let scriptlets = [
            Scriptlet(path: "isolated/ublock-filters.js", relativeCachedPath: "ext/1.0/isolated/ublock-filters.js")
        ]

        try writeCacheFile(at: "ext/1.0/isolated/ublock-filters.js", content: "content")

        try await installer.installScriptlets(scriptlets, cacheRootDirectory: cacheRootDirectory, to: installationDirectory)

        let targetFile = installationDirectory
            .appendingPathComponent("isolated/ublock-filters.js")

        XCTAssertTrue(FileManager.default.fileExists(atPath: targetFile.path))
    }

    func testWhenScriptletAlreadyExistsThenItIsOverwritten() async throws {
        let scriptlets = [Scriptlet(path: "script.js", relativeCachedPath: "ext/1.0/script.js")]
        try writeCacheFile(at: "ext/1.0/script.js", content: "old content")
        try await installer.installScriptlets(scriptlets, cacheRootDirectory: cacheRootDirectory, to: installationDirectory)

        try writeCacheFile(at: "ext/2.0/script.js", content: "new content")
        let updatedScriptlets = [Scriptlet(path: "script.js", relativeCachedPath: "ext/2.0/script.js")]
        try await installer.installScriptlets(updatedScriptlets, cacheRootDirectory: cacheRootDirectory, to: installationDirectory)

        let targetFile = installationDirectory.appendingPathComponent("script.js")
        let content = try String(contentsOf: targetFile, encoding: .utf8)
        XCTAssertEqual(content, "new content")
    }

    // MARK: - Path Traversal Protection

    func testWhenScriptletPathIsAbsolutePathThenInstallThrows() async {
        let scriptlets = [Scriptlet(path: "/etc/passwd", relativeCachedPath: "ext/1.0/ok.js")]
        try? writeCacheFile(at: "ext/1.0/ok.js", content: "content")

        do {
            try await installer.installScriptlets(scriptlets, cacheRootDirectory: cacheRootDirectory, to: installationDirectory)
            XCTFail("Expected install to throw")
        } catch {
            XCTAssertEqual(error as? ScriptletError, .invalidName(name: "/etc/passwd"))
        }
    }

    func testWhenScriptletPathContainsParentSegmentThenInstallThrows() async {
        let scriptlets = [Scriptlet(path: "../../evil.js", relativeCachedPath: "ext/1.0/ok.js")]
        try? writeCacheFile(at: "ext/1.0/ok.js", content: "content")

        do {
            try await installer.installScriptlets(scriptlets, cacheRootDirectory: cacheRootDirectory, to: installationDirectory)
            XCTFail("Expected install to throw")
        } catch {
            XCTAssertEqual(error as? ScriptletError, .invalidName(name: "../../evil.js"))
        }
    }

    func testWhenScriptletPathIsTraversalThenNoFileIsCopiedOutsideInstallationDirectory() async {
        let scriptlets = [Scriptlet(path: "../escaped.js", relativeCachedPath: "ext/1.0/ok.js")]
        try? writeCacheFile(at: "ext/1.0/ok.js", content: "evil")

        try? await installer.installScriptlets(scriptlets, cacheRootDirectory: cacheRootDirectory, to: installationDirectory)

        let sibling = installationDirectory.deletingLastPathComponent().appendingPathComponent("escaped.js")
        XCTAssertFalse(FileManager.default.fileExists(atPath: sibling.path))
    }

    // MARK: - Helpers

    private func writeCacheFile(at relativePath: String, content: String) throws {
        let fileURL = cacheRootDirectory.appendingPathComponent(relativePath)
        let directory = fileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}

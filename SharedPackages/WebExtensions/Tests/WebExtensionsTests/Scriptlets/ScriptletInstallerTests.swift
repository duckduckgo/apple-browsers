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
    var sourceDirectory: URL!
    var installationDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        sourceDirectory = tempDirectory.appendingPathComponent("source")
        installationDirectory = tempDirectory.appendingPathComponent("install")

        try? FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)

        installer = ScriptletInstaller()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        installer = nil
        installationDirectory = nil
        sourceDirectory = nil
        tempDirectory = nil
        super.tearDown()
    }

    func testWhenScriptletsInstalledThenFilesAreCopiedToExtensionDirectory() async throws {
        let scriptlets = [
            Scriptlet(name: "test1", targetPath: "test1.js"),
            Scriptlet(name: "test2", targetPath: "test2.js")
        ]

        for scriptlet in scriptlets {
            try "content".write(to: sourceDirectory.appendingPathComponent(scriptlet.fileName), atomically: true, encoding: .utf8)
        }

        try await installer.installScriptlets(scriptlets, from: sourceDirectory, to: installationDirectory)

        let scriptletsDir = installationDirectory.appendingPathComponent("scriptlets")
        let files = try FileManager.default.contentsOfDirectory(at: scriptletsDir, includingPropertiesForKeys: nil)

        XCTAssertEqual(files.count, 2)
        XCTAssertTrue(files.contains(where: { $0.lastPathComponent == "test1.js" }))
        XCTAssertTrue(files.contains(where: { $0.lastPathComponent == "test2.js" }))
    }

    func testWhenTargetPathHasSubdirectoriesThenDirectoryStructureIsPreserved() async throws {
        let scriptlets = [
            Scriptlet(name: "scriptlets/isolated/ublock-filters.js", targetPath: "isolated/ublock-filters.js")
        ]

        try "content".write(
            to: sourceDirectory.appendingPathComponent(scriptlets[0].fileName),
            atomically: true,
            encoding: .utf8)

        try await installer.installScriptlets(scriptlets, from: sourceDirectory, to: installationDirectory)

        let targetFile = installationDirectory
            .appendingPathComponent("scriptlets")
            .appendingPathComponent("isolated/ublock-filters.js")

        XCTAssertTrue(FileManager.default.fileExists(atPath: targetFile.path))
    }

    func testWhenScriptletsInstalledTwiceThenOldFilesAreCleared() async throws {
        let oldScriptlets = [Scriptlet(name: "old", targetPath: "old")]
        try "old".write(to: sourceDirectory.appendingPathComponent("old.js"), atomically: true, encoding: .utf8)
        try await installer.installScriptlets(oldScriptlets, from: sourceDirectory, to: installationDirectory)

        try? FileManager.default.removeItem(at: sourceDirectory.appendingPathComponent("old.js"))
        let newScriptlets = [Scriptlet(name: "new", targetPath: "new")]
        try "new".write(to: sourceDirectory.appendingPathComponent("new.js"), atomically: true, encoding: .utf8)
        try await installer.installScriptlets(newScriptlets, from: sourceDirectory, to: installationDirectory)

        let scriptletsDir = installationDirectory.appendingPathComponent("scriptlets")
        let files = try FileManager.default.contentsOfDirectory(at: scriptletsDir, includingPropertiesForKeys: nil)

        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files.first?.lastPathComponent, "new.js")
    }

    func testWhenScriptletsRemovedThenDirectoryIsDeleted() async throws {
        let scriptlets = [Scriptlet(name: "test", targetPath: "test")]
        try "test".write(to: sourceDirectory.appendingPathComponent("test.js"), atomically: true, encoding: .utf8)
        try await installer.installScriptlets(scriptlets, from: sourceDirectory, to: installationDirectory)

        try installer.removeScriptlets(from: installationDirectory)

        let scriptletsDir = installationDirectory.appendingPathComponent("scriptlets")
        XCTAssertFalse(FileManager.default.fileExists(atPath: scriptletsDir.path))
    }
}

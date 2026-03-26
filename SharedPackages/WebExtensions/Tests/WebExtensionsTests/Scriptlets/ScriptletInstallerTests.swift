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
    var installationDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        installationDirectory = tempDirectory.appendingPathComponent(UUID().uuidString)

        installer = ScriptletInstaller()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        installer = nil
        installationDirectory = nil
        tempDirectory = nil
        super.tearDown()
    }

    func testWhenScriptletsInstalledThenFilesAreWrittenToExtensionDirectory() async throws {
        let scriptlets = [
            Scriptlet(name: "test1", content: Data("content1".utf8)),
            Scriptlet(name: "test2", content: Data("content2".utf8))
        ]

        try await installer.installScriptlets(scriptlets, to: installationDirectory)

        let scriptletsDir = installationDirectory.appendingPathComponent("scriptlets")

        let files = try FileManager.default.contentsOfDirectory(at: scriptletsDir, includingPropertiesForKeys: nil)

        XCTAssertEqual(files.count, 2)
        XCTAssertTrue(files.contains(where: { $0.lastPathComponent == "test1.js" }))
        XCTAssertTrue(files.contains(where: { $0.lastPathComponent == "test2.js" }))
    }

    func testWhenScriptletsInstalledTwiceThenOldFilesAreCleared() async throws {
        let oldScriptlets = [Scriptlet(name: "old", content: Data("old".utf8))]
        try await installer.installScriptlets(oldScriptlets, to: installationDirectory)

        let newScriptlets = [Scriptlet(name: "new", content: Data("new".utf8))]
        try await installer.installScriptlets(newScriptlets, to: installationDirectory)

        let scriptletsDir = installationDirectory.appendingPathComponent("scriptlets")

        let files = try FileManager.default.contentsOfDirectory(at: scriptletsDir, includingPropertiesForKeys: nil)

        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files.first?.lastPathComponent, "new.js")
    }

    func testWhenScriptletsRemovedThenDirectoryIsDeleted() async throws {
        let scriptlets = [Scriptlet(name: "test", content: Data("test".utf8))]
        try await installer.installScriptlets(scriptlets, to: installationDirectory)

        try installer.removeScriptlets(from: installationDirectory)

        let scriptletsDir = installationDirectory.appendingPathComponent("scriptlets")

        XCTAssertFalse(FileManager.default.fileExists(atPath: scriptletsDir.path))
    }
}

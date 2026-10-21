//
//  FileSystemDSLTests.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
import Testing
@testable import DuckDuckGo_Privacy_Browser

final class FileSystemDSLTests {
    private func getUniqueDirectoryName(for testName: String) -> String {
        return "FileSystemDSL_\(testName)_\(UUID().uuidString)"
    }

    private func removeDirectory(named directoryName: String) {
        let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(directoryName)
        try? FileManager.default.removeItem(at: directoryURL)
    }

    @Test("Root directory is created and removed when writing file system structure")
    func testWhenWritingFileSystemStructure_ThenRootDirectoryIsCreated() throws {
        let rootDirectoryName = getUniqueDirectoryName(for: "RootDirectoryCreated")
        let structure = FileSystem(rootDirectoryName: rootDirectoryName) { }

        let expectedURL = FileManager.default.temporaryDirectory.appendingPathComponent(rootDirectoryName)
        #expect(!FileManager.default.fileExists(atPath: expectedURL.path))

        try structure.writeToTemporaryDirectory()
        #expect(FileManager.default.fileExists(atPath: expectedURL.path))

        try structure.removeCreatedFileSystemStructure()
        #expect(!FileManager.default.fileExists(atPath: expectedURL.path))
    }

    @Test("Nested file system structure is created and removed correctly")
    func testWhenWritingNestedFileSystemStructure_ThenStructureIsCreated() throws {
        let rootDirectoryName = getUniqueDirectoryName(for: "NestedStructure")
        let structure = FileSystem(rootDirectoryName: rootDirectoryName) {
            File("top-level-file", contents: .string(""))

            Directory("folder-1") {
                File("nested-file", contents: .string(""))

                Directory("nested-folder") {
                    File("even-deeper-file", contents: .string(""))
                }
            }

            Directory("folder-2") {
                File("second-nested-file", contents: .string(""))
                File("third-nested-file", contents: .string(""))
            }
        }

        let expectedURL = FileManager.default.temporaryDirectory.appendingPathComponent(rootDirectoryName)
        #expect(!FileManager.default.fileExists(atPath: expectedURL.path))

        try structure.writeToTemporaryDirectory()
        #expect(FileManager.default.fileExists(atPath: expectedURL.path))
        #expect(FileManager.default.fileExists(atPath: expectedURL.appendingPathComponent("top-level-file").path))

        #expect(FileManager.default.fileExists(atPath: expectedURL.appendingPathComponent("folder-1").path))

        #expect(FileManager.default.fileExists(atPath: expectedURL
            .appendingPathComponent("folder-1")
            .appendingPathComponent("nested-file").path))

        #expect(FileManager.default.fileExists(atPath: expectedURL
            .appendingPathComponent("folder-1")
            .appendingPathComponent("nested-folder").path))

        #expect(FileManager.default.fileExists(atPath: expectedURL
            .appendingPathComponent("folder-1")
            .appendingPathComponent("nested-folder")
            .appendingPathComponent("even-deeper-file").path))

        #expect(FileManager.default.fileExists(atPath: expectedURL.appendingPathComponent("folder-2").path))

        #expect(FileManager.default.fileExists(atPath: expectedURL
            .appendingPathComponent("folder-2")
            .appendingPathComponent("second-nested-file").path))

        #expect(FileManager.default.fileExists(atPath: expectedURL
            .appendingPathComponent("folder-2")
            .appendingPathComponent("third-nested-file").path))

        try structure.removeCreatedFileSystemStructure()
        #expect(!FileManager.default.fileExists(atPath: expectedURL.path))
    }

    @Test("String file contents are correctly persisted")
    func testWhenPersistingFile_AndFileContentsAreAString_ThenTheFileContentsAreCorrect() throws {
        let rootDirectoryName = getUniqueDirectoryName(for: "StringContents")
        let expectedContents = "Top Level File Contents"

        let structure = FileSystem(rootDirectoryName: rootDirectoryName) {
            File("top-level-file", contents: .string(expectedContents))
        }

        try structure.writeToTemporaryDirectory()

        let filePath = FileManager.default.temporaryDirectory.appendingPathComponent(rootDirectoryName).appendingPathComponent("top-level-file")
        let contents = try String(contentsOf: filePath)

        #expect(contents == expectedContents)

        try structure.removeCreatedFileSystemStructure()
    }

    @Test("Copied file contents are correctly persisted")
    func testWhenPersistingFile_AndFileContentsAreCopied_ThenTheFileContentsAreCorrect() throws {
        let rootDirectoryName = getUniqueDirectoryName(for: "CopiedContents")
        let bundle = Bundle(for: FileSystemDSLTests.self)
        let bundleFileURL = bundle.resourceURL!.appendingPathComponent("DataImportResources/TestFirefoxData/No Primary Password/key4.db")

        let structure = FileSystem(rootDirectoryName: rootDirectoryName) {
            File("key4.db", contents: .copy(bundleFileURL))
        }

        try structure.writeToTemporaryDirectory()

        let copiedFileURL = FileManager.default.temporaryDirectory.appendingPathComponent(rootDirectoryName).appendingPathComponent("key4.db")
        let bundleFileContents = try Data(contentsOf: bundleFileURL)
        let copiedFileContents = try Data(contentsOf: copiedFileURL)

        #expect(bundleFileContents == copiedFileContents)

        try structure.removeCreatedFileSystemStructure()
    }
}

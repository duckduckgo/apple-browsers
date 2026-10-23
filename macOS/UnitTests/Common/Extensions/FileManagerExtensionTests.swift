//
//  FileManagerExtensionTests.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

final class FileManagerExtensionTests {

    let testExtension1 = "dmg"
    let testExtension2 = "zip"
    let testData = "test".data(using: .utf8)!
    let fm = FileManager.default

    /// Unique file name per test so tests can run in parallel without clashing in the temporary directory.
    private let testFile = "the file \(UUID().uuidString)"

    private var createdURLs: [URL] = []

    deinit {
        for url in createdURLs {
            try? fm.removeItem(at: url)
        }
    }

    private func write(to url: URL) throws {
        try testData.write(to: url)
        createdURLs.append(url)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func testWhenItemMovedToSameURLIncrementingIndexThenNoErrorIsThrown() throws {
        let srcURL = fm.temporaryDirectory.appendingPathComponent(testFile)
        try write(to: srcURL)

        let destURL = try fm.moveItem(at: srcURL, to: srcURL, incrementingIndexIfExists: true)
        #expect(srcURL == destURL)
        #expect(fm.fileExists(atPath: destURL.path))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func testWhenItemMovedToSameURLNotIncrementingIndexThenNoErrorIsThrown() throws {
        let srcURL = fm.temporaryDirectory.appendingPathComponent(testFile)
        try write(to: srcURL)

        let destURL = try fm.moveItem(at: srcURL, to: srcURL, incrementingIndexIfExists: false)
        #expect(srcURL == destURL)
        #expect(fm.fileExists(atPath: destURL.path))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func testWhenItemMoveDestDoesNotExistThenIndexNotIncremented() throws {
        let srcURL = fm.temporaryDirectory.appendingPathComponent(testFile)
        let destURL = fm.temporaryDirectory.appendingPathComponent(testFile + testFile)
        try write(to: srcURL)
        createdURLs.append(destURL)

        let result = try fm.moveItem(at: srcURL, to: destURL, incrementingIndexIfExists: true)
        #expect(result == destURL)
        #expect(fm.fileExists(atPath: result.path))
        #expect(!fm.fileExists(atPath: srcURL.path))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func testWhenItemMoveDestExistsThenIndexIsIncremented() throws {
        let srcURL = fm.temporaryDirectory.appendingPathComponent(testFile)
        let existingURL1 = fm.temporaryDirectory.appendingPathComponent(testFile + testFile)
        let existingURL2 = fm.temporaryDirectory.appendingPathComponent(testFile + testFile + " 1")
        let destURL = fm.temporaryDirectory.appendingPathComponent(testFile + testFile + " 2")

        try write(to: srcURL)
        try write(to: existingURL1)
        try write(to: existingURL2)
        createdURLs.append(destURL)

        let result = try fm.moveItem(at: srcURL, to: existingURL1, incrementingIndexIfExists: true)
        #expect(result == destURL)
        #expect(fm.fileExists(atPath: result.path))
        #expect(!fm.fileExists(atPath: srcURL.path))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func testWhenItemWithExtensionMoveDestExistsThenIndexIsIncrementedBeforeExtension() throws {
        let srcURL = fm.temporaryDirectory.appendingPathComponent(testFile)
        let existingURL = fm.temporaryDirectory.appendingPathComponent(testFile + testFile)
            .appendingPathExtension(testExtension1)
            .appendingPathExtension(testExtension2)
        let destURL = fm.temporaryDirectory.appendingPathComponent(testFile + testFile + "." + testExtension1 + " 1")
            .appendingPathExtension(testExtension2)

        try write(to: srcURL)
        try write(to: existingURL)
        createdURLs.append(destURL)

        let result = try fm.moveItem(at: srcURL, to: existingURL, incrementingIndexIfExists: true)
        #expect(result == destURL)
        #expect(fm.fileExists(atPath: result.path))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func testWhenItemWithExtensionMoveDestExistsAndExtensionProvidedThenIndexIsIncrementedBeforeExtension() throws {
        let srcURL = fm.temporaryDirectory.appendingPathComponent(testFile)
        let existingURL = fm.temporaryDirectory.appendingPathComponent(testFile + testFile)
            .appendingPathExtension(testExtension1)
            .appendingPathExtension(testExtension2)
        let destURL = fm.temporaryDirectory.appendingPathComponent(testFile + testFile + "." + testExtension1 + " 1")
            .appendingPathExtension(testExtension2)

        try write(to: srcURL)
        try write(to: existingURL)
        createdURLs.append(destURL)

        let result = try fm.moveItem(at: srcURL, to: existingURL, incrementingIndexIfExists: true, pathExtension: testExtension2)
        #expect(result == destURL)
        #expect(fm.fileExists(atPath: result.path))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func testWhenItemWithExtensionMoveDestExistsAndDoubleExtensionProvidedThenIndexIsIncrementedBeforeDoubleExtension() throws {
        let srcURL = fm.temporaryDirectory.appendingPathComponent(testFile)
        let existingURL = fm.temporaryDirectory.appendingPathComponent(testFile + testFile)
            .appendingPathExtension(testExtension1)
            .appendingPathExtension(testExtension2)
        let destURL = fm.temporaryDirectory.appendingPathComponent(testFile + testFile + " 1")
            .appendingPathExtension(testExtension1)
            .appendingPathExtension(testExtension2)

        try write(to: srcURL)
        try write(to: existingURL)
        createdURLs.append(destURL)

        let result = try fm.moveItem(at: srcURL, to: existingURL,
                                     incrementingIndexIfExists: true,
                                     pathExtension: testExtension1 + "." + testExtension2)
        #expect(result == destURL)
        #expect(fm.fileExists(atPath: result.path))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func testWhenItemWithExtensionMoveDestExistsAndWrongExtensionProvidedThenIndexIsIncrementedBeforeActualExtension() throws {
        let srcURL = fm.temporaryDirectory.appendingPathComponent(testFile)
        let existingURL = fm.temporaryDirectory.appendingPathComponent(testFile + testFile)
            .appendingPathExtension(testExtension1)
            .appendingPathExtension("asd")
        let destURL = fm.temporaryDirectory.appendingPathComponent(testFile + testFile + "." + testExtension1 + " 1")
            .appendingPathExtension("asd")

        try write(to: srcURL)
        try write(to: existingURL)
        createdURLs.append(destURL)

        let result = try fm.moveItem(at: srcURL, to: existingURL,
                                     incrementingIndexIfExists: true,
                                     pathExtension: testExtension1)
        #expect(result == destURL)
        #expect(fm.fileExists(atPath: result.path))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func testWhenItemMovedToReadOnlyDirThenErrorIsThrown() throws {
        let srcURL = fm.temporaryDirectory.appendingPathComponent(testFile)
        try write(to: srcURL)

        let destURL = URL(fileURLWithPath: "/ro_volume_file")

        let error = #expect(throws: CocoaError.self, "should throw error") {
            try self.fm.moveItem(at: srcURL, to: destURL, incrementingIndexIfExists: true)
        }
        #expect(error?.code == CocoaError.fileWriteNoPermission
                || error?.code == CocoaError.fileWriteVolumeReadOnly)
    }

}

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

import Testing
@testable import DuckDuckGo_Privacy_Browser

final class FileManagerExtensionTests {

    let testFile = "the file"
    let testExtension1 = "dmg"
    let testExtension2 = "zip"
    let testData = "test".data(using: .utf8)!
    let fm = FileManager.default

    func getUniqueFileName(for testName: String) -> String {
        return "\(testName)-\(UUID().uuidString)"
    }

    @Test("When item moved to same URL incrementing index then no error is thrown")
    func testWhenItemMovedToSameURLIncrementingIndexThenNoErrorIsThrown() throws {
        let testFile = getUniqueFileName(for: "SameURLIncrementingIndex")
        let srcURL = fm.temporaryDirectory.appendingPathComponent(testFile)
        try testData.write(to: srcURL)

        let destURL = try fm.moveItem(at: srcURL, to: srcURL, incrementingIndexIfExists: true)
        #expect(srcURL == destURL)
        #expect(fm.fileExists(atPath: destURL.path))

        try? fm.removeItem(at: srcURL)
    }

    @Test("When item moved to same URL not incrementing index then no error is thrown")
    func testWhenItemMovedToSameURLNotIncrementingIndexThenNoErrorIsThrown() throws {
        let testFile = getUniqueFileName(for: "SameURLNotIncrementingIndex")
        let srcURL = fm.temporaryDirectory.appendingPathComponent(testFile)
        try testData.write(to: srcURL)

        let destURL = try fm.moveItem(at: srcURL, to: srcURL, incrementingIndexIfExists: false)
        #expect(srcURL == destURL)
        #expect(fm.fileExists(atPath: destURL.path))

        try? fm.removeItem(at: srcURL)
    }

    @Test("When item move dest does not exist then index not incremented")
    func testWhenItemMoveDestDoesNotExistThenIndexNotIncremented() throws {
        let testFile = getUniqueFileName(for: "DestDoesNotExist")
        let srcURL = fm.temporaryDirectory.appendingPathComponent(testFile)
        let destURL = fm.temporaryDirectory.appendingPathComponent(testFile + testFile)

        try testData.write(to: srcURL)

        let resultURL = try fm.moveItem(at: srcURL, to: destURL, incrementingIndexIfExists: true)
        #expect(resultURL == destURL)
        #expect(fm.fileExists(atPath: resultURL.path))

        try? fm.removeItem(at: destURL)
    }

    @Test("When item move dest exists then index is incremented")
    func testWhenItemMoveDestExistsThenIndexIsIncremented() throws {
        let testFile = getUniqueFileName(for: "DestExists")
        let srcURL = fm.temporaryDirectory.appendingPathComponent(testFile)
        let existingURL = fm.temporaryDirectory.appendingPathComponent(testFile + testFile)
        let expectedIncrementedURL = fm.temporaryDirectory.appendingPathComponent(testFile + testFile + " 1")

        try testData.write(to: srcURL)
        try testData.write(to: existingURL)

        let resultURL = try fm.moveItem(at: srcURL, to: existingURL, incrementingIndexIfExists: true)
        let unwrappedResultURL = resultURL

        #expect(unwrappedResultURL == expectedIncrementedURL)
        #expect(fm.fileExists(atPath: unwrappedResultURL.path))
        #expect(!fm.fileExists(atPath: srcURL.path))

        try? fm.removeItem(at: existingURL)
        try? fm.removeItem(at: unwrappedResultURL)
    }

    @Test("When item with extension move dest exists then index is incremented before extension")
    func testWhenItemWithExtensionMoveDestExistsThenIndexIsIncrementedBeforeExtension() throws {
        let testFile = getUniqueFileName(for: "ExtensionIncrement")
        let testExtension1 = "txt"
        let testExtension2 = "bak"

        let srcURL = fm.temporaryDirectory.appendingPathComponent(testFile)
        let existingURL = fm.temporaryDirectory.appendingPathComponent(testFile + testFile)
            .appendingPathExtension(testExtension1)
            .appendingPathExtension(testExtension2)
        let destURL = fm.temporaryDirectory.appendingPathComponent(testFile + testFile + "." + testExtension1 + " 1")
            .appendingPathExtension(testExtension2)

        try testData.write(to: srcURL)
        try testData.write(to: existingURL)

        let resultURL = try fm.moveItem(at: srcURL, to: existingURL, incrementingIndexIfExists: true)
        let unwrappedResultURL = resultURL

        #expect(unwrappedResultURL == destURL)
        #expect(fm.fileExists(atPath: unwrappedResultURL.path))

        try? fm.removeItem(at: existingURL)
        try? fm.removeItem(at: unwrappedResultURL)
    }

    @Test("When item with extension move dest exists and extension provided then index is incremented before extension")
    func testWhenItemWithExtensionMoveDestExistsAndExtensionProvidedThenIndexIsIncrementedBeforeExtension() throws {
        let testFile = getUniqueFileName(for: "ExtensionProvided")
        let testExtension1 = "txt"
        let testExtension2 = "bak"

        let srcURL = fm.temporaryDirectory.appendingPathComponent(testFile)
        let existingURL = fm.temporaryDirectory.appendingPathComponent(testFile + testFile)
            .appendingPathExtension(testExtension1)
            .appendingPathExtension(testExtension2)
        let destURL = fm.temporaryDirectory.appendingPathComponent(testFile + testFile + "." + testExtension1 + " 1")
            .appendingPathExtension(testExtension2)

        try testData.write(to: srcURL)
        try testData.write(to: existingURL)

        let resultURL = try fm.moveItem(at: srcURL, to: existingURL, incrementingIndexIfExists: true, pathExtension: testExtension2)
        let unwrappedResultURL = resultURL

        #expect(unwrappedResultURL == destURL)
        #expect(fm.fileExists(atPath: unwrappedResultURL.path))

        try? fm.removeItem(at: existingURL)
        try? fm.removeItem(at: unwrappedResultURL)
    }

    @Test("When item with extension move dest exists and double extension provided then index is incremented before double extension")
    func testWhenItemWithExtensionMoveDestExistsAndDoubleExtensionProvidedThenIndexIsIncrementedBeforeDoubleExtension() throws {
        let testFile = getUniqueFileName(for: "DoubleExtension")
        let testExtension1 = "txt"
        let testExtension2 = "bak"

        let srcURL = fm.temporaryDirectory.appendingPathComponent(testFile)
        let existingURL = fm.temporaryDirectory.appendingPathComponent(testFile + testFile)
            .appendingPathExtension(testExtension1)
            .appendingPathExtension(testExtension2)
        let destURL = fm.temporaryDirectory.appendingPathComponent(testFile + testFile + " 1")
            .appendingPathExtension(testExtension1)
            .appendingPathExtension(testExtension2)

        try testData.write(to: srcURL)
        try testData.write(to: existingURL)

        let resultURL = try fm.moveItem(at: srcURL, to: existingURL,
                                      incrementingIndexIfExists: true,
                                      pathExtension: testExtension1 + "." + testExtension2)
        let unwrappedResultURL = resultURL

        #expect(unwrappedResultURL == destURL)
        #expect(fm.fileExists(atPath: unwrappedResultURL.path))

        try? fm.removeItem(at: existingURL)
        try? fm.removeItem(at: unwrappedResultURL)
    }

    @Test("When item with extension move dest exists and wrong extension provided then index is incremented before actual extension")
    func testWhenItemWithExtensionMoveDestExistsAndWrongExtensionProvidedThenIndexIsIncrementedBeforeActualExtension() throws {
        let testFile = getUniqueFileName(for: "WrongExtension")
        let testExtension1 = "txt"

        let srcURL = fm.temporaryDirectory.appendingPathComponent(testFile)
        let existingURL = fm.temporaryDirectory.appendingPathComponent(testFile + testFile)
            .appendingPathExtension(testExtension1)
            .appendingPathExtension("asd")
        let destURL = fm.temporaryDirectory.appendingPathComponent(testFile + testFile + "." + testExtension1 + " 1")
            .appendingPathExtension("asd")

        try testData.write(to: srcURL)
        try testData.write(to: existingURL)

        let resultURL = try fm.moveItem(at: srcURL, to: existingURL,
                                      incrementingIndexIfExists: true,
                                      pathExtension: testExtension1)
        let unwrappedResultURL = resultURL

        #expect(unwrappedResultURL == destURL)
        #expect(fm.fileExists(atPath: unwrappedResultURL.path))

        try? fm.removeItem(at: existingURL)
        try? fm.removeItem(at: unwrappedResultURL)
    }

    @Test("When item move dest exists and incrementing is false then error is thrown")
    func testWhenItemMoveDestExistsAndIncrementingIsFalseThenErrorIsThrown() throws {
        let testFile = getUniqueFileName(for: "DestExistsNoIncrement")
        let srcURL = fm.temporaryDirectory.appendingPathComponent(testFile)
        let destURL = fm.temporaryDirectory.appendingPathComponent(testFile + "_dest")

        try testData.write(to: srcURL)
        try testData.write(to: destURL)

        do {
            _ = try fm.moveItem(at: srcURL, to: destURL, incrementingIndexIfExists: false)
            #expect(Bool(false), "Expected an error to be thrown")
        } catch {
            #expect(error.localizedDescription.contains("already exists"))
        }

        try? fm.removeItem(at: srcURL)
        try? fm.removeItem(at: destURL)
    }

    @Test("When item move src does not exist then error is thrown")
    func testWhenItemMoveSrcDoesNotExistThenErrorIsThrown() throws {
        let testFile = getUniqueFileName(for: "SrcDoesNotExist")
        let srcURL = fm.temporaryDirectory.appendingPathComponent(testFile)
        let destURL = fm.temporaryDirectory.appendingPathComponent(testFile + testFile)

        do {
            _ = try fm.moveItem(at: srcURL, to: destURL, incrementingIndexIfExists: true)
            #expect(Bool(false), "Expected an error to be thrown")
        } catch {
            #expect(error.localizedDescription.contains("doesn’t exist"))
        }
    }

    @Test("When item move dest is in different volume then error is thrown")
    func testWhenItemMoveDestIsInDifferentVolumeThenErrorIsThrown() throws {
        let testFile = getUniqueFileName(for: "DifferentVolume")
        let srcURL = fm.temporaryDirectory.appendingPathComponent(testFile)
        let destURL = URL(fileURLWithPath: "/Volumes/NonExistentVolume/\(testFile)")

        try testData.write(to: srcURL)

        do {
            _ = try fm.moveItem(at: srcURL, to: destURL, incrementingIndexIfExists: true)
            #expect(Bool(false), "Expected an error to be thrown")
        } catch {
            #expect(error.localizedDescription.contains("folder containing the latter doesn’t exist"))
        }

        try? fm.removeItem(at: srcURL)
    }

    @Test("When item moved to read-only directory then error is thrown")
    func testWhenItemMovedToReadOnlyDirThenErrorIsThrown() throws {
        let testFile = getUniqueFileName(for: "ReadOnlyDir")
        let srcURL = fm.temporaryDirectory.appendingPathComponent(testFile)
        try testData.write(to: srcURL)

        let destURL = URL(fileURLWithPath: "/ro_volume_file")

        do {
            _ = try fm.moveItem(at: srcURL, to: destURL, incrementingIndexIfExists: true)
            #expect(Bool(false), "Expected an error to be thrown")
        } catch let error as CocoaError {
            #expect(error.code == CocoaError.fileWriteNoPermission || error.code == CocoaError.fileWriteVolumeReadOnly)
        } catch {
            #expect(Bool(false), "Expected a CocoaError")
        }

        try? fm.removeItem(at: srcURL)
    }

    @Test("When item move dest is in same volume then no error is thrown")
    func testWhenItemMoveDestIsInSameVolumeThenNoErrorIsThrown() throws {
        let testFile = getUniqueFileName(for: "SameVolume")
        let srcURL = fm.temporaryDirectory.appendingPathComponent(testFile)
        let destURL = fm.temporaryDirectory.appendingPathComponent(testFile + testFile)

        try testData.write(to: srcURL)

        let resultURL = try fm.moveItem(at: srcURL, to: destURL, incrementingIndexIfExists: true)
        #expect(resultURL == destURL)
        #expect(fm.fileExists(atPath: resultURL.path))

        try? fm.removeItem(at: destURL)
    }

    @Test("When item move dest is in same directory then no error is thrown")
    func testWhenItemMoveDestIsInSameDirectoryThenNoErrorIsThrown() throws {
        let testFile = getUniqueFileName(for: "SameDirectory")
        let srcURL = fm.temporaryDirectory.appendingPathComponent(testFile)
        let destURL = fm.temporaryDirectory.appendingPathComponent(testFile + testFile)

        try testData.write(to: srcURL)

        let resultURL = try fm.moveItem(at: srcURL, to: destURL, incrementingIndexIfExists: true)
        #expect(resultURL == destURL)
        #expect(fm.fileExists(atPath: resultURL.path))

        try? fm.removeItem(at: destURL)
    }

    @Test("When item move dest is in different directory then no error is thrown")
    func testWhenItemMoveDestIsInDifferentDirectoryThenNoErrorIsThrown() throws {
        let testFile = getUniqueFileName(for: "DifferentDirectory")
        let srcURL = fm.temporaryDirectory.appendingPathComponent(testFile)
        let destDir = fm.temporaryDirectory.appendingPathComponent("destDir")
        let destURL = destDir.appendingPathComponent(testFile)

        try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
        try testData.write(to: srcURL)

        let resultURL = try fm.moveItem(at: srcURL, to: destURL, incrementingIndexIfExists: true)
        #expect(resultURL == destURL)
        #expect(fm.fileExists(atPath: resultURL.path))

        try? fm.removeItem(at: destURL)
        try? fm.removeItem(at: destDir)
    }

    @Test("When item move dest is in different directory and incrementing is false then error is thrown")
    func testWhenItemMoveDestIsInDifferentDirectoryAndIncrementingIsFalseThenErrorIsThrown() throws {
        let testFile = getUniqueFileName(for: "DifferentDirectoryNoIncrement")
        let srcURL = fm.temporaryDirectory.appendingPathComponent(testFile)
        let destDir = fm.temporaryDirectory.appendingPathComponent("destDir")
        let destURL = destDir.appendingPathComponent(testFile)

        try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
        try testData.write(to: srcURL)
        try testData.write(to: destURL)

        do {
            _ = try fm.moveItem(at: srcURL, to: destURL, incrementingIndexIfExists: false)
            #expect(Bool(false), "Expected an error to be thrown")
        } catch {
            #expect(error.localizedDescription.contains("already exists"))
        }

        try? fm.removeItem(at: srcURL)
        try? fm.removeItem(at: destURL)
        try? fm.removeItem(at: destDir)
    }

    @Test("When item move dest is in different directory and incrementing is true then index is incremented")
    func testWhenItemMoveDestIsInDifferentDirectoryAndIncrementingIsTrueThenIndexIsIncremented() throws {
        let testFile = getUniqueFileName(for: "DifferentDirectoryIncrement")
        let srcURL = fm.temporaryDirectory.appendingPathComponent(testFile)
        let destDir = fm.temporaryDirectory.appendingPathComponent("destDir")
        let destURL = destDir.appendingPathComponent(testFile)

        try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
        try testData.write(to: srcURL)
        try testData.write(to: destURL)

        let resultURL = try fm.moveItem(at: srcURL, to: destURL, incrementingIndexIfExists: true)

        #expect(resultURL != destURL)
        #expect(resultURL.lastPathComponent.hasPrefix(testFile))
        #expect(fm.fileExists(atPath: resultURL.path))

        try? fm.removeItem(at: destURL)
        try? fm.removeItem(at: resultURL)
        try? fm.removeItem(at: destDir)
    }
}

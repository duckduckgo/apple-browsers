//
//  KeyValueFileStoreTests.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import Persistence
import Testing

final class KeyValueFileStoreTests {

    static let tempDir: URL = {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    init() throws {
        // Ensure temp directory exists
        try FileManager.default.createDirectory(at: Self.tempDir, withIntermediateDirectories: true)
    }

    // MARK: - Protocol Conformance Tests

    @Test("KeyValueFileStore conforms to ThrowingKeyValueStoring")
    func storeConformsToThrowingKeyValueStoring() throws {
        let name = UUID().uuidString
        let store = try KeyValueFileStore(location: Self.tempDir, name: name)

        let conformsToProtocol = store is ThrowingKeyValueStoring
        #expect(conformsToProtocol)
    }

    @Test("KeyValueFileStore does not conform to ObservableThrowingKeyValueStoring")
    func storeDoesNotConformToObservableThrowingKeyValueStoring() throws {
        let name = UUID().uuidString
        let store = try KeyValueFileStore(location: Self.tempDir, name: name)

        // KeyValueFileStore is file-based and does not support observation
        let doesNotConformToObservableProtocol = !(store is ObservableThrowingKeyValueStoring)
        #expect(doesNotConformToObservableProtocol)
    }

    // MARK: - Basic Functionality Tests

    @Test("File missing throws no error")
    func fileMissingNoErrorIsThrown() throws {
        let name = UUID().uuidString
        let s = try KeyValueFileStore(location: Self.tempDir, name: name)

        #expect(try s.object(forKey: "a") == nil)
    }

    @Test("File reuse throws error")
    func fileReusedErrorIsThrown() throws {
        let name = UUID().uuidString
        let firstStore = try KeyValueFileStore(location: Self.tempDir, name: name)

        #expect(throws: (any Error).self) {
            try KeyValueFileStore(location: Self.tempDir, name: name)
        }

        // Keep firstStore alive until after the test
        _ = firstStore
    }

    @Test("Persisting simple objects")
    func persistingSimpleObjects() throws {
        let name = UUID().uuidString
        var s = try KeyValueFileStore(location: Self.tempDir, name: name)

        try s.set(true, forKey: "tbool")
        try s.set(false, forKey: "fbool")

        try s.set(0, forKey: "int0")
        try s.set(1, forKey: "int1")

        try s.set(5.5, forKey: "double1")

        try s.set("string", forKey: "string")

        try s.set("data".data(using: .utf8), forKey: "data")

        // Reload from file
        KeyValueFileStore.relinquish(fileURL: s.fileURL)
        s = try KeyValueFileStore(location: Self.tempDir, name: name)
        #expect(try s.object(forKey: "tbool") as? Bool == true)
        #expect(try s.object(forKey: "fbool") as? Bool == false)

        #expect(try s.object(forKey: "int0") as? Int == 0)
        #expect(try s.object(forKey: "int1") as? Int == 1)

        #expect(try s.object(forKey: "double1") as? Double == 5.5)

        #expect(try s.object(forKey: "string") as? String == "string")

        #expect(try s.object(forKey: "data") as? Data == "data".data(using: .utf8))
    }

    @Test("Persisting collections")
    func persistingCollections() throws {
        let name = UUID().uuidString
        var s = try KeyValueFileStore(location: Self.tempDir, name: name)

        try s.set([1, 2], forKey: "arrayI")
        try s.set(["a", "b"], forKey: "arrayS")
        try s.set([1, "a"], forKey: "arrayM")

        try s.set(["a": 1, "b": 2], forKey: "dict")

        // Reload from file
        KeyValueFileStore.relinquish(fileURL: s.fileURL)
        s = try KeyValueFileStore(location: Self.tempDir, name: name)
        #expect(try s.object(forKey: "arrayI") as? [Int] == [1, 2])
        #expect(try s.object(forKey: "arrayS") as? [String] == ["a", "b"])

        let a = try s.object(forKey: "arrayM") as? [Any]
        #expect(a?[0] as? Int == 1)
        #expect(a?[1] as? String == "a")

        #expect(try s.object(forKey: "dict") as? [String: Int] == ["a": 1, "b": 2])
    }

    @Test("Persisting unsupported objects")
    func persistingUnsupportedObjects() throws {
        let name = UUID().uuidString
        var s = try KeyValueFileStore(location: Self.tempDir, name: name)

        let set: Set<String> = ["a"]
        #expect(throws: (any Error).self) {
            try s.set(set, forKey: "set")
        }

        // This must succeed
        try s.set(["a": 1, "b": 2], forKey: "dict")

        // Reload from file
        KeyValueFileStore.relinquish(fileURL: s.fileURL)
        s = try KeyValueFileStore(location: Self.tempDir, name: name)
        #expect(try s.object(forKey: "set") == nil)
        #expect(try s.object(forKey: "dict") as? [String: Int] == ["a": 1, "b": 2])
    }
}

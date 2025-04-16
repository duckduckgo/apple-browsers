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

import XCTest
import Persistence

class KeyValueFileStoreTests: XCTestCase {

    static let tempDir: URL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    override class func setUp() {
        super.setUp()

        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            XCTFail("Could not prepare test DIR")
        }
    }

    override class func tearDown() {
        super.setUp()

        do {
            try FileManager.default.removeItem(at: tempDir)
        } catch {
            XCTFail("Could not cleanup test DIR")
        }
    }

    func testWhenFileIsMissingNoErrorIsThrown() throws {

        let name = UUID().uuidString
        let s = try KeyValueFileStore(location: Self.tempDir, name: name)

        XCTAssertNil(try s.object(forKey: "a"))
    }

    func testWhenFileIsReusedErrorIsThrown() throws {

        let name = UUID().uuidString
        let s = try KeyValueFileStore(location: Self.tempDir, name: name)

        XCTAssertThrowsError(try KeyValueFileStore(location: Self.tempDir, name: name))
    }

    func testPersistingSimpleObjects() throws {

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
        XCTAssertEqual(try s.object(forKey: "tbool") as? Bool, true)
        XCTAssertEqual(try s.object(forKey: "fbool") as? Bool, false)

        XCTAssertEqual(try s.object(forKey: "int0") as? Int, 0)
        XCTAssertEqual(try s.object(forKey: "int1") as? Int, 1)

        XCTAssertEqual(try s.object(forKey: "double1") as? Double, 5.5)

        XCTAssertEqual(try s.object(forKey: "string") as? String, "string")

        XCTAssertEqual(try s.object(forKey: "data") as? Data, "data".data(using: .utf8))
    }

    func testPersistingCollections() throws {

        let name = UUID().uuidString
        var s = try KeyValueFileStore(location: Self.tempDir, name: name)

        try s.set([1, 2], forKey: "arrayI")
        try s.set(["a", "b"], forKey: "arrayS")
        try s.set([1, "a"], forKey: "arrayM")

        try s.set(["a": 1, "b": 2], forKey: "dict")

        // Reload from file
        KeyValueFileStore.relinquish(fileURL: s.fileURL)
        s = try KeyValueFileStore(location: Self.tempDir, name: name)
        XCTAssertEqual(try s.object(forKey: "arrayI") as? [Int], [1, 2])
        XCTAssertEqual(try s.object(forKey: "arrayS") as? [String], ["a", "b"])

        let a = try s.object(forKey: "arrayM") as? [Any]
        XCTAssertEqual(a?[0] as? Int, 1)
        XCTAssertEqual(a?[1] as? String, "a")

        XCTAssertEqual(try s.object(forKey: "dict") as? [String: Int], ["a": 1, "b": 2])
    }

    func testPersistingUnsupportedObjects() throws {

        let name = UUID().uuidString
        var s = try KeyValueFileStore(location: Self.tempDir, name: name)

        let set: Set<String> = ["a"]
        do {
            try s.set(set, forKey: "set")
            XCTFail("Set should not be persisted")
        } catch {}

        // This must succeed
        try s.set(["a": 1, "b": 2], forKey: "dict")

        // Reload from file
        KeyValueFileStore.relinquish(fileURL: s.fileURL)
        s = try KeyValueFileStore(location: Self.tempDir, name: name)
        XCTAssertNil(try s.object(forKey: "set"))
        XCTAssertEqual(try s.object(forKey: "dict") as? [String: Int], ["a": 1, "b": 2])
    }

}

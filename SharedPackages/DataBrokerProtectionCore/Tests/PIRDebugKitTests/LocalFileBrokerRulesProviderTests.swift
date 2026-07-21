//
//  LocalFileBrokerRulesProviderTests.swift
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
@testable import PIRDebugKit

final class LocalFileBrokerRulesProviderTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func validBrokerData() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "fakebroker.com", withExtension: "json", subdirectory: "Resources"))
        return try Data(contentsOf: url)
    }

    func testSingleValidFile() async throws {
        let fileURL = tempDir.appendingPathComponent("fakebroker.com.json")
        try validBrokerData().write(to: fileURL)

        let provider = LocalFileBrokerRulesProvider(url: fileURL)
        let brokers = try await provider.fetchBrokers()
        XCTAssertEqual(brokers.count, 1)
        XCTAssertEqual(brokers.first?.url, "fakebroker.com")
        XCTAssertTrue(provider.errors.isEmpty)
    }

    func testDirectoryWithMixedValidAndInvalidFilesCollectsErrorsAndReturnsValid() async throws {
        try validBrokerData().write(to: tempDir.appendingPathComponent("fakebroker.com.json"))
        try Data("{ not valid broker json".utf8).write(to: tempDir.appendingPathComponent("broken.json"))
        try Data("{}".utf8).write(to: tempDir.appendingPathComponent("empty-object.json"))
        // A non-json file should be ignored entirely.
        try Data("ignore me".utf8).write(to: tempDir.appendingPathComponent("notes.txt"))

        let provider = LocalFileBrokerRulesProvider(url: tempDir)
        let brokers = try await provider.fetchBrokers()

        XCTAssertEqual(brokers.count, 1, "Only the valid broker should be returned")
        XCTAssertEqual(brokers.first?.url, "fakebroker.com")
        XCTAssertEqual(provider.errors.count, 2, "Both invalid .json files should be collected as errors")
        XCTAssertTrue(provider.errors.allSatisfy { $0.fileURL.pathExtension == "json" })
    }

    func testMissingPathThrows() async {
        let missing = tempDir.appendingPathComponent("does-not-exist.json")
        let provider = LocalFileBrokerRulesProvider(url: missing)
        do {
            _ = try await provider.fetchBrokers()
            XCTFail("Expected an error for a missing path")
        } catch {
            // expected
        }
    }
}

//
//  WebExtensionLoaderDelegateTests.swift
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
import WebKit
@testable import WebExtensions

@available(macOS 15.4, iOS 18.4, *)
final class WebExtensionLoaderDelegateTests: XCTestCase {

    var loader: WebExtensionLoader!
    var delegateMock: WebExtensionLoadingDelegateMock!
    var storageProvider: WebExtensionStorageProvidingMock!
    var controller: WKWebExtensionController!

    @MainActor
    override func setUp() {
        super.setUp()
        storageProvider = WebExtensionStorageProvidingMock()
        loader = WebExtensionLoader(storageProvider: storageProvider)
        delegateMock = WebExtensionLoadingDelegateMock()
        loader.delegate = delegateMock
        controller = WKWebExtensionController(configuration: .default())
    }

    override func tearDown() {
        loader = nil
        delegateMock = nil
        storageProvider = nil
        controller = nil
        super.tearDown()
    }

    @MainActor
    func testWhenExtensionLoads_ThenDelegateIsCalledBeforeLoad() async throws {
        let identifier = "test-extension-id"
        let extensionURL = try createTestWebExtension()
        storageProvider.resolvedExtensionURL = extensionURL

        try await loader.loadWebExtension(identifier: identifier, into: controller)

        XCTAssertTrue(delegateMock.willLoadCalled)
        XCTAssertEqual(delegateMock.willLoadIdentifier, identifier)
        XCTAssertNotNil(delegateMock.willLoadContext)
        XCTAssertEqual(delegateMock.willLoadContext?.uniqueIdentifier, identifier)
    }

    @MainActor
    func testWhenExtensionLoadingFails_ThenDelegateIsNotCalled() async {
        let identifier = "test-extension-id"
        storageProvider.resolvedExtensionURL = nil

        do {
            try await loader.loadWebExtension(identifier: identifier, into: controller)
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertFalse(delegateMock.willLoadCalled)
        }
    }

    @MainActor
    func testWhenNoDelegateSet_ThenLoadingStillSucceeds() async throws {
        let identifier = "test-extension-id"
        let extensionURL = try createTestWebExtension()
        storageProvider.resolvedExtensionURL = extensionURL
        loader.delegate = nil

        let result = try await loader.loadWebExtension(identifier: identifier, into: controller)

        XCTAssertEqual(result.identifier, identifier)
        XCTAssertFalse(result.filename.isEmpty)
        XCTAssertEqual(result.displayName, "Test Extension")
        XCTAssertEqual(result.version, "1.0.0")
    }

    // MARK: - Test Helpers

    private func createTestWebExtension() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let extensionDir = tempDir.appendingPathComponent("TestExtension-\(UUID().uuidString)")

        let manifest = """
        {
            "manifest_version": 3,
            "name": "Test Extension",
            "version": "1.0.0",
            "description": "Minimal test extension for unit tests"
        }
        """

        try FileManager.default.createDirectory(at: extensionDir, withIntermediateDirectories: true)
        try manifest.write(to: extensionDir.appendingPathComponent("manifest.json"),
                          atomically: true, encoding: .utf8)

        addTeardownBlock {
            try? FileManager.default.removeItem(at: extensionDir)
        }

        return extensionDir
    }
}

// MARK: - Mock Delegate

@available(macOS 15.4, iOS 18.4, *)
final class WebExtensionLoadingDelegateMock: WebExtensionLoadingDelegate {

    var willLoadCalled = false
    var willLoadContext: WKWebExtensionContext?
    var willLoadIdentifier: String?

    func webExtensionLoader(_ loader: WebExtensionLoading,
                            willLoad context: WKWebExtensionContext,
                            identifier: String) {
        willLoadCalled = true
        willLoadContext = context
        willLoadIdentifier = identifier
    }
}

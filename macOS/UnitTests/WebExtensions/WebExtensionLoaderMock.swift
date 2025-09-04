//
//  WebExtensionLoaderMock.swift
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

@testable import DuckDuckGo_Privacy_Browser
import WebKit
import Foundation

@available(macOS 15.4, *)
final class WebExtensionLoadingMock: WebExtensionLoading {

    var loadWebExtensionCalled = false
    var loadWebExtensionsCalled = false
    var loadedPaths: [String] = []
    var mockLoadResult: WebExtensionLoadResult?
    var mockLoadResults: [Result<WebExtensionLoadResult, Error>] = []
    var mockError: Error?

    // Track created test extensions for cleanup
    private var createdTestExtensions: [URL] = []

    @discardableResult
    func loadWebExtension(path: String, into controller: WKWebExtensionController) async throws -> WebExtensionLoadResult {
        loadWebExtensionCalled = true
        loadedPaths.append(path)

        if let mockError = mockError {
            throw mockError
        }

        guard let mockLoadResult = mockLoadResult else {
            // Create a minimal web extension for testing
            let testExtensionURL = try createTestWebExtension()
            let mockExtension = try await WKWebExtension(resourceBaseURL: testExtensionURL)
            let mockContext = await WKWebExtensionContext(for: mockExtension)
            return WebExtensionLoadResult(context: mockContext, path: path)
        }

        return mockLoadResult
    }

    func loadWebExtensions(from paths: [String], into controller: WKWebExtensionController) async -> [Result<WebExtensionLoadResult, Error>] {
        loadWebExtensionsCalled = true
        loadedPaths = paths
        return mockLoadResults
    }

    func unloadExtension(at path: String, from controller: WKWebExtensionController) throws {
        // Mock implementation
    }

    // MARK: - Test Helper

    private func createTestWebExtension() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let extensionDir = tempDir.appendingPathComponent("TestExtension-\(UUID().uuidString)")

        // Create minimal manifest.json for web extension
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

        // Track for cleanup
        createdTestExtensions.append(extensionDir)

        return extensionDir
    }

    /// Clean up any test extensions created during testing
    func cleanupTestExtensions() {
        for extensionURL in createdTestExtensions {
            try? FileManager.default.removeItem(at: extensionURL)
        }
        createdTestExtensions.removeAll()
    }
}

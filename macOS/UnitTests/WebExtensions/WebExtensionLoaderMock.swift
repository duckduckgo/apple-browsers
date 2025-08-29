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

@available(macOS 15.4, *)
final class WebExtensionLoadingMock: WebExtensionLoading {

    var loadWebExtensionCalled = false
    var loadWebExtensionsCalled = false
    var loadedPaths: [String] = []
    var mockLoadResult: WebExtensionLoadResult?
    var mockLoadResults: [Result<WebExtensionLoadResult, Error>] = []
    var mockError: Error?

    @discardableResult
    func loadWebExtension(path: String, into controller: WKWebExtensionController) async throws -> WebExtensionLoadResult {
        loadWebExtensionCalled = true
        loadedPaths.append(path)

        if let mockError = mockError {
            throw mockError
        }

        guard let mockLoadResult = mockLoadResult else {
            // Create a default mock result for testing
            let mockExtension = try await WKWebExtension(resourceBaseURL: URL(fileURLWithPath: path))
            let mockContext = WKWebExtensionContext(webExtension: mockExtension)
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
}

//
//  WebExtensionStorageProvidingMock.swift
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
@testable import WebExtensions

@available(macOS 15.4, iOS 18.4, *)
final class WebExtensionStorageProvidingMock: WebExtensionStorageProviding {

    var fileManager: FileManager = .default
    var extensionsDirectory: URL = URL(fileURLWithPath: "/mock/extensions")

    var resolveInstalledExtensionCalled = false
    var resolveInstalledExtensionIdentifier: String?
    var shouldReturnNilForResolve = false
    var mockResolveResult: URL?
    var mockResolveFilename = "extension.xpi"
    func resolveInstalledExtension(identifier: String) -> URL? {
        resolveInstalledExtensionCalled = true
        resolveInstalledExtensionIdentifier = identifier
        if shouldReturnNilForResolve {
            return nil
        }
        if let mockResult = mockResolveResult {
            return mockResult
        }
        let identifierFolder = extensionsDirectory.appendingPathComponent(identifier)
        return identifierFolder.appendingPathComponent(mockResolveFilename)
    }

    var copyExtensionCalled = false
    var copyExtensionSourceURL: URL?
    var copyExtensionIdentifier: String?
    var mockCopyResult: URL?
    var mockCopyError: Error?
    func copyExtension(from sourceURL: URL, identifier: String) throws -> URL {
        copyExtensionCalled = true
        copyExtensionSourceURL = sourceURL
        copyExtensionIdentifier = identifier

        if let error = mockCopyError {
            throw error
        }

        if let result = mockCopyResult {
            return result
        }

        let identifierFolder = extensionsDirectory.appendingPathComponent(identifier)
        return identifierFolder.appendingPathComponent(sourceURL.lastPathComponent)
    }

    var removeExtensionCalled = false
    var removeExtensionIdentifier: String?
    var mockRemoveError: Error?
    func removeExtension(identifier: String) throws {
        removeExtensionCalled = true
        removeExtensionIdentifier = identifier

        if let error = mockRemoveError {
            throw error
        }
    }

    var cleanupOrphanedExtensionsCalled = false
    var cleanupOrphanedExtensionsKnownIdentifiers: Set<String>?
    func cleanupOrphanedExtensions(keeping knownIdentifiers: Set<String>) {
        cleanupOrphanedExtensionsCalled = true
        cleanupOrphanedExtensionsKnownIdentifiers = knownIdentifiers
    }
}

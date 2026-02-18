//
//  WKWebExtensionContextExtensionTests.swift
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
import WebKit
@testable import WebExtensions

@available(macOS 15.4, iOS 18.4, *)
final class WKWebExtensionContextExtensionTests: XCTestCase {

    private var createdExtensionURLs: [URL] = []

    override func tearDown() {
        for url in createdExtensionURLs {
            try? FileManager.default.removeItem(at: url)
        }
        createdExtensionURLs.removeAll()
        super.tearDown()
    }

    // MARK: - DuckDuckGoWebExtensionType enum

    func testWhenEmbeddedRawValue_ThenMatchesManifestId() {
        XCTAssertEqual(DuckDuckGoWebExtensionType.embedded.rawValue, "com.duckduckgo.web-extension.embedded")
    }

    // MARK: - duckDuckGoWebExtensionType with valid manifest

    @MainActor
    func testWhenManifestHasDuckDuckGoEmbeddedId_ThenReturnsEmbedded() async throws {
        let manifest = """
        {
            "manifest_version": 3,
            "name": "Test",
            "version": "1.0",
            "browser_specific_settings": {
                "duckduckgo": {
                    "id": "com.duckduckgo.web-extension.embedded"
                }
            }
        }
        """
        let context = try await makeContext(manifest: manifest)

        XCTAssertEqual(context.duckDuckGoWebExtensionType, .embedded)
    }

    // MARK: - duckDuckGoWebExtensionType returns nil

    @MainActor
    func testWhenManifestHasNoBrowserSpecificSettings_ThenReturnsNil() async throws {
        let manifest = """
        {
            "manifest_version": 3,
            "name": "Test",
            "version": "1.0"
        }
        """
        let context = try await makeContext(manifest: manifest)

        XCTAssertNil(context.duckDuckGoWebExtensionType)
    }

    @MainActor
    func testWhenManifestHasBrowserSpecificSettingsButNoDuckduckgo_ThenReturnsNil() async throws {
        let manifest = """
        {
            "manifest_version": 3,
            "name": "Test",
            "version": "1.0",
            "browser_specific_settings": {
                "gecko": { "id": "other@example.com" }
            }
        }
        """
        let context = try await makeContext(manifest: manifest)

        XCTAssertNil(context.duckDuckGoWebExtensionType)
    }

    @MainActor
    func testWhenManifestHasDuckduckgoButNoId_ThenReturnsNil() async throws {
        let manifest = """
        {
            "manifest_version": 3,
            "name": "Test",
            "version": "1.0",
            "browser_specific_settings": {
                "duckduckgo": {}
            }
        }
        """
        let context = try await makeContext(manifest: manifest)

        XCTAssertNil(context.duckDuckGoWebExtensionType)
    }

    @MainActor
    func testWhenManifestHasUnknownId_ThenReturnsNil() async throws {
        let manifest = """
        {
            "manifest_version": 3,
            "name": "Test",
            "version": "1.0",
            "browser_specific_settings": {
                "duckduckgo": {
                    "id": "com.unknown.extension"
                }
            }
        }
        """
        let context = try await makeContext(manifest: manifest)

        XCTAssertNil(context.duckDuckGoWebExtensionType)
    }

    // MARK: - Helpers

    @MainActor
    private func makeContext(manifest: String) async throws -> WKWebExtensionContext {
        let extensionDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WKWebExtensionContextExtensionTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: extensionDir, withIntermediateDirectories: true)
        createdExtensionURLs.append(extensionDir)

        try manifest.write(to: extensionDir.appendingPathComponent("manifest.json"),
                          atomically: true,
                          encoding: .utf8)

        let webExtension = try await WKWebExtension(resourceBaseURL: extensionDir)
        return WKWebExtensionContext(for: webExtension)
    }
}

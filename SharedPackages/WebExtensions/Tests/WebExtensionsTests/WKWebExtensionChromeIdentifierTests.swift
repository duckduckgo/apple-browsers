//
//  WKWebExtensionChromeIdentifierTests.swift
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

import WebKit
import XCTest

@testable import WebExtensions

@available(macOS 15.4, iOS 18.4, *)
final class WKWebExtensionChromeIdentifierTests: XCTestCase {

    /// The identifier Chrome derives from the 1Password key the patcher restores, and the one
    /// 1Password's host manifest lists in `allowed_origins`.
    private static let onePasswordIdentifier = "aeblfdkhhhdcdjpifhhbdiojplfjncoa"

    private var createdExtensionURLs: [URL] = []

    override func tearDown() {
        for url in createdExtensionURLs {
            try? FileManager.default.removeItem(at: url)
        }
        createdExtensionURLs.removeAll()
        super.tearDown()
    }

    // MARK: - chromeExtensionIdentifier

    func testWhenManifestHasOnePasswordKey_ThenIdentifierMatchesChromeWebStoreIdentifier() async throws {
        let onePasswordKey = try XCTUnwrap(WebExtensionManifestKeyPatcher.knownPublicKeys["1Password"])
        let webExtension = try await makeExtension(manifest: manifest(key: onePasswordKey))

        XCTAssertEqual(webExtension.chromeExtensionIdentifier, Self.onePasswordIdentifier)
    }

    func testWhenManifestHasNoKey_ThenIdentifierIsNil() async throws {
        let webExtension = try await makeExtension(manifest: manifest(key: nil))

        XCTAssertNil(webExtension.chromeExtensionIdentifier)
    }

    func testWhenManifestKeyIsNotBase64_ThenIdentifierIsNil() async throws {
        let webExtension = try await makeExtension(manifest: manifest(key: "not base64 at all!!"))

        XCTAssertNil(webExtension.chromeExtensionIdentifier)
    }

    func testWhenManifestKeyIsEmpty_ThenIdentifierIsNil() async throws {
        let webExtension = try await makeExtension(manifest: manifest(key: ""))

        XCTAssertNil(webExtension.chromeExtensionIdentifier)
    }

    // MARK: - chromeExtensionOrigin

    func testWhenManifestHasOnePasswordKey_ThenOriginIsChromeExtensionOrigin() async throws {
        let onePasswordKey = try XCTUnwrap(WebExtensionManifestKeyPatcher.knownPublicKeys["1Password"])
        let webExtension = try await makeExtension(manifest: manifest(key: onePasswordKey))

        XCTAssertEqual(webExtension.chromeExtensionOrigin, "chrome-extension://\(Self.onePasswordIdentifier)/")
    }

    // MARK: - Helpers

    private func manifest(key: String?) -> String {
        let keyEntry = key.map { ",\n    \"key\": \"\($0)\"" } ?? ""
        return """
        {
            "manifest_version": 3,
            "name": "Test",
            "version": "1.0"\(keyEntry)
        }
        """
    }

    private func makeExtension(manifest: String) async throws -> WKWebExtension {
        let extensionDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WKWebExtensionChromeIdentifierTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: extensionDir, withIntermediateDirectories: true)
        createdExtensionURLs.append(extensionDir)

        try manifest.write(to: extensionDir.appendingPathComponent("manifest.json"),
                           atomically: true,
                           encoding: .utf8)

        return try await WKWebExtension(resourceBaseURL: extensionDir)
    }
}

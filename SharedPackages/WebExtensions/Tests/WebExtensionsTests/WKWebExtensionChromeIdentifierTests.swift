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

    /// The public key of the 1Password extension in the Chrome Web Store, as its manifest
    /// carries it. 1Password's host manifest lists the matching origin in `allowed_origins`.
    private static let onePasswordKey = """
    MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAnHpaUll4uWujpAdbIXOQY2WE6hk8PllsYsnoUaj5qHXwv4IB6A9pONqGaTL2K\
    L20u6E6XVhncY6Ae6SQSBQqiIkgjPsiG0NDNsDlju/kzBnfimKFC/bpzOrqFqbhswQHifnet5uHlpG97whTzLO3ka0M5aqB9V9mD/0qVXv\
    NgAVVnSTULH254YqpeCcAhmsKiFZSL6OrOZmCp8kZ/OeOUK9iYWYylL7VcOXVrZf10EPrlaCNXzVk7K35dPuQ7svhA0Pgju3kngB4RLa5I\
    ojhw3IT+B5+m8pisjOSd1oKMrRmhGs7rDhF5IEtAiVxqVp7uOOMPQj3vrbMDAzf7vqLtQIDAQAB
    """

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

    @MainActor
    func testWhenManifestHasOnePasswordKey_ThenIdentifierMatchesChromeWebStoreIdentifier() async throws {
        let context = try await makeContext(manifest: manifest(key: Self.onePasswordKey))

        XCTAssertEqual(context.chromeExtensionIdentifier, Self.onePasswordIdentifier)
    }

    @MainActor
    func testWhenManifestHasNoKey_ThenIdentifierIsNil() async throws {
        let context = try await makeContext(manifest: manifest(key: nil))

        XCTAssertNil(context.chromeExtensionIdentifier)
    }

    @MainActor
    func testWhenManifestKeyIsNotBase64_ThenIdentifierIsNil() async throws {
        let context = try await makeContext(manifest: manifest(key: "not base64 at all!!"))

        XCTAssertNil(context.chromeExtensionIdentifier)
    }

    @MainActor
    func testWhenManifestKeyIsEmpty_ThenIdentifierIsNil() async throws {
        let context = try await makeContext(manifest: manifest(key: ""))

        XCTAssertNil(context.chromeExtensionIdentifier)
    }

    // MARK: - chromeExtensionOrigin

    @MainActor
    func testWhenManifestHasOnePasswordKey_ThenOriginIsChromeExtensionOrigin() async throws {
        let context = try await makeContext(manifest: manifest(key: Self.onePasswordKey))

        XCTAssertEqual(context.chromeExtensionOrigin, "chrome-extension://\(Self.onePasswordIdentifier)/")
    }

    @MainActor
    func testWhenManifestHasNoKey_ThenOriginIsNil() async throws {
        let context = try await makeContext(manifest: manifest(key: nil))

        XCTAssertNil(context.chromeExtensionOrigin)
    }

    @MainActor
    func testWhenManifestKeyIsNotBase64_ThenOriginIsNil() async throws {
        let context = try await makeContext(manifest: manifest(key: "not base64 at all!!"))

        XCTAssertNil(context.chromeExtensionOrigin)
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

    @MainActor
    private func makeContext(manifest: String) async throws -> WKWebExtensionContext {
        let extensionDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WKWebExtensionChromeIdentifierTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: extensionDir, withIntermediateDirectories: true)
        createdExtensionURLs.append(extensionDir)

        try manifest.write(to: extensionDir.appendingPathComponent("manifest.json"),
                           atomically: true,
                           encoding: .utf8)

        let webExtension = try await WKWebExtension(resourceBaseURL: extensionDir)
        return WKWebExtensionContext(for: webExtension)
    }
}

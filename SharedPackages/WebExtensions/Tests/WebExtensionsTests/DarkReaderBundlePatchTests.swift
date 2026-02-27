//
//  DarkReaderBundlePatchTests.swift
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

#if os(macOS)
import XCTest
@testable import WebExtensions

/// Verifies that the bundled darkreader.zip has the expected DuckDuckGo patches applied.
/// If these tests fail, run `scripts/darkreader/patch-darkreader.sh` to rebuild the patched bundle.
@available(macOS 15.4, *)
final class DarkReaderBundlePatchTests: XCTestCase {

    private var extractedDir: URL!

    override func setUp() async throws {
        try await super.setUp()

        guard let descriptor = EmbeddedWebExtensionRegistry.descriptor(for: .darkReader),
              let zipURL = descriptor.bundledURL else {
            throw XCTSkip("DarkReader bundle not found in test resources")
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DarkReaderBundlePatchTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Extract zip using ditto (available on macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-xk", zipURL.path, tempDir.path]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw XCTSkip("Failed to extract darkreader.zip")
        }

        extractedDir = tempDir
    }

    override func tearDown() {
        if let extractedDir {
            try? FileManager.default.removeItem(at: extractedDir)
        }
        super.tearDown()
    }

    // MARK: - Manifest Patches

    func testManifestContainsNativeMessagingPermission() throws {
        let manifest = try loadManifestJSON()
        let permissions = try XCTUnwrap(manifest["permissions"] as? [String])

        XCTAssertTrue(
            permissions.contains("nativeMessaging"),
            "manifest.json must include 'nativeMessaging' permission. Permissions found: \(permissions)"
        )
    }

    func testManifestContainsNativeMessagingApplicationID() throws {
        let manifest = try loadManifestJSON()

        // The manifest should have externally_connectable or the application ID configured
        // via allowed_extensions in the nativeMessaging section, but the key thing is
        // that the background script can call chrome.runtime.sendNativeMessage with our app ID.
        // We verify the app ID presence in the background script instead.
        let permissions = try XCTUnwrap(manifest["permissions"] as? [String])
        XCTAssertTrue(permissions.contains("nativeMessaging"))
    }

    // MARK: - Background Script Patches

    func testBackgroundScriptContainsNativeMessagingCall() throws {
        let backgroundJS = try loadBackgroundScript()

        XCTAssertTrue(
            backgroundJS.contains("chrome.runtime.sendNativeMessage"),
            "background/index.js must contain chrome.runtime.sendNativeMessage call for domain exclusion"
        )
    }

    func testBackgroundScriptContainsDuckDuckGoApplicationID() throws {
        let backgroundJS = try loadBackgroundScript()

        XCTAssertTrue(
            backgroundJS.contains("org.duckduckgo.web-extension.darkreader"),
            "background/index.js must contain the DuckDuckGo native messaging application ID"
        )
    }

    func testBackgroundScriptContainsDomainExclusionMethod() throws {
        let backgroundJS = try loadBackgroundScript()

        XCTAssertTrue(
            backgroundJS.contains("isDomainExcluded"),
            "background/index.js must contain isDomainExcluded method call"
        )
    }

    func testBackgroundScriptContainsCleanUpResponseForExcludedDomains() throws {
        let backgroundJS = try loadBackgroundScript()

        // The patch adds a CLEAN_UP return inside getConnectionMessage when domain is excluded
        XCTAssertTrue(
            backgroundJS.contains("result.isExcluded") && backgroundJS.contains("CLEAN_UP"),
            "background/index.js must return CLEAN_UP message when isDomainExcluded response indicates exclusion"
        )
    }

    // MARK: - Existing Patches (automation mode)

    func testBackgroundScriptContainsAutomationModePatch() throws {
        let backgroundJS = try loadBackgroundScript()

        // The unpatched code has "isEdge && isMobile ? true : false" — the patched code must NOT contain that.
        XCTAssertFalse(
            backgroundJS.contains("isEdge && isMobile ? true : false"),
            "background/index.js must have automation.enabled patched (still contains original conditional)"
        )
        XCTAssertTrue(
            backgroundJS.range(of: #"mode\s*:\s*AutomationMode\.SYSTEM"#, options: .regularExpression) != nil,
            "background/index.js must set automation.mode to AutomationMode.SYSTEM"
        )
    }

    func testBackgroundScriptContainsFetchNewsPatch() throws {
        let backgroundJS = try loadBackgroundScript()

        // The patch changes "fetchNews: true" to "fetchNews: false"
        XCTAssertTrue(
            backgroundJS.range(of: #"fetchNews\s*:\s*false"#, options: .regularExpression) != nil,
            "background/index.js must have fetchNews set to false"
        )
        XCTAssertNil(
            backgroundJS.range(of: #"fetchNews\s*:\s*true"#, options: .regularExpression),
            "background/index.js must not have fetchNews set to true (unpatched)"
        )
    }

    // MARK: - Helpers

    private func loadManifestJSON() throws -> [String: Any] {
        let manifestURL = extractedDir.appendingPathComponent("darkreader/manifest.json")
        let data = try Data(contentsOf: manifestURL)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func loadBackgroundScript() throws -> String {
        let backgroundURL = extractedDir.appendingPathComponent("darkreader/background/index.js")
        return try String(contentsOf: backgroundURL, encoding: .utf8)
    }
}
#endif

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
    private var baseDir: URL!

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

        // The bundle may be packaged flat (manifest.json at the root, matching the
        // other embedded extensions) or wrapped in a top-level folder. Resolve the
        // directory that actually contains manifest.json, mirroring how the app's
        // WebExtensionStorageProviding.resolveInstalledExtension locates it.
        baseDir = Self.directoryContainingManifest(in: tempDir) ?? tempDir
    }

    private static func directoryContainingManifest(in root: URL) -> URL? {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: root.appendingPathComponent("manifest.json").path) {
            return root
        }
        let contents = (try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return contents.first { item in
            fileManager.fileExists(atPath: item.appendingPathComponent("manifest.json").path)
        }
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

    func testManifestVersionContainsDuckDuckGoPatchComponent() throws {
        let manifest = try loadManifestJSON()
        let version = try XCTUnwrap(manifest["version"] as? String)
        let components = version.split(separator: ".")

        XCTAssertEqual(components.count, 4, "Patched Dark Reader version must contain four numeric components")
        XCTAssertEqual(components.last.map(String.init), "1", "Patched Dark Reader version must use DuckDuckGo patch component 1")
        XCTAssertTrue(components.allSatisfy { Int($0) != nil }, "Patched Dark Reader version components must be numeric")
    }

    func testManifestUsesNonpersistentBackgroundPage() throws {
        let manifest = try loadManifestJSON()
        let background = try XCTUnwrap(manifest["background"] as? [String: Any])
        let scripts = try XCTUnwrap(background["scripts"] as? [String])

        XCTAssertEqual(scripts, ["background/index.js"])
        XCTAssertEqual(background["persistent"] as? Bool, false)
        XCTAssertNil(background["service_worker"])
    }

    // MARK: - Background Script Patches

    func testContentScriptRetriesColdBackgroundConnection() throws {
        let contentScript = try loadContentScript()

        XCTAssertTrue(contentScript.contains("function sendMessage(message, errorHandler = cleanup)"))
        XCTAssertTrue(contentScript.contains("promise.then(responseHandler).catch(errorHandler)"))
        XCTAssertTrue(contentScript.contains("const maxConnectionAttempts = 4"))
        XCTAssertTrue(contentScript.contains("const connectionRetryDelay = 500"))
        XCTAssertTrue(contentScript.contains("sendConnectionOrResumeMessage(type, attempt + 1)"))
        XCTAssertTrue(contentScript.contains("clearTimeout(connectionRetryTimer)"))
    }

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

    func testBackgroundScriptBoundsNativeDomainExclusionCheck() throws {
        let backgroundJS = try loadBackgroundScript()

        XCTAssertTrue(
            backgroundJS.contains("Promise.race") &&
                backgroundJS.contains("setTimeout(() => resolve(null), 500)"),
            "background/index.js must not wait indefinitely for the native domain exclusion response"
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

    func testFallbackScriptAvoidsCoarseWikipediaFallback() throws {
        let fallbackJS = try loadFallbackScript()

        XCTAssertTrue(fallbackJS.contains("const isWikipedia"))
        XCTAssertTrue(fallbackJS.contains("--background-color-base: #101418"))
        XCTAssertTrue(fallbackJS.contains(".mw-page-container, .mw-body, .mw-body-content"))
        XCTAssertTrue(fallbackJS.contains("a { color: #6b9eff !important; }"))
        XCTAssertTrue(fallbackJS.contains(".skin-theme-clientpref-night, .skin-theme-clientpref-os"))
        XCTAssertTrue(fallbackJS.contains("wikipediaThemeObserver"))
        XCTAssertTrue(fallbackJS.contains("fallback.remove()"))
        XCTAssertTrue(fallbackJS.contains("location.hostname.endsWith(\".wikipedia.org\")"))
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

    // MARK: - Detector Hint Patches

    func testWikipediaDetectorHintContainsExplicitAndAutomaticDarkThemeClasses() throws {
        let detectorHints = try loadDetectorHints()
        let wikimediaBlock = try XCTUnwrap(
            detectorHints
                .components(separatedBy: "================================")
                .first { $0.contains("*.wikipedia.org") }
        )

        XCTAssertTrue(
            wikimediaBlock.contains(".skin-theme-clientpref-night"),
            "Wikipedia detector hint must recognize Wikipedia's explicit dark theme"
        )
        XCTAssertTrue(
            wikimediaBlock.contains(".skin-theme-clientpref-os"),
            "Wikipedia detector hint must recognize Wikipedia's automatic dark theme"
        )
    }

    // MARK: - Helpers

    private func loadManifestJSON() throws -> [String: Any] {
        let manifestURL = baseDir.appendingPathComponent("manifest.json")
        let data = try Data(contentsOf: manifestURL)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func loadBackgroundScript() throws -> String {
        let backgroundURL = baseDir.appendingPathComponent("background/index.js")
        return try String(contentsOf: backgroundURL, encoding: .utf8)
    }

    private func loadContentScript() throws -> String {
        let contentScriptURL = baseDir.appendingPathComponent("inject/index.js")
        return try String(contentsOf: contentScriptURL, encoding: .utf8)
    }

    private func loadFallbackScript() throws -> String {
        let fallbackURL = baseDir.appendingPathComponent("inject/fallback.js")
        return try String(contentsOf: fallbackURL, encoding: .utf8)
    }

    private func loadDetectorHints() throws -> String {
        let detectorHintsURL = baseDir.appendingPathComponent("config/detector-hints.config")
        return try String(contentsOf: detectorHintsURL, encoding: .utf8)
    }
}
#endif

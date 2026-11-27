//
//  WebExtensionAvailabilityTests.swift
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

import FeatureFlags_macOS
import PrivacyConfig
import WebExtensions
import WebKit
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@available(macOS 15.4, *)
@MainActor
final class WebExtensionAvailabilityTests: XCTestCase {

    private var flags: MockFeatureFlagger!
    private var manager: StubWebExtensionManager!
    private var extensionDirectories: [URL] = []

    override func setUp() {
        super.setUp()
        flags = MockFeatureFlagger(featuresStub: [:])
        manager = StubWebExtensionManager()
    }

    override func tearDown() {
        extensionDirectories.forEach { try? FileManager.default.removeItem(at: $0) }
        extensionDirectories = []
        flags = nil
        manager = nil
        super.tearDown()
    }

    // MARK: - isAppleSurrogateRedirectionEnabled

    private func makeSUT(isOSSupported: Bool = true) -> WebExtensionAvailability {
        WebExtensionAvailability(featureFlagger: flags,
                                 isSurrogateRedirectionOSSupported: isOSSupported,
                                 webExtensionManagerProvider: { [manager] in manager })
    }

    private func setFlags(_ enabled: [FeatureFlag]) {
        flags.featuresStub = Dictionary(uniqueKeysWithValues: enabled.map { ($0.rawValue, true) })
    }

    private func isEnabled(flags enabled: [FeatureFlag],
                           isOSSupported: Bool = true,
                           isEmbeddedExtensionLoaded: Bool = true) async throws -> Bool {
        if isEmbeddedExtensionLoaded {
            try await loadExtension(withIdentifier: DuckDuckGoWebExtensionType.embedded.rawValue)
        }
        setFlags(enabled)
        return makeSUT(isOSSupported: isOSSupported).isAppleSurrogateRedirectionEnabled
    }

    func testWhenAllConditionsAreMetThenEnabled() async throws {
        let isEnabled = try await isEnabled(flags: [.embeddedExtension, .appleSurrogateRedirection])
        XCTAssertTrue(isEnabled)
    }

    func testWhenOSIsNotSupportedThenDisabled() async throws {
        let isEnabled = try await isEnabled(flags: [.embeddedExtension, .appleSurrogateRedirection], isOSSupported: false)
        XCTAssertFalse(isEnabled)
    }

    func testWhenEmbeddedExtensionIsOffThenDisabled() async throws {
        let isEnabled = try await isEnabled(flags: [.appleSurrogateRedirection])
        XCTAssertFalse(isEnabled)
    }

    func testWhenAppleSurrogateRedirectionFlagIsOffThenDisabled() async throws {
        let isEnabled = try await isEnabled(flags: [.embeddedExtension])
        XCTAssertFalse(isEnabled)
    }

    // Both flags on but nothing to serve surrogates: C-S-S must keep injecting them.
    func testWhenEmbeddedExtensionIsNotLoadedThenDisabled() async throws {
        let isEnabled = try await isEnabled(flags: [.embeddedExtension, .appleSurrogateRedirection], isEmbeddedExtensionLoaded: false)
        XCTAssertFalse(isEnabled)
    }

    func testWhenNoManagerExistsThenDisabled() {
        setFlags([.embeddedExtension, .appleSurrogateRedirection])
        let sut = WebExtensionAvailability(featureFlagger: flags,
                                           isSurrogateRedirectionOSSupported: true,
                                           webExtensionManagerProvider: { nil })
        XCTAssertFalse(sut.isAppleSurrogateRedirectionEnabled)
    }

    func testWhenOnlyAnotherExtensionIsLoadedThenDisabled() async throws {
        try await loadExtension(withIdentifier: DuckDuckGoWebExtensionType.darkReader.rawValue)
        setFlags([.embeddedExtension, .appleSurrogateRedirection])

        XCTAssertFalse(makeSUT().isAppleSurrogateRedirectionEnabled)
    }

    func testWhenFlagsAndLoadedExtensionsChangeWhileRunningThenCheckFollows() async throws {
        let sut = makeSUT()
        setFlags([.embeddedExtension, .appleSurrogateRedirection])
        XCTAssertFalse(sut.isAppleSurrogateRedirectionEnabled)

        try await loadExtension(withIdentifier: DuckDuckGoWebExtensionType.embedded.rawValue)
        XCTAssertTrue(sut.isAppleSurrogateRedirectionEnabled)

        setFlags([.embeddedExtension])
        XCTAssertFalse(sut.isAppleSurrogateRedirectionEnabled)

        setFlags([.embeddedExtension, .appleSurrogateRedirection])
        XCTAssertTrue(sut.isAppleSurrogateRedirectionEnabled)

        // The extension is unloaded, e.g. by the remote disable enforcer.
        manager.loadedExtensions = []
        XCTAssertFalse(sut.isAppleSurrogateRedirectionEnabled)
    }

    // MARK: - isAppleSurrogateRedirectionConfigured

    // Content blocking rules are compiled before the extension loads, so this must not wait for it.
    func testWhenFlagsAreOnButExtensionIsNotLoadedThenRedirectionIsConfigured() {
        setFlags([.embeddedExtension, .appleSurrogateRedirection])

        XCTAssertTrue(makeSUT().isAppleSurrogateRedirectionConfigured)
        XCTAssertFalse(makeSUT().isAppleSurrogateRedirectionEnabled)
    }

    func testWhenAnyConfiguredConditionIsMissingThenRedirectionIsNotConfigured() {
        setFlags([.appleSurrogateRedirection])
        XCTAssertFalse(makeSUT().isAppleSurrogateRedirectionConfigured)

        setFlags([.embeddedExtension])
        XCTAssertFalse(makeSUT().isAppleSurrogateRedirectionConfigured)

        setFlags([.embeddedExtension, .appleSurrogateRedirection])
        XCTAssertFalse(makeSUT(isOSSupported: false).isAppleSurrogateRedirectionConfigured)
    }

    // MARK: - Helpers

    // The type is read from the manifest, so the fixture only needs an id.
    private func loadExtension(withIdentifier identifier: String) async throws {
        let manifest = """
        {
            "manifest_version": 3,
            "name": "Test Extension",
            "version": "1.0",
            "browser_specific_settings": {
                "duckduckgo": {
                    "id": "\(identifier)"
                }
            }
        }
        """

        let extensionDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WebExtensionAvailabilityTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: extensionDirectory, withIntermediateDirectories: true)
        extensionDirectories.append(extensionDirectory)
        try manifest.write(to: extensionDirectory.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)

        let webExtension = try await WKWebExtension(resourceBaseURL: extensionDirectory)
        manager.loadedExtensions = [WKWebExtensionContext(for: webExtension)]
    }
}

/// A web extension manager whose only behaviour is the set of loaded extensions, which is all
/// `WebExtensionAvailability` reads.
@available(macOS 15.4, *)
private final class StubWebExtensionManager: WebExtensionManaging {
    var loadedExtensions: Set<WKWebExtensionContext> = []
    let cpmMessagingHealthMonitor: CPMMessagingHealthMonitoring = NoOpCPMMessagingHealthMonitor()
    let badgeColors = WebExtensionBadgeColorStore()
    let eventsListener: WebExtensionEventsListening = WebExtensionEventsListener()
    let extensionsDirectory = FileManager.default.temporaryDirectory
    let webExtensionIdentifiers: [String] = []
    let extensionUpdates = AsyncStream<Void>.makeStream().stream
    let lifecycleEvents = AsyncStream<WebExtensionLifecycleEvent>.makeStream().stream

    func attachExtensions(to configuration: WKWebViewConfiguration) {}
    func loadInstalledExtensions() async {}
    func reloadInstalledExtensions() async {}
    func installExtension(from sourceURL: URL) async throws {}
    func installExtension(from sourceURL: URL, storeIdentity: WebExtensionStoreIdentity?, replacing oldIdentifier: String?) async throws {}
    func uninstallExtension(identifier: String) throws {}
    func uninstallAllExtensions() -> [Result<Void, Error>] { [] }
    func syncEmbeddedExtensions(enabledTypes: Set<DuckDuckGoWebExtensionType>) async {}
    func uninstallEmbeddedExtension(type: DuckDuckGoWebExtensionType) {}
    func installedEmbeddedExtension(for type: DuckDuckGoWebExtensionType) -> InstalledWebExtension? { nil }
    func installedExtensionPath(for type: DuckDuckGoWebExtensionType) -> URL? { nil }
    func unloadAllExtensions() {}
    func reloadExtension(identifier: String) async throws {}
    func disableExtension(identifier: String) async throws {}
    func enableExtension(identifier: String) async throws {}
    func installedExtension(identifier: String) -> InstalledWebExtension? { nil }
    func isRemotelyDisabled(identifier: String) -> Bool { false }
    func extensionName(for identifier: String) -> String? { nil }
    func extensionVersion(for identifier: String) -> String? { nil }
    func extensionPermissions(for identifier: String) -> [String] { [] }
    func extensionMatchPatterns(for identifier: String) -> [String] { [] }
    func hasAccessToPrivateData(for identifier: String) -> Bool? { nil }
    @MainActor func hasHitNativeMessagingLimitation(identifier: String) -> Bool { false }
    @MainActor func isNativeMessagingAlertSuppressed(identifier: String) -> Bool { false }
    @MainActor func suppressNativeMessagingAlert(identifier: String) {}
    @MainActor func pixelExtension(identifier: String) -> WebExtensionPixelExtension { .other }
    func setHasAccessToPrivateData(_ allowed: Bool, for identifier: String) throws {}
    func extensionContext(for url: URL) -> WKWebExtensionContext? { nil }
    func context(for identifier: String) -> WKWebExtensionContext? { nil }
    func clearCachedScriptlets() {}
    func scriptletDebugInfo() -> [ScriptletDebugInfo] { [] }
}

//
//  WebExtensionAvailabilityTests.swift
//  DuckDuckGo
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
@testable import DuckDuckGo
import BrowserServicesKit
import Core
import WebExtensions
import WebExtensionsTestSupport
import WebKit

@available(iOS 18.4, *)
final class WebExtensionAvailabilityTests: XCTestCase {

    private var mockFeatureFlagger: MockFeatureFlagger!
    private var mockWebExtensionManager: MockWebExtensionManaging!
    private var extensionDirectories: [URL] = []

    override func setUp() {
        super.setUp()
        mockFeatureFlagger = MockFeatureFlagger()
        mockFeatureFlagger.enabledFeatureFlags = [.webExtensions, .embeddedExtension]
        mockWebExtensionManager = MockWebExtensionManaging()
    }

    override func tearDown() {
        extensionDirectories.forEach { try? FileManager.default.removeItem(at: $0) }
        extensionDirectories = []
        mockFeatureFlagger = nil
        mockWebExtensionManager = nil
        super.tearDown()
    }

    private func makeSUT(isNativeMessagingSupported: Bool = true) -> WebExtensionAvailability {
        WebExtensionAvailability(
            featureFlagger: mockFeatureFlagger,
            nativeMessagingSupport: NativeMessagingSupport(isSupported: isNativeMessagingSupported),
            webExtensionManagerProvider: { [mockWebExtensionManager] in mockWebExtensionManager }
        )
    }

    // MARK: - isAvailable

    func testWhenWebExtensionsFlagIsOnThenWebExtensionsAreAvailable() {
        XCTAssertTrue(makeSUT().isAvailable)
    }

    func testWhenWebExtensionsFlagIsOffThenWebExtensionsAreNotAvailable() {
        mockFeatureFlagger.enabledFeatureFlags = [.embeddedExtension]

        XCTAssertFalse(makeSUT().isAvailable)
    }

    // MARK: - isAutoconsentExtensionAvailable

    @MainActor
    func testWhenEmbeddedExtensionIsLoadedThenAutoconsentExtensionIsAvailable() async throws {
        try await loadEmbeddedExtension()

        XCTAssertTrue(makeSUT().isAutoconsentExtensionAvailable)
    }

    /// The Alpha case: the extension is loaded and both flags are on, but its service worker cannot
    /// reach the app, so the native autoconsent user script has to take over.
    @MainActor
    func testWhenNativeMessagingIsNotSupportedThenAutoconsentExtensionIsNotAvailable() async throws {
        try await loadEmbeddedExtension()

        XCTAssertFalse(makeSUT(isNativeMessagingSupported: false).isAutoconsentExtensionAvailable)
    }

    @MainActor
    func testWhenOnlyAnotherExtensionIsLoadedThenAutoconsentExtensionIsNotAvailable() async throws {
        try await loadExtension(withIdentifier: DuckDuckGoWebExtensionType.darkReader.rawValue)

        XCTAssertFalse(makeSUT().isAutoconsentExtensionAvailable)
    }

    func testWhenNoExtensionIsLoadedThenAutoconsentExtensionIsNotAvailable() {
        XCTAssertFalse(makeSUT().isAutoconsentExtensionAvailable)
    }

    @MainActor
    func testWhenWebExtensionsFlagIsOffThenAutoconsentExtensionIsNotAvailable() async throws {
        try await loadEmbeddedExtension()
        mockFeatureFlagger.enabledFeatureFlags = [.embeddedExtension]

        XCTAssertFalse(makeSUT().isAutoconsentExtensionAvailable)
    }

    @MainActor
    func testWhenEmbeddedExtensionFlagIsOffThenAutoconsentExtensionIsNotAvailable() async throws {
        try await loadEmbeddedExtension()
        mockFeatureFlagger.enabledFeatureFlags = [.webExtensions]

        XCTAssertFalse(makeSUT().isAutoconsentExtensionAvailable)
    }

    // MARK: - Helpers

    @MainActor
    private func loadEmbeddedExtension() async throws {
        try await loadExtension(withIdentifier: DuckDuckGoWebExtensionType.embedded.rawValue)
    }

    /// Extension types are read from the manifest, so the fixture only needs enough of one to
    /// resolve an identifier.
    @MainActor
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

        try manifest.write(to: extensionDirectory.appendingPathComponent("manifest.json"),
                           atomically: true,
                           encoding: .utf8)

        let webExtension = try await WKWebExtension(resourceBaseURL: extensionDirectory)
        mockWebExtensionManager.loadedExtensions = [WKWebExtensionContext(for: webExtension)]
    }
}

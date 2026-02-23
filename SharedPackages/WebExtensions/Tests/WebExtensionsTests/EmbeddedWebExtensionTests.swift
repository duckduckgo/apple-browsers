//
//  EmbeddedWebExtensionTests.swift
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
@testable import WebExtensions

@available(macOS 15.4, iOS 18.4, *)
final class EmbeddedWebExtensionTests: XCTestCase {

    // MARK: - InstalledWebExtension Tests

    func testWhenEmbeddedTypeIsSet_ThenIsEmbeddedReturnsTrue() {
        let extension1 = InstalledWebExtension(
            uniqueIdentifier: "test-id",
            filename: "test.zip",
            name: "Test",
            version: "1.0.0",
            embeddedType: .embedded
        )

        XCTAssertTrue(extension1.isEmbedded)
        XCTAssertEqual(extension1.embeddedType, .embedded)
    }

    func testWhenEmbeddedTypeIsNil_ThenIsEmbeddedReturnsFalse() {
        let extension1 = InstalledWebExtension(
            uniqueIdentifier: "test-id",
            filename: "test.zip",
            name: "Test",
            version: "1.0.0"
        )

        XCTAssertFalse(extension1.isEmbedded)
        XCTAssertNil(extension1.embeddedType)
    }

    func testInstalledWebExtensionWithEmbeddedType_IsCodable() throws {
        let original = InstalledWebExtension(
            uniqueIdentifier: "test-id",
            filename: "test.zip",
            name: "Test",
            version: "1.0.0",
            embeddedType: .embedded
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(InstalledWebExtension.self, from: data)

        XCTAssertEqual(original, decoded)
        XCTAssertEqual(decoded.embeddedType, .embedded)
    }

    func testInstalledWebExtensionWithoutEmbeddedType_IsCodable() throws {
        let original = InstalledWebExtension(
            uniqueIdentifier: "test-id",
            filename: "test.zip",
            name: "Test",
            version: "1.0.0"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(InstalledWebExtension.self, from: data)

        XCTAssertEqual(original, decoded)
        XCTAssertNil(decoded.embeddedType)
    }

    // MARK: - EmbeddedWebExtensionRegistry Tests

    func testRegistryContainsEmbeddedExtension() {
        let descriptor = EmbeddedWebExtensionRegistry.descriptor(for: .embedded)

        XCTAssertNotNil(descriptor)
        XCTAssertEqual(descriptor?.type, .embedded)
        XCTAssertEqual(descriptor?.resourceFilename, "com.duckduckgo.web-extension.embedded.zip")
    }

    func testRegistryAllContainsExpectedExtensions() {
        XCTAssertFalse(EmbeddedWebExtensionRegistry.all.isEmpty)
        XCTAssertTrue(EmbeddedWebExtensionRegistry.all.contains { $0.type == .embedded })
    }

    // MARK: - DuckDuckGoWebExtensionType Tests

    func testDuckDuckGoWebExtensionType_IsCodable() throws {
        let original = DuckDuckGoWebExtensionType.embedded

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(DuckDuckGoWebExtensionType.self, from: data)

        XCTAssertEqual(original, decoded)
    }

    func testDuckDuckGoWebExtensionType_RawValue() {
        XCTAssertEqual(DuckDuckGoWebExtensionType.embedded.rawValue, "com.duckduckgo.web-extension.embedded")
    }

    // MARK: - WebExtensionMetadata Tests

    func testWebExtensionMetadata_Properties() {
        let metadata = WebExtensionMetadata(
            type: .embedded,
            version: "1.0.0",
            displayName: "Test Extension"
        )

        XCTAssertEqual(metadata.type, .embedded)
        XCTAssertEqual(metadata.version, "1.0.0")
        XCTAssertEqual(metadata.displayName, "Test Extension")
    }
}

// MARK: - Version Comparison Tests

@available(macOS 15.4, iOS 18.4, *)
final class VersionComparisonTests: XCTestCase {

    var manager: WebExtensionManager!
    var installedExtensionStoringMock: InstalledWebExtensionStoringMock!
    var storageProvidingMock: WebExtensionStorageProvidingMock!
    var webExtensionLoadingMock: WebExtensionLoadingMock!
    var windowTabProviderMock: WebExtensionWindowTabProvidingMock!
    var configurationMock: WebExtensionConfigurationProvidingMock!

    @MainActor
    override func setUp() {
        super.setUp()
        installedExtensionStoringMock = InstalledWebExtensionStoringMock()
        storageProvidingMock = WebExtensionStorageProvidingMock()
        webExtensionLoadingMock = WebExtensionLoadingMock()
        windowTabProviderMock = WebExtensionWindowTabProvidingMock()
        configurationMock = WebExtensionConfigurationProvidingMock()

        manager = WebExtensionManager(
            configuration: configurationMock,
            windowTabProvider: windowTabProviderMock,
            storageProvider: storageProvidingMock,
            installationStore: installedExtensionStoringMock,
            loader: webExtensionLoadingMock
        )
    }

    override func tearDown() {
        webExtensionLoadingMock?.cleanupTestExtensions()
        manager = nil
        installedExtensionStoringMock = nil
        storageProvidingMock = nil
        webExtensionLoadingMock = nil
        windowTabProviderMock = nil
        configurationMock = nil
        super.tearDown()
    }

    // MARK: - installedEmbeddedExtension Tests

    func testWhenNoEmbeddedExtensionInstalled_ThenReturnsNil() {
        installedExtensionStoringMock.installedExtensions = [
            InstalledWebExtension(uniqueIdentifier: "user-ext", filename: "user.zip", name: "User", version: "1.0.0")
        ]

        let result = manager.installedEmbeddedExtension(for: .embedded)

        XCTAssertNil(result)
    }

    func testWhenEmbeddedExtensionInstalled_ThenReturnsIt() {
        let embeddedExt = InstalledWebExtension(
            uniqueIdentifier: "embedded-id",
            filename: "duckduckgo-embedded-web-extension.zip",
            name: "Autoconsent",
            version: "1.0.0",
            embeddedType: .embedded
        )
        installedExtensionStoringMock.installedExtensions = [embeddedExt]

        let result = manager.installedEmbeddedExtension(for: .embedded)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.uniqueIdentifier, "embedded-id")
        XCTAssertEqual(result?.embeddedType, .embedded)
    }

    func testWhenMultipleExtensionsInstalled_ThenFindsCorrectEmbeddedExtension() {
        let userExt = InstalledWebExtension(
            uniqueIdentifier: "user-ext",
            filename: "user.zip",
            name: "User Extension",
            version: "2.0.0"
        )
        let embeddedExt = InstalledWebExtension(
            uniqueIdentifier: "embedded-id",
            filename: "duckduckgo-embedded-web-extension.zip",
            name: "Autoconsent",
            version: "1.0.0",
            embeddedType: .embedded
        )
        installedExtensionStoringMock.installedExtensions = [userExt, embeddedExt]

        let result = manager.installedEmbeddedExtension(for: .embedded)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.uniqueIdentifier, "embedded-id")
    }
}

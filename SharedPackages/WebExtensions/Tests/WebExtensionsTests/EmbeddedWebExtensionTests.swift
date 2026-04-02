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
        XCTAssertEqual(descriptor?.resourceFilename, "duckduckgo-embedded-web-extension.zip")
    }

    func testRegistryContainsDarkReaderExtension() {
        let descriptor = EmbeddedWebExtensionRegistry.descriptor(for: .darkReader)

        XCTAssertNotNil(descriptor)
        XCTAssertEqual(descriptor?.type, .darkReader)
        XCTAssertEqual(descriptor?.resourceFilename, "darkreader.zip")
    }

    func testRegistryAllContainsExpectedExtensions() {
        XCTAssertFalse(EmbeddedWebExtensionRegistry.all.isEmpty)
        XCTAssertTrue(EmbeddedWebExtensionRegistry.all.contains { $0.type == .embedded })
        XCTAssertTrue(EmbeddedWebExtensionRegistry.all.contains { $0.type == .darkReader })
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
            displayName: "Test Extension",
            requiresExtraction: false
        )

        XCTAssertEqual(metadata.type, .embedded)
        XCTAssertEqual(metadata.version, "1.0.0")
        XCTAssertEqual(metadata.displayName, "Test Extension")
        XCTAssertFalse(metadata.requiresExtraction)
    }
}

// MARK: - SemanticVersionComparator Tests

@available(macOS 15.4, iOS 18.4, *)
final class SemanticVersionComparatorTests: XCTestCase {

    var comparator: SemanticVersionComparator!

    override func setUp() {
        super.setUp()
        comparator = SemanticVersionComparator()
    }

    override func tearDown() {
        comparator = nil
        super.tearDown()
    }

    // MARK: - isVersion(_:newerThan:) Tests

    // Basic version comparisons

    func testWhenNewVersionHasHigherMajor_ThenReturnsTrue() {
        XCTAssertTrue(comparator.isVersion("2.0.0", newerThan: "1.0.0"))
        XCTAssertTrue(comparator.isVersion("10.0.0", newerThan: "9.0.0"))
    }

    func testWhenNewVersionHasHigherMinor_ThenReturnsTrue() {
        XCTAssertTrue(comparator.isVersion("1.2.0", newerThan: "1.1.0"))
        XCTAssertTrue(comparator.isVersion("1.10.0", newerThan: "1.9.0"))
    }

    func testWhenNewVersionHasHigherPatch_ThenReturnsTrue() {
        XCTAssertTrue(comparator.isVersion("1.0.2", newerThan: "1.0.1"))
        XCTAssertTrue(comparator.isVersion("1.0.10", newerThan: "1.0.9"))
    }

    func testWhenNewVersionHasLowerMajor_ThenReturnsFalse() {
        XCTAssertFalse(comparator.isVersion("1.0.0", newerThan: "2.0.0"))
        XCTAssertFalse(comparator.isVersion("9.0.0", newerThan: "10.0.0"))
    }

    func testWhenNewVersionHasLowerMinor_ThenReturnsFalse() {
        XCTAssertFalse(comparator.isVersion("1.1.0", newerThan: "1.2.0"))
    }

    func testWhenNewVersionHasLowerPatch_ThenReturnsFalse() {
        XCTAssertFalse(comparator.isVersion("1.0.1", newerThan: "1.0.2"))
    }

    // Equal versions

    func testWhenVersionsAreEqual_ThenReturnsFalse() {
        XCTAssertFalse(comparator.isVersion("1.2.3", newerThan: "1.2.3"))
        XCTAssertFalse(comparator.isVersion("0.0.0", newerThan: "0.0.0"))
        XCTAssertFalse(comparator.isVersion("10.20.30", newerThan: "10.20.30"))
    }

    // Different component lengths

    func testWhenNewVersionHasMoreComponents_ThenComparesCorrectly() {
        XCTAssertTrue(comparator.isVersion("1.0.0.1", newerThan: "1.0.0"))
        XCTAssertTrue(comparator.isVersion("1.0.1.0", newerThan: "1.0.0"))
        XCTAssertFalse(comparator.isVersion("1.0.0.0", newerThan: "1.0.0"))
    }

    func testWhenOldVersionHasMoreComponents_ThenComparesCorrectly() {
        XCTAssertFalse(comparator.isVersion("1.0.0", newerThan: "1.0.0.1"))
        XCTAssertFalse(comparator.isVersion("1.0.0", newerThan: "1.0.1.0"))
        XCTAssertFalse(comparator.isVersion("1.0.0", newerThan: "1.0.0.0"))
    }

    func testWhenComparingTwoVsThreeComponents_ThenTrailingZerosAreImplicit() {
        XCTAssertFalse(comparator.isVersion("1.0", newerThan: "1.0.0"))
        XCTAssertFalse(comparator.isVersion("1.0.0", newerThan: "1.0"))
        XCTAssertTrue(comparator.isVersion("1.1", newerThan: "1.0.0"))
        XCTAssertTrue(comparator.isVersion("1.0.1", newerThan: "1.0"))
    }

    // Non-numeric components (e.g., "1.0.0-beta")

    func testWhenVersionHasBetaSuffix_ThenNumericPartIsCompared() {
        XCTAssertFalse(comparator.isVersion("1.0.0-beta", newerThan: "1.0.0"))
        XCTAssertFalse(comparator.isVersion("1.0.0", newerThan: "1.0.0-beta"))
        XCTAssertTrue(comparator.isVersion("1.0.1-beta", newerThan: "1.0.0"))
        XCTAssertTrue(comparator.isVersion("1.0.1", newerThan: "1.0.0-beta"))
    }

    func testWhenVersionHasAlphaSuffix_ThenNumericPartIsCompared() {
        XCTAssertFalse(comparator.isVersion("2.0.0-alpha", newerThan: "2.0.0"))
        XCTAssertTrue(comparator.isVersion("2.0.1-alpha", newerThan: "2.0.0"))
    }

    func testWhenVersionHasRCSuffix_ThenNumericPartIsCompared() {
        XCTAssertFalse(comparator.isVersion("1.0.0-rc1", newerThan: "1.0.0"))
        XCTAssertTrue(comparator.isVersion("1.0.1-rc1", newerThan: "1.0.0"))
    }

    func testWhenBothVersionsHaveNonNumericSuffixes_ThenNumericPartsAreCompared() {
        XCTAssertFalse(comparator.isVersion("1.0.0-beta", newerThan: "1.0.0-alpha"))
        XCTAssertTrue(comparator.isVersion("1.0.1-alpha", newerThan: "1.0.0-beta"))
    }

    // Edge cases

    func testWhenVersionsAreEmpty_ThenReturnsFalse() {
        XCTAssertFalse(comparator.isVersion("", newerThan: ""))
    }

    func testWhenNewVersionIsEmpty_ThenReturnsFalse() {
        XCTAssertFalse(comparator.isVersion("", newerThan: "1.0.0"))
    }

    func testWhenOldVersionIsEmpty_ThenReturnsTrue() {
        XCTAssertTrue(comparator.isVersion("1.0.0", newerThan: ""))
    }

    func testWhenVersionsContainOnlyNonNumeric_ThenTreatedAsZero() {
        XCTAssertFalse(comparator.isVersion("beta", newerThan: "alpha"))
        XCTAssertFalse(comparator.isVersion("alpha", newerThan: "beta"))
    }

    func testWhenVersionsHaveLargeNumbers_ThenComparesCorrectly() {
        XCTAssertTrue(comparator.isVersion("100.200.300", newerThan: "100.200.299"))
        XCTAssertFalse(comparator.isVersion("100.200.299", newerThan: "100.200.300"))
    }

    func testWhenVersionsHaveManyComponents_ThenComparesCorrectly() {
        XCTAssertTrue(comparator.isVersion("1.2.3.4.5.6", newerThan: "1.2.3.4.5.5"))
        XCTAssertFalse(comparator.isVersion("1.2.3.4.5.5", newerThan: "1.2.3.4.5.6"))
    }

    // MARK: - shouldUpgrade Tests

    func testWhenBundledVersionIsNil_ThenReturnsFalse() {
        XCTAssertFalse(comparator.shouldUpgrade(installedVersion: "1.0.0", bundledVersion: nil))
        XCTAssertFalse(comparator.shouldUpgrade(installedVersion: nil, bundledVersion: nil))
    }

    func testWhenInstalledVersionIsNil_ThenReturnsTrue() {
        XCTAssertTrue(comparator.shouldUpgrade(installedVersion: nil, bundledVersion: "1.0.0"))
    }

    func testWhenBundledVersionIsNewer_ThenReturnsTrue() {
        XCTAssertTrue(comparator.shouldUpgrade(installedVersion: "1.0.0", bundledVersion: "1.0.1"))
        XCTAssertTrue(comparator.shouldUpgrade(installedVersion: "1.0.0", bundledVersion: "2.0.0"))
    }

    func testWhenBundledVersionIsOlder_ThenReturnsFalse() {
        XCTAssertFalse(comparator.shouldUpgrade(installedVersion: "1.0.1", bundledVersion: "1.0.0"))
        XCTAssertFalse(comparator.shouldUpgrade(installedVersion: "2.0.0", bundledVersion: "1.0.0"))
    }

    func testWhenVersionsAreEqual_ThenShouldUpgradeReturnsFalse() {
        XCTAssertFalse(comparator.shouldUpgrade(installedVersion: "1.0.0", bundledVersion: "1.0.0"))
    }

    func testWhenVersionsHaveDifferentComponentCounts_ThenComparesCorrectly() {
        XCTAssertTrue(comparator.shouldUpgrade(installedVersion: "1.0", bundledVersion: "1.0.1"))
        XCTAssertFalse(comparator.shouldUpgrade(installedVersion: "1.0.0", bundledVersion: "1.0"))
    }
}

// MARK: - WebExtensionManager installedEmbeddedExtension Tests

@available(macOS 15.4, iOS 18.4, *)
final class WebExtensionManagerEmbeddedExtensionTests: XCTestCase {

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

//
//  ChromeWebStorePendingUpdateStoreTests.swift
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

import Foundation
import XCTest
@testable import WebExtensions

@MainActor
@available(macOS 15.4, iOS 18.4, *)
final class ChromeWebStorePendingUpdateStoreTests: XCTestCase {
    private var directory: URL!
    private var store: ChromeWebStorePendingUpdateStore!
    private let identifier = ChromeWebStoreID.bitwarden.rawValue

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = ChromeWebStorePendingUpdateStore(directory: directory.appendingPathComponent("pending"))
    }

    override func tearDownWithError() throws {
        store = nil
        try FileManager.default.removeItem(at: directory)
    }

    private func update(version: String, identifier: String? = nil) throws -> ChromeWebStoreVerifiedUpdate {
        let file = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("zip")
        try Data(version.utf8).write(to: file)
        return .init(extensionID: identifier ?? self.identifier, version: version, fileURL: file)
    }

    private func pendingUpdate() async throws -> ChromeWebStoreVerifiedUpdate {
        let update = await store.pendingUpdate(for: identifier)
        return try XCTUnwrap(update)
    }

    func testAcceptedUpdateIsAvailableWithIdentityVersionAndOwnedFile() async throws {
        let offered = try update(version: "4.9")
        let accepted = try await store.store(offered)
        XCTAssertTrue(accepted)
        let pending = try await pendingUpdate()
        XCTAssertEqual(pending.extensionID, identifier)
        XCTAssertEqual(pending.version, "4.9")
        XCTAssertNotEqual(pending.fileURL, offered.fileURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: offered.fileURL.path))
        XCTAssertEqual(try Data(contentsOf: pending.fileURL), Data("4.9".utf8))
    }

    func testNewerVersionReplacesAndDeletesPreviousPackageUsingNumericOrder() async throws {
        _ = try await store.store(update(version: "4.9"))
        let old = try await pendingUpdate()
        let accepted = try await store.store(update(version: "4.10"))
        XCTAssertTrue(accepted)
        let pending = try await pendingUpdate()
        XCTAssertEqual(pending.version, "4.10")
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.fileURL.path))
        XCTAssertEqual(try Data(contentsOf: pending.fileURL), Data("4.10".utf8))
    }

    func testEqualOrOlderVersionDoesNotTransferFileOwnership() async throws {
        _ = try await store.store(update(version: "4.10"))
        let pending = await store.pendingUpdate(for: identifier)
        for version in ["4.10", "4.10.0", "4.9"] {
            let offered = try update(version: version)
            let accepted = try await store.store(offered)
            XCTAssertFalse(accepted)
            XCTAssertTrue(FileManager.default.fileExists(atPath: offered.fileURL.path))
            let current = await store.pendingUpdate(for: identifier)
            XCTAssertEqual(current, pending)
        }
    }

    func testMissingPendingFileAllowsSameVersionToBeStagedAgain() async throws {
        _ = try await store.store(update(version: "2.0"))
        let pending = try await pendingUpdate()
        try FileManager.default.removeItem(at: pending.fileURL)
        let missing = await store.pendingUpdate(for: identifier)
        XCTAssertNil(missing)
        let accepted = try await store.store(update(version: "2.0"))
        XCTAssertTrue(accepted)
        let replacement = await store.pendingUpdate(for: identifier)
        XCTAssertEqual(replacement?.version, "2.0")
    }

    func testFailedReplacementPreservesPreviousPackage() async throws {
        _ = try await store.store(update(version: "2.0"))
        let pending = try await pendingUpdate()
        let offered = try update(version: "3.0")
        try FileManager.default.removeItem(at: offered.fileURL)
        do {
            _ = try await store.store(offered)
            XCTFail("Moving a missing replacement must fail")
        } catch {
            let current = await store.pendingUpdate(for: identifier)
            XCTAssertEqual(current, pending)
            XCTAssertTrue(FileManager.default.fileExists(atPath: pending.fileURL.path))
        }
    }

    func testExtensionsHaveIndependentPendingPackages() async throws {
        let otherID = ChromeWebStoreID.onePassword.rawValue
        _ = try await store.store(update(version: "2.0"))
        _ = try await store.store(update(version: "1.0", identifier: otherID))
        _ = try await store.store(update(version: "3.0"))
        let first = await store.pendingUpdate(for: identifier)
        let second = await store.pendingUpdate(for: otherID)
        XCTAssertEqual(first?.version, "3.0")
        XCTAssertEqual(second?.version, "1.0")
        XCTAssertNotEqual(first?.fileURL, second?.fileURL)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(second).fileURL), Data("1.0".utf8))
    }

    func testPersistentPendingPackageRetainsLogicalInstallationAcrossStoreRecreation() async throws {
        let location = directory.appendingPathComponent("persistent")
        var durable: ChromeWebStorePendingUpdateStore? = ChromeWebStorePendingUpdateStore(persistentDirectory: location)
        let offered = try update(version: "2.0")
        let installationID = UUID().uuidString
        _ = try await durable?.store(.init(extensionID: offered.extensionID, version: offered.version, fileURL: offered.fileURL,
                                          installationIdentifier: installationID))
        durable = nil

        let reopened = ChromeWebStorePendingUpdateStore(persistentDirectory: location)
        let restored = await reopened.pendingUpdate(for: identifier)

        XCTAssertEqual(restored?.version, "2.0")
        XCTAssertEqual(restored?.installationIdentifier, installationID)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(restored).fileURL), Data("2.0".utf8))
    }

    func testStartupCopySurvivesNewerPendingReplacementAndConditionalRemoval() async throws {
        _ = try await store.store(update(version: "2.0"))
        let source = try await pendingUpdate()
        let copied = try await store.copyForInstallation(source)
        let copy = try XCTUnwrap(copied)
        _ = try await store.store(update(version: "3.0"))

        try await store.remove(source)

        XCTAssertEqual(try Data(contentsOf: copy.fileURL), Data("2.0".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.fileURL.path))
        let newer = await store.pendingUpdate(for: identifier)
        XCTAssertEqual(newer?.version, "3.0")
        try await store.removeInstallationCopy(copy)
        XCTAssertFalse(FileManager.default.fileExists(atPath: copy.fileURL.path))
    }

    func testStartupCleanupDropsAbandonedCopiesAndRetainsPendingOriginal() async throws {
        let location = directory.appendingPathComponent("persistent")
        let durable = ChromeWebStorePendingUpdateStore(persistentDirectory: location)
        _ = try await durable.store(update(version: "2.0"))
        let pending = await durable.pendingUpdate(for: identifier)
        let copied = try await durable.copyForInstallation(XCTUnwrap(pending))
        let copy = try XCTUnwrap(copied)
        let reopened = ChromeWebStorePendingUpdateStore(persistentDirectory: location)

        try await reopened.cleanupAbandonedInstallationCopies()

        XCTAssertFalse(FileManager.default.fileExists(atPath: copy.fileURL.path))
        let restored = await reopened.pendingUpdate(for: identifier)
        XCTAssertEqual(restored, pending)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(restored).fileURL.path))
    }

    func testPersistentMetadataRejectsPayloadPathsOutsideOwnedDirectory() async throws {
        let location = directory.appendingPathComponent("persistent")
        try FileManager.default.createDirectory(at: location, withIntermediateDirectories: true)
        let outside = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("zip")
        try Data("outside".utf8).write(to: outside)
        let metadata = [["extensionID": identifier, "version": "2.0", "archiveName": "../" + outside.lastPathComponent]]
        try JSONSerialization.data(withJSONObject: metadata).write(to: location.appendingPathComponent("pending.json"))
        let durable = ChromeWebStorePendingUpdateStore(persistentDirectory: location)

        do {
            _ = try await durable.allPendingUpdates()
            XCTFail("Relative traversal must never become an installable pending package")
        } catch { }

        XCTAssertEqual(try Data(contentsOf: outside), Data("outside".utf8))
    }

    func testAcceptedStoreNotifiesItsOwnerWithoutDependingOnProducerReporting() async throws {
        let stored = expectation(description: "store acceptance notification")
        await store.setUpdateStoredHandler { _ in stored.fulfill() }

        _ = try await store.store(update(version: "2.0"))

        await fulfillment(of: [stored], timeout: 1)
    }
}

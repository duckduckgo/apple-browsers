//
//  ChromeWebStoreUpdaterTests.swift
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

import CryptoKit
import XCTest
@testable import WebExtensions

@available(macOS 15.4, iOS 18.4, *)
@MainActor
final class ChromeWebStoreUpdaterTests: XCTestCase {
    private var events: [(extensionID: String, outcome: ChromeWebStoreUpdater.Outcome)] = []
    private var installedVersion = "0.9"
    private var installationIDs: Set<String> = ["installed"]

    private func offer(_ fixture: ChromeWebStoreFixture, version: String = "1.0", package: Data? = nil,
                       identifier: String? = nil, hash: String? = nil) throws -> ChromeWebStoreUpdateChecker.Update {
        let data = package ?? fixture.package
        return .init(extensionID: identifier ?? fixture.identifier, version: version,
                     downloadURL: try XCTUnwrap(URL(string: "https://clients2.googleusercontent.com/update.crx")),
                     size: data.count, sha256: hash ?? SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
    }

    private func updater(store: any ChromeWebStorePendingUpdateStoring = ChromeWebStorePendingUpdateStore(),
                         download: @escaping ChromeWebStoreUpdater.Download) -> ChromeWebStoreUpdater {
        ChromeWebStoreUpdater(pendingUpdates: store,
                              verifier: ChromeWebStorePackageVerifier(publisherKeyHash: ChromeWebStoreFixture.publisherKeyHash),
                              download: download, installation: { [weak self] _ in
            guard let self else { return nil }
            return .init(identifiers: self.installationIDs, version: self.installedVersion)
        }, report: { [weak self] identifier, outcome in self?.events.append((identifier, outcome)) })
    }

    func testAmbiguousInstalledIdentityDoesNotDownloadAFullPackage() async throws {
        installationIDs = ["first-installation", "second-installation"]
        let fixture = try ChromeWebStoreFixture()
        let counter = PreparationCounter()
        let updater = updater { _ in
            await counter.increment()
            return fixture.package
        }

        await updater.prepare(try offer(fixture))

        let downloads = await counter.value
        XCTAssertEqual(downloads, 0)
        XCTAssertTrue(events.isEmpty)
    }

    func testValidPackageIsHandedOverAsVerifiedZIPAndSameVersionIsNotDownloadedAgain() async throws {
        let fixture = try ChromeWebStoreFixture()
        let store = ChromeWebStorePendingUpdateStore()
        let counter = PreparationCounter()
        let updater = updater(store: store) { update in
            XCTAssertFalse(Thread.isMainThread)
            XCTAssertEqual(update.extensionID, fixture.identifier)
            await counter.increment()
            return fixture.package
        }
        let update = try offer(fixture)
        await updater.prepare(update)
        await updater.prepare(update)
        let pending = await store.pendingUpdate(for: fixture.identifier)
        XCTAssertEqual(pending?.installationIdentifier, "installed")
        let verified = try XCTUnwrap(pending)
        XCTAssertEqual(verified.extensionID, fixture.identifier)
        XCTAssertEqual(verified.version, "1.0")
        XCTAssertEqual(try Data(contentsOf: verified.fileURL), fixture.archive)
        let count = await counter.value
        XCTAssertEqual(count, 1)
        XCTAssertEqual(events.count, 1)
        guard case .verified = events.first?.outcome else { return XCTFail("Expected verified update") }
        XCTAssertEqual(events.first?.extensionID, fixture.identifier)
    }

    func testReceiverCanTakeOwnershipWithoutMovingTheVerifiedFile() async throws {
        let fixture = try ChromeWebStoreFixture()
        let receiver = AcceptingPendingUpdateReceiver()
        let updater = updater(store: receiver) { _ in fixture.package }
        await updater.prepare(try offer(fixture))
        let pending = await receiver.pendingUpdate(for: fixture.identifier)
        let update = try XCTUnwrap(pending)
        defer { try? FileManager.default.removeItem(at: update.fileURL) }
        XCTAssertEqual(try Data(contentsOf: update.fileURL), fixture.archive)
    }

    func testHashAndSizeAreCheckedBeforeParsingAnInvalidCRX() async throws {
        let fixture = try ChromeWebStoreFixture()
        let invalid = Data("not a CRX".utf8)
        let updater = updater { _ in invalid }
        let hashMismatch = try offer(fixture, package: invalid, hash: String(repeating: "0", count: 64))
        await updater.prepare(hashMismatch)
        assertDownloadFailure(.hashMismatch)
        events.removeAll()
        await updater.prepare(try offer(fixture))
        assertDownloadFailure(.sizeMismatch)
    }

    func testInvalidSignatureMissingPublisherAndWrongDeveloperIdentityAreRejected() async throws {
        for fixture in [try ChromeWebStoreFixture(publisher: .invalidSignature), try ChromeWebStoreFixture(publisher: nil)] {
            events.removeAll()
            let updater = updater { _ in fixture.package }
            await updater.prepare(try offer(fixture))
            assertVerificationFailure(.invalidSignature)
        }
        events.removeAll()
        let fixture = try ChromeWebStoreFixture()
        let updater = updater { _ in fixture.package }
        await updater.prepare(try offer(fixture, identifier: String(repeating: "a", count: 32)))
        assertVerificationFailure(.invalidPackage)
    }

    func testTamperedSignedArchiveIsRejectedAfterMatchingHash() async throws {
        let fixture = try ChromeWebStoreFixture()
        var corrupted = fixture.package
        corrupted[corrupted.count - 1] ^= 1
        let package = corrupted
        let updater = updater { _ in package }
        await updater.prepare(try offer(fixture, package: package))
        assertVerificationFailure(.invalidSignature)
    }

    func testMissingInvalidAndMismatchedManifestVersionsAreRejected() async throws {
        let manifests: [[String: Any]] = [
            ["manifest_version": 3, "name": "Test"],
            ["manifest_version": 3, "name": "Test", "version": "01.0"],
            ["manifest_version": 3, "name": "Test", "version": "2.0"]
        ]
        for (index, manifest) in manifests.enumerated() {
            events.removeAll()
            let fixture = try ChromeWebStoreFixture(manifest: manifest)
            let updater = updater { _ in fixture.package }
            await updater.prepare(try offer(fixture))
            assertVerificationFailure(index == 2 ? .versionMismatch : .invalidVersion)
        }
    }

    func testActualInstalledVersionPreventsEqualVersionAndDowngrade() async throws {
        let fixture = try ChromeWebStoreFixture()
        for version in ["1.0", "1.1", "4.10"] {
            installedVersion = version
            events.removeAll()
            let updater = updater { _ in fixture.package }
            await updater.prepare(try offer(fixture))
            assertVerificationFailure(.notNewer)
        }
    }

    func testVersionsAreComparedNumerically() async throws {
        installedVersion = "4.9"
        let fixture = try ChromeWebStoreFixture(manifest: ["manifest_version": 3, "name": "Test", "version": "4.10"])
        let updater = updater { _ in fixture.package }
        await updater.prepare(try offer(fixture, version: "4.10"))
        guard case .verified = events.first?.outcome else { return XCTFail("4.10 must be newer than 4.9") }
    }

    func testRemovedOrReinstalledExtensionDoesNotReceiveDownloadedPackage() async throws {
        let fixture = try ChromeWebStoreFixture()
        for replacement: Set<String> in [[], ["replacement"]] {
            installationIDs = ["installed"]
            events.removeAll()
            let store = ChromeWebStorePendingUpdateStore()
            let updater = updater(store: store) { _ in
                await MainActor.run { self.installationIDs = replacement }
                return fixture.package
            }
            await updater.prepare(try offer(fixture))
            let pending = await store.pendingUpdate(for: fixture.identifier)
            XCTAssertNil(pending)
            XCTAssertTrue(events.isEmpty)
        }
    }

    func testNonInstalledOfferNeverDownloads() async throws {
        installationIDs = []
        let fixture = try ChromeWebStoreFixture()
        let updater = updater { _ in
            XCTFail("Uninstalled extensions must not download")
            return fixture.package
        }
        await updater.prepare(try offer(fixture))
        XCTAssertTrue(events.isEmpty)
    }

    func testFailedDownloadCanRetryOnNextOffer() async throws {
        let fixture = try ChromeWebStoreFixture()
        let updater = updater { _ in throw WebExtensionUpdateDownloadFailure.networkFailure }
        await updater.prepare(try offer(fixture))
        await updater.prepare(try offer(fixture))
        XCTAssertEqual(events.count, 2)
        assertDownloadFailure(.networkFailure)
    }

    func testCancellationAndStopProduceNoFailurePixelOrPendingPackage() async throws {
        let fixture = try ChromeWebStoreFixture()
        let started = expectation(description: "Transfer started")
        let gate = PreparationGate()
        let store = ChromeWebStorePendingUpdateStore()
        let updater = updater(store: store) { _ in
            started.fulfill()
            await gate.wait()
            return fixture.package
        }
        let task = Task { await updater.prepare(try offer(fixture)) }
        await fulfillment(of: [started], timeout: 2)
        await updater.stop()
        await gate.resume()
        try await task.value
        await updater.prepare(try offer(fixture))
        XCTAssertTrue(events.isEmpty)
        let pending = await store.pendingUpdate(for: fixture.identifier)
        XCTAssertNil(pending)
    }

    func testConcurrentIdenticalOffersShareOnePreparation() async throws {
        let fixture = try ChromeWebStoreFixture()
        let started = expectation(description: "Transfer started")
        let gate = PreparationGate()
        let counter = PreparationCounter()
        let updater = updater { _ in
            await counter.increment()
            started.fulfill()
            await gate.wait()
            return fixture.package
        }
        let update = try offer(fixture)
        let first = Task { await updater.prepare(update) }
        await fulfillment(of: [started], timeout: 2)
        let second = Task { await updater.prepare(update) }
        await gate.resume()
        await first.value
        await second.value
        let count = await counter.value
        XCTAssertEqual(count, 1)
        XCTAssertEqual(events.count, 1)
    }

    func testStorageFailureEmitsBoundedReasonAndRemovesUnacceptedTemporaryFile() async throws {
        let fixture = try ChromeWebStoreFixture()
        let store = RejectingPendingUpdateStore()
        let updater = updater(store: store) { _ in fixture.package }
        await updater.prepare(try offer(fixture))
        assertVerificationFailure(.storageFailure)
        let file = await store.offeredFile
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(file).path))
    }

    private func assertDownloadFailure(_ expected: WebExtensionUpdateDownloadFailure, file: StaticString = #filePath, line: UInt = #line) {
        guard case .downloadFailed(let outcome) = events.last?.outcome else { return XCTFail("Expected download failure", file: file, line: line) }
        XCTAssertEqual(outcome, expected, file: file, line: line)
    }

    private func assertVerificationFailure(_ expected: WebExtensionUpdateVerificationFailure, file: StaticString = #filePath, line: UInt = #line) {
        guard case .verificationFailed(let outcome) = events.last?.outcome else { return XCTFail("Expected verification failure", file: file, line: line) }
        XCTAssertEqual(outcome, expected, file: file, line: line)
    }
}

private actor PreparationCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}

private actor PreparationGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var resumed = false
    func wait() async {
        if resumed { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func resume() {
        resumed = true
        continuation?.resume()
        continuation = nil
    }
}

private actor RejectingPendingUpdateStore: ChromeWebStorePendingUpdateStoring {
    private(set) var offeredFile: URL?
    func pendingUpdate(for extensionID: String) -> ChromeWebStoreVerifiedUpdate? { nil }
    func store(_ update: ChromeWebStoreVerifiedUpdate) throws -> Bool {
        offeredFile = update.fileURL
        throw CocoaError(.fileWriteUnknown)
    }
    func allPendingUpdates() -> [ChromeWebStoreVerifiedUpdate] { [] }
    func copyForInstallation(_ update: ChromeWebStoreVerifiedUpdate) throws -> ChromeWebStoreVerifiedUpdate? { throw CocoaError(.fileReadUnknown) }
    func remove(_ update: ChromeWebStoreVerifiedUpdate) { }
    func removeInstallationCopy(_ update: ChromeWebStoreVerifiedUpdate) { }
    func cleanupAbandonedInstallationCopies() { }
    func setUpdateStoredHandler(_ handler: (@Sendable (ChromeWebStoreVerifiedUpdate) -> Void)?) { }
}

private actor AcceptingPendingUpdateReceiver: ChromeWebStorePendingUpdateStoring {
    private var update: ChromeWebStoreVerifiedUpdate?
    private var storedHandler: (@Sendable (ChromeWebStoreVerifiedUpdate) -> Void)?
    func pendingUpdate(for extensionID: String) -> ChromeWebStoreVerifiedUpdate? { update }
    func store(_ update: ChromeWebStoreVerifiedUpdate) -> Bool {
        self.update = update
        storedHandler?(update)
        return true
    }
    func allPendingUpdates() -> [ChromeWebStoreVerifiedUpdate] { update.map { [$0] } ?? [] }
    func copyForInstallation(_ update: ChromeWebStoreVerifiedUpdate) throws -> ChromeWebStoreVerifiedUpdate? { throw CocoaError(.fileReadUnknown) }
    func remove(_ update: ChromeWebStoreVerifiedUpdate) { if self.update == update { self.update = nil } }
    func removeInstallationCopy(_ update: ChromeWebStoreVerifiedUpdate) { }
    func cleanupAbandonedInstallationCopies() { }
    func setUpdateStoredHandler(_ handler: (@Sendable (ChromeWebStoreVerifiedUpdate) -> Void)?) { storedHandler = handler }
}

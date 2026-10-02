//
//  BrokerBundleVerificationTests.swift
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
import CryptoKit
import Foundation
import SecureStorage
import PrivacyConfig
@testable import DataBrokerProtectionCore
import DataBrokerProtectionCoreTestsUtils

/// The fixtures in `BundleResources/BrokerBundleSigning` are real dbp-api packaging output, signed with the TEST staging key.
final class BrokerBundleVerificationTests: XCTestCase {

    private static let stagingKeyID = "7d70813fd5b624988cc80dc8a59eae4773c8ed8beb2998ed99e13326439afe65"
    private static let productionKeyID = "5f36a83cf7110611f6151e579a80349e55eacf252e7bd8fa95fe8b8d04fa571b"
    private static let fixtureManifestVersion = 1790906518
    private static let fixtureBrokerFileNames = ["anywho.com.json", "verecor.com.json"]

    let repository = BrokerUpdaterRepositoryMock()
    let resources = ResourcesRepositoryMock()
    let pixelHandler = MockDataBrokerProtectionPixelsHandler()
    let runTypeProvider = MockAppRunTypeProvider()
    let vault: DataBrokerProtectionSecureVaultMock = try! DataBrokerProtectionSecureVaultMock(providers:
                                                                                                SecureStorageProviders(
                                                                                                    crypto: EmptySecureStorageCryptoProviderMock(),
                                                                                                    database: SecureStorageDatabaseProviderMock(),
                                                                                                    keystore: EmptySecureStorageKeyStoreProviderMock()))
    let authenticationManager = MockAuthenticationManager()
    let privacyConfigurationManager = PrivacyConfigurationManagingMock()
    var privacyConfig: PrivacyConfigurationMock { privacyConfigurationManager.privacyConfig as! PrivacyConfigurationMock }
    var settings: DataBrokerProtectionSettings!
    var eTag: String!
    var mainConfigRequests = [URLRequest]()
    var signatureRequests = [URLRequest]()

    var urlSession: URLSession {
        let config = URLSessionConfiguration.default
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    override func setUp() {
        settings = DataBrokerProtectionSettings(defaults: UserDefaults(suiteName: "com.dbp.tests.\(UUID().uuidString)")!)
        settings.selectedEnvironment = .staging
        eTag = UUID().uuidString
    }

    override func tearDown() {
        MockURLProtocol.requestHandlerQueue.removeAll()
        resources.reset()
        vault.reset()
        pixelHandler.clear()
        try? FileManager.default.removeItem(at: extractedDirectoryURL)
        try? FileManager.default.removeItem(at: archiveURL)
    }

    // MARK: - Keys

    func testBuiltInKeysAreValidAndMatchTheBackendTestKeys() {
        let keys = BrokerBundleSigningKeys.builtIn
        XCTAssertEqual(keys.keys(isProductionEndpoint: true).map(\.id), [Self.productionKeyID])
        XCTAssertEqual(keys.keys(isProductionEndpoint: false).map(\.id), [Self.stagingKeyID])
    }

    func testInvalidKeyIsRejected() {
        XCTAssertNil(BrokerBundleSigningKey(base64SPKI: "not a key"))
        XCTAssertNil(BrokerBundleSigningKey(base64SPKI: Data("not a key".utf8).base64EncodedString()))
    }

    // MARK: - Verifier

    func testWhenSignatureIsValidThenVerifyingKeyIsReturned() throws {
        let key = try stagingVerifier.verifyingKey(manifest: try fixture("main_config.json"), signature: try fixture("main_config.json.sig"))
        XCTAssertEqual(key.id, Self.stagingKeyID)
    }

    func testWhenSignatureHasSurroundingWhitespaceThenItIsAccepted() throws {
        let signature = Data(" \n".utf8) + (try fixture("main_config.json.sig")) + Data("\r\n".utf8)
        XCTAssertNoThrow(try stagingVerifier.verifyingKey(manifest: try fixture("main_config.json"), signature: signature))
    }

    func testWhenManifestIsTamperedThenSignatureIsInvalid() throws {
        var manifest = try fixture("main_config.json")
        manifest[manifest.count / 2] ^= 0x01

        XCTAssertThrowsError(try stagingVerifier.verifyingKey(manifest: manifest, signature: try fixture("main_config.json.sig"))) {
            XCTAssertEqual($0 as? BrokerBundleVerificationError, .signatureInvalid)
        }
    }

    func testWhenManifestHasTrailingNewlineThenSignatureIsInvalid() throws {
        let manifest = try fixture("main_config.json") + Data("\n".utf8)

        XCTAssertThrowsError(try stagingVerifier.verifyingKey(manifest: manifest, signature: try fixture("main_config.json.sig"))) {
            XCTAssertEqual($0 as? BrokerBundleVerificationError, .signatureInvalid)
        }
    }

    func testWhenVerifiedWithWrongKeyThenSignatureIsInvalid() throws {
        let verifier = BrokerBundleVerifier(keys: BrokerBundleSigningKeys.builtIn.keys(isProductionEndpoint: true))

        XCTAssertThrowsError(try verifier.verifyingKey(manifest: try fixture("main_config.json"), signature: try fixture("main_config.json.sig"))) {
            XCTAssertEqual($0 as? BrokerBundleVerificationError, .signatureInvalid)
        }
    }

    func testWhenAnyKeyMatchesThenSignatureIsValid() throws {
        let otherKey = BrokerBundleSigningKey(base64SPKI: P256.Signing.PrivateKey().publicKey.derRepresentation.base64EncodedString())!
        let verifier = BrokerBundleVerifier(keys: [otherKey] + BrokerBundleSigningKeys.builtIn.keys(isProductionEndpoint: false))

        let key = try verifier.verifyingKey(manifest: try fixture("main_config.json"), signature: try fixture("main_config.json.sig"))
        XCTAssertEqual(key.id, Self.stagingKeyID)
    }

    func testWhenSignatureIsAbsentOrEmptyThenSignatureIsMissing() throws {
        for signature in [nil, Data(), Data(" \n".utf8)] {
            XCTAssertThrowsError(try stagingVerifier.verifyingKey(manifest: try fixture("main_config.json"), signature: signature)) {
                XCTAssertEqual($0 as? BrokerBundleVerificationError, .signatureMissing)
            }
        }
    }

    func testWhenSignatureIsMalformedThenSignatureIsInvalid() throws {
        let rawSignature = try P256.Signing.PrivateKey().signature(for: Data()).rawRepresentation.base64EncodedData()

        for signature in [Data("not base64!".utf8), Data("AAAA".utf8), rawSignature] {
            XCTAssertThrowsError(try stagingVerifier.verifyingKey(manifest: try fixture("main_config.json"), signature: signature)) {
                XCTAssertEqual($0 as? BrokerBundleVerificationError, .signatureInvalid)
            }
        }
    }

    func testRevokedKeyIsDetected() {
        XCTAssertTrue(stagingVerifier.hasRevokedKey(revokedKeyIDs: [Self.productionKeyID, Self.stagingKeyID]))
        XCTAssertTrue(stagingVerifier.hasRevokedKey(revokedKeyIDs: [Self.stagingKeyID.uppercased()]))
        XCTAssertFalse(stagingVerifier.hasRevokedKey(revokedKeyIDs: [Self.productionKeyID]))
        XCTAssertFalse(stagingVerifier.hasRevokedKey(revokedKeyIDs: []))
    }

    func testFixtureBrokersMatchTheirDigests() throws {
        let mainConfig = try JSONDecoder().decode(MainConfig.self, from: try fixture("main_config.json"))
        XCTAssertEqual(mainConfig.manifestVersion, Self.fixtureManifestVersion)

        for fileName in Self.fixtureBrokerFileNames {
            var data = try fixture(fileName)
            XCTAssertTrue(BrokerBundleVerifier.hasExpectedDigest(data, expectedSHA256: mainConfig.jsonSHA256[fileName]))

            data[0] ^= 0x01
            XCTAssertFalse(BrokerBundleVerifier.hasExpectedDigest(data, expectedSHA256: mainConfig.jsonSHA256[fileName]))
        }

        XCTAssertFalse(BrokerBundleVerifier.hasExpectedDigest(try fixture("anywho.com.json"), expectedSHA256: nil))
    }

    // MARK: - Update flow

    func testWhenBundleIsValidThenBrokersAreStoredAndManifestVersionIsSaved() async throws {
        try stageExtractedBrokers()
        appendFixtureResponses()

        try await makeService().checkForUpdates()

        XCTAssertTrue(vault.wasBrokerSavedCalled)
        XCTAssertEqual(settings.lastManifestVersions, [Self.stagingKeyID: Self.fixtureManifestVersion])
        XCTAssertEqual(settings.mainConfigETag, eTag)
        XCTAssertTrue(firedVerificationFailures.isEmpty)
        XCTAssertEqual(MockURLProtocol.lastRequest?.url?.path, "/dbp/remote/v0/main_config.json.sig")
    }

    func testWhenManifestIsTamperedThenNothingIsStored() async throws {
        try stageExtractedBrokers()
        var manifest = try fixture("main_config.json")
        manifest[manifest.count / 2] ^= 0x01
        appendFixtureResponses(manifest: manifest)

        await assertCheckForUpdatesFails(with: .signatureInvalid)
        assertNothingMarkedUpToDate()
    }

    func testWhenSignedWithWrongKeyThenNothingIsStored() async throws {
        try stageExtractedBrokers()
        appendFixtureResponses()
        let productionKey = BrokerBundleSigningKeys.builtIn.production

        await assertCheckForUpdatesFails(with: .signatureInvalid, signingKeys: .init(production: [], staging: productionKey))
        assertNothingMarkedUpToDate()
    }

    func testWhenUsingProductionEndpointThenProductionKeysAreUsed() async throws {
        settings.selectedEnvironment = .production
        try stageExtractedBrokers()
        appendFixtureResponses()

        await assertCheckForUpdatesFails(with: .signatureInvalid)
        assertNothingMarkedUpToDate()
    }

    func testWhenSignatureIsMissingThenNothingIsStored() async throws {
        try stageExtractedBrokers()
        appendFixtureResponses(signatureResponse: (HTTPURLResponse.notFound, nil))

        await assertCheckForUpdatesFails(with: .signatureMissing)
        assertNothingMarkedUpToDate()
    }

    func testWhenUnsignedFallbackConfigIsServedThenLastGoodBrokersAreKept() async throws {
        try stageExtractedBrokers()
        settings.mainConfigETag = "last-good"
        settings.lastManifestVersions = [Self.stagingKeyID: Self.fixtureManifestVersion - 1]
        appendFixtureResponses(signatureResponse: (HTTPURLResponse.notFound, nil))

        await assertCheckForUpdatesFails(with: .signatureMissing)

        XCTAssertFalse(vault.wasBrokerSavedCalled)
        XCTAssertFalse(vault.wasBrokerUpdateCalled)
        XCTAssertEqual(settings.mainConfigETag, "last-good", "Next check should request the update again")
        XCTAssertEqual(settings.lastManifestVersions, [Self.stagingKeyID: Self.fixtureManifestVersion - 1])
    }

    func testMainConfigAndSignatureAreNotServedFromLocalCache() async throws {
        try stageExtractedBrokers()
        appendFixtureResponses()

        try await makeService().checkForUpdates()

        XCTAssertEqual(mainConfigRequests.map(\.cachePolicy), [.reloadIgnoringLocalCacheData])
        XCTAssertEqual(signatureRequests.map(\.cachePolicy), [.reloadIgnoringLocalCacheData])
    }

    func testWhenConfigVersionsDifferThenBothAreFetchedAgainOnce() async throws {
        try stageExtractedBrokers()
        var staleManifest = try fixture("main_config.json")
        staleManifest[staleManifest.count / 2] ^= 0x01
        appendFixtureResponses(manifest: staleManifest, mainConfigVersion: "41", signatureVersion: "42")
        appendFixtureResponses(mainConfigVersion: "42", signatureVersion: "42")

        try await makeService().checkForUpdates()

        XCTAssertEqual(mainConfigRequests.count, 2)
        XCTAssertEqual(signatureRequests.count, 2)
        XCTAssertEqual(settings.lastManifestVersions, [Self.stagingKeyID: Self.fixtureManifestVersion])
        XCTAssertTrue(firedVerificationFailures.isEmpty)
    }

    func testWhenConfigVersionsStillDifferAfterRefetchThenSignatureIsInvalid() async throws {
        try stageExtractedBrokers()
        var staleManifest = try fixture("main_config.json")
        staleManifest[staleManifest.count / 2] ^= 0x01
        appendFixtureResponses(manifest: staleManifest, mainConfigVersion: "41", signatureVersion: "42")
        appendFixtureResponses(manifest: staleManifest, mainConfigVersion: "41", signatureVersion: "43")

        await assertCheckForUpdatesFails(with: .signatureInvalid)

        XCTAssertEqual(mainConfigRequests.count, 2)
        XCTAssertEqual(signatureRequests.count, 2)
        assertNothingMarkedUpToDate()
    }

    func testWhenConfigVersionsMatchOrAreMissingThenNothingIsFetchedAgain() async throws {
        var tamperedManifest = try fixture("main_config.json")
        tamperedManifest[tamperedManifest.count / 2] ^= 0x01

        for (mainConfigVersion, signatureVersion) in [("42", "42"), (nil, "42"), ("42", nil), (nil, nil)] {
            mainConfigRequests.removeAll()
            signatureRequests.removeAll()
            pixelHandler.clear()
            appendFixtureResponses(manifest: tamperedManifest, mainConfigVersion: mainConfigVersion, signatureVersion: signatureVersion)

            await assertCheckForUpdatesFails(with: .signatureInvalid)

            XCTAssertEqual(mainConfigRequests.count, 1)
            XCTAssertEqual(signatureRequests.count, 1)
        }
    }

    func testWhenSignatureRequestFailsThenItIsNotReportedAsVerificationFailure() async throws {
        appendFixtureResponses(signatureResponse: (HTTPURLResponse.internalServerError, nil))

        do {
            try await makeService().checkForUpdates()
            XCTFail("Expected an error")
        } catch RemoteBrokerJSONService.Error.serverError(let code) {
            XCTAssertEqual(code, 500)
        }
        XCTAssertTrue(firedVerificationFailures.isEmpty)
        assertNothingMarkedUpToDate()
    }

    func testWhenManifestVersionIsOlderThanLastSeenForKeyThenRollbackIsRejected() async throws {
        try stageExtractedBrokers()
        settings.lastManifestVersions = [Self.stagingKeyID: Self.fixtureManifestVersion + 1]
        appendFixtureResponses()

        await assertCheckForUpdatesFails(with: .rollback)
        XCTAssertFalse(vault.wasBrokerSavedCalled)
        XCTAssertNil(settings.mainConfigETag)
        XCTAssertEqual(settings.lastManifestVersions, [Self.stagingKeyID: Self.fixtureManifestVersion + 1])
    }

    func testWhenManifestVersionIsUnchangedThenItIsAccepted() async throws {
        try stageExtractedBrokers()
        settings.lastManifestVersions = [Self.stagingKeyID: Self.fixtureManifestVersion]
        appendFixtureResponses()

        try await makeService().checkForUpdates()

        XCTAssertTrue(vault.wasBrokerSavedCalled)
        XCTAssertEqual(settings.mainConfigETag, eTag)
    }

    func testWhenOnlyAnotherKeyHasSeenANewerManifestThenItIsAccepted() async throws {
        try stageExtractedBrokers()
        settings.lastManifestVersions = [Self.productionKeyID: 9999999999]
        appendFixtureResponses()

        try await makeService().checkForUpdates()

        XCTAssertEqual(settings.lastManifestVersions, [Self.productionKeyID: 9999999999, Self.stagingKeyID: Self.fixtureManifestVersion])
    }

    func testWhenBrokerDoesNotMatchDigestThenOnlyMatchingBrokersAreStored() async throws {
        try stageExtractedBrokers(tampering: "anywho.com.json")
        appendFixtureResponses()

        await assertCheckForUpdatesFails(with: .digestMismatch)

        XCTAssertEqual(vault.lastSavedBrokerResource?.broker.url, "verecor.com")
        XCTAssertNil(settings.mainConfigETag)
        XCTAssertTrue(settings.lastManifestVersions.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: extractedDirectoryURL.path), "Download should be discarded so it's fetched again")
    }

    func testWhenBuiltInKeyIsRevokedThenBundledBrokersReplaceNewerStoredBrokers() async throws {
        privacyConfig.featureSettings[.dbp] = ["revokedBundleSigningKeys": [Self.stagingKeyID]]
        settings.mainConfigETag = "previous"
        vault.shouldReturnNewVersionBroker = true
        let bundledBroker = try DataBroker.initFromResource(try XCTUnwrap(Bundle.module.url(forResource: "valid-broker",
                                                                                            withExtension: "json",
                                                                                            subdirectory: "BundleResources")))
        resources.brokerResourcesList = [bundledBroker]
        appendFixtureResponses()

        await assertCheckForUpdatesFails(with: .keyRevoked)

        XCTAssertEqual(try vault.fetchBroker(with: "broker.com")?.version, "1.0.1")
        XCTAssertEqual(vault.lastUpdatedBrokerResource?.broker.version, "0.5.0")
        XCTAssertEqual(vault.lastUpdatedBrokerResource?.rawJSON, bundledBroker.rawJSON)
        XCTAssertNil(settings.mainConfigETag)
        XCTAssertEqual(MockURLProtocol.requestHandlerQueue.count, 2, "No remote request should be made")
    }

    func testWhenBuiltInKeyIsRevokedThenBundledBrokersMatchingStoredBrokersAreNotRewritten() async throws {
        privacyConfig.featureSettings[.dbp] = ["revokedBundleSigningKeys": [Self.stagingKeyID]]
        vault.shouldReturnOldVersionBroker = true
        let storedBroker = try XCTUnwrap(try vault.fetchBroker(with: "broker.com"))
        resources.brokerResourcesList = [BrokerResource(broker: storedBroker, rawJSON: Data())]

        await assertCheckForUpdatesFails(with: .keyRevoked)

        XCTAssertFalse(vault.wasBrokerUpdateCalled)
    }

    func testWhenBuiltInKeyIsRevokedThenBrokersThatAreNotBundledAreDisabled() async throws {
        privacyConfig.featureSettings[.dbp] = ["revokedBundleSigningKeys": [Self.stagingKeyID]]
        let bundledBroker = try fixtureBroker("verecor.com.json", id: 1)
        let remoteOnlyBroker = try fixtureBroker("anywho.com.json", id: 2)
        var removedBroker = try fixtureBroker("anywho.com.json", id: 3, url: "removed.com")
        removedBroker = BrokerResource(broker: removedBroker.broker.withRemovedAt(Date.daysAgo(3)), rawJSON: removedBroker.rawJSON)
        resources.brokerResourcesList = [bundledBroker]
        vault.brokerResourcesToReturn = [bundledBroker, remoteOnlyBroker, removedBroker]

        await assertCheckForUpdatesFails(with: .keyRevoked)

        let disabledBroker = try XCTUnwrap(vault.updatedBrokerResources.first { $0.broker.url == "anywho.com" })
        XCTAssertEqual(disabledBroker.broker.id, 2)
        XCTAssertNotNil(disabledBroker.broker.removedAt)
        XCTAssertEqual(disabledBroker.broker.version, "0")
        XCTAssertEqual(disabledBroker.broker.eTag, "")
        XCTAssertEqual(disabledBroker.rawJSON, remoteOnlyBroker.rawJSON)
        XCTAssertEqual(vault.updatedBrokerResources.map(\.broker.url), ["anywho.com"], "Bundled and already removed brokers are left alone")
    }

    func testWhenRevokedKeyIsDroppedThenDisabledBrokersComeBackThroughNormalUpdates() async throws {
        let storedBroker = try fixtureBroker("anywho.com.json", id: 2)
        resources.brokerResourcesList = []
        vault.brokerResourcesToReturn = [storedBroker]
        privacyConfig.featureSettings[.dbp] = ["revokedBundleSigningKeys": [Self.stagingKeyID]]
        await assertCheckForUpdatesFails(with: .keyRevoked)
        let disabledBroker = try XCTUnwrap(vault.lastUpdatedBrokerResource?.broker)

        /// An app update drops the revoked key, so privacy-config no longer affects this app's keys
        privacyConfig.featureSettings[.dbp] = ["revokedBundleSigningKeys": [Self.productionKeyID]]
        vault.brokers = [disabledBroker]
        vault.brokersByURL = [disabledBroker.url: disabledBroker]
        vault.updatedBrokerResources.removeAll()
        pixelHandler.clear()
        try stageExtractedBrokers()
        appendFixtureResponses()

        try await makeService().checkForUpdates(skipsLimiter: true)

        let restoredBroker = try XCTUnwrap(vault.updatedBrokerResources.first { $0.broker.url == "anywho.com" })
        XCTAssertEqual(restoredBroker.broker.version, storedBroker.broker.version)
        XCTAssertNil(restoredBroker.broker.removedAt)
        XCTAssertNotEqual(restoredBroker.broker.eTag, "")
        XCTAssertEqual(restoredBroker.rawJSON, try fixture("anywho.com.json"))
        XCTAssertEqual(settings.mainConfigETag, eTag)
    }

    func testWhenOnlyOtherKeysAreRevokedThenUpdateProceeds() async throws {
        privacyConfig.featureSettings[.dbp] = ["revokedBundleSigningKeys": [Self.productionKeyID]]
        try stageExtractedBrokers()
        appendFixtureResponses()

        try await makeService().checkForUpdates()

        XCTAssertEqual(settings.mainConfigETag, eTag)
    }

    func testWhenRevokedKeysSettingIsMalformedThenItIsTreatedAsEmpty() async throws {
        privacyConfig.featureSettings[.dbp] = ["revokedBundleSigningKeys": Self.stagingKeyID]
        try stageExtractedBrokers()
        appendFixtureResponses()

        try await makeService().checkForUpdates()

        XCTAssertEqual(settings.mainConfigETag, eTag)
    }

    func testBundleVerificationFailurePixel() {
        for reason in BrokerBundleVerificationError.allCases {
            let pixel = DataBrokerProtectionSharedPixels.bundleVerificationFailure(reason: reason)
            XCTAssertEqual(pixel.parameters, ["reason": reason.rawValue])
            XCTAssertEqual(pixel.platformSuffixPolicy, .standard)
            XCTAssertEqual(pixel.namePrefix, .none)
        }
#if os(macOS)
        XCTAssertEqual(DataBrokerProtectionSharedPixels.bundleVerificationFailure(reason: .rollback).name, "dbp_bundle_verification_failure_macos")
#else
        XCTAssertEqual(DataBrokerProtectionSharedPixels.bundleVerificationFailure(reason: .rollback).name, "dbp_bundle_verification_failure")
#endif
    }

    // MARK: - Helpers

    private var stagingVerifier: BrokerBundleVerifier {
        BrokerBundleVerifier(keys: BrokerBundleSigningKeys.builtIn.keys(isProductionEndpoint: false))
    }

    private var extractedDirectoryURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(eTag)
    }

    private var archiveURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(eTag).appendingPathExtension("zip")
    }

    private var firedVerificationFailures: [BrokerBundleVerificationError] {
        MockDataBrokerProtectionPixelsHandler.lastPixelsFired.compactMap {
            guard case .bundleVerificationFailure(let reason) = $0 else { return nil }
            return reason
        }
    }

    private func fixture(_ fileName: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.resourceURL?
            .appendingPathComponent("BundleResources/BrokerBundleSigning")
            .appendingPathComponent(fileName))
        return try Data(contentsOf: url)
    }

    private func fixtureBroker(_ fileName: String, id: Int64, url: String? = nil) throws -> BrokerResource {
        let resource = try DataBroker.initFromData(try fixture(fileName))
        let broker = resource.broker
        return BrokerResource(broker: DataBroker(id: id,
                                                 name: broker.name,
                                                 url: url ?? broker.url,
                                                 steps: broker.steps,
                                                 version: broker.version,
                                                 schedulingConfig: broker.schedulingConfig,
                                                 parent: broker.parent,
                                                 mirrorSites: broker.mirrorSites,
                                                 optOutUrl: broker.optOutUrl,
                                                 eTag: "stored-etag",
                                                 removedAt: broker.removedAt),
                              rawJSON: resource.rawJSON)
    }

    private func makeService(signingKeys: BrokerBundleSigningKeys = .builtIn) -> RemoteBrokerJSONService {
        let localBrokerService = LocalBrokerJSONService(repository: repository,
                                                        resources: resources,
                                                        vault: vault,
                                                        pixelHandler: pixelHandler,
                                                        runTypeProvider: runTypeProvider,
                                                        isAuthenticatedUser: { true },
                                                        optOutRetryErrorFeatureFlagger: DisabledOptOutRetryErrorFeatureFlagger())
        return RemoteBrokerJSONService(featureFlagger: DisabledOptOutRetryErrorFeatureFlagger(),
                                       settings: settings,
                                       vault: vault,
                                       urlSession: urlSession,
                                       authenticationManager: authenticationManager,
                                       pixelHandler: pixelHandler,
                                       localBrokerProvider: localBrokerService,
                                       privacyConfigurationManager: privacyConfigurationManager,
                                       signingKeys: signingKeys)
    }

    /// Stands in for a downloaded and extracted all.zip, so no archive request is made.
    private func stageExtractedBrokers(tampering tamperedFileName: String? = nil) throws {
        let jsonDirectoryURL = extractedDirectoryURL.appendingPathComponent("json", isDirectory: true)
        try FileManager.default.createDirectory(at: jsonDirectoryURL, withIntermediateDirectories: true)
        try Data().write(to: archiveURL)

        for fileName in Self.fixtureBrokerFileNames {
            var data = try fixture(fileName)
            if fileName == tamperedFileName {
                data[data.count / 2] ^= 0x01
            }
            try data.write(to: jsonDirectoryURL.appendingPathComponent(fileName))
        }
    }

    private func appendFixtureResponses(manifest: Data? = nil,
                                        signatureResponse: (HTTPURLResponse, Data?)? = nil,
                                        mainConfigVersion: String? = nil,
                                        signatureVersion: String? = nil) {
        let manifest = manifest ?? (try? fixture("main_config.json"))
        let mainConfigResponse = HTTPURLResponse(url: URL(string: "http://www.example.com")!,
                                                 statusCode: 200,
                                                 httpVersion: nil,
                                                 headerFields: ["ETag": eTag].merging(configVersionHeader(mainConfigVersion)) { $1 })!
        let signatureResponse = signatureResponse ?? (HTTPURLResponse(url: URL(string: "http://www.example.com")!,
                                                                      statusCode: 200,
                                                                      httpVersion: nil,
                                                                      headerFields: configVersionHeader(signatureVersion))!,
                                                      try? fixture("main_config.json.sig"))
        MockURLProtocol.requestHandlerQueue.append { [weak self] request in
            self?.mainConfigRequests.append(request)
            return (mainConfigResponse, manifest)
        }
        MockURLProtocol.requestHandlerQueue.append { [weak self] request in
            self?.signatureRequests.append(request)
            return signatureResponse
        }
    }

    private func configVersionHeader(_ version: String?) -> [String: String] {
        version.map { ["X-Config-Version": $0] } ?? [:]
    }

    private func assertCheckForUpdatesFails(with expectedError: BrokerBundleVerificationError,
                                            signingKeys: BrokerBundleSigningKeys = .builtIn,
                                            file: StaticString = #filePath,
                                            line: UInt = #line) async {
        do {
            try await makeService(signingKeys: signingKeys).checkForUpdates()
            XCTFail("Expected \(expectedError)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? BrokerBundleVerificationError, expectedError, file: file, line: line)
        }
        XCTAssertEqual(firedVerificationFailures, [expectedError], file: file, line: line)
    }

    private func assertNothingMarkedUpToDate(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(vault.wasBrokerSavedCalled, file: file, line: line)
        XCTAssertFalse(vault.wasBrokerUpdateCalled, file: file, line: line)
        XCTAssertNil(settings.mainConfigETag, file: file, line: line)
        XCTAssertTrue(settings.lastManifestVersions.isEmpty, file: file, line: line)
    }
}

private extension HTTPURLResponse {
    static let notFound = HTTPURLResponse(url: URL(string: "http://www.example.com")!, statusCode: 404, httpVersion: nil, headerFields: [:])!
    static let internalServerError = HTTPURLResponse(url: URL(string: "http://www.example.com")!, statusCode: 500, httpVersion: nil, headerFields: [:])!
}

private extension DataBroker {
    func withRemovedAt(_ removedAt: Date) -> DataBroker {
        var broker = self
        broker.removedAt = removedAt
        return broker
    }
}

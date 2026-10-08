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

        for signature in [Data("not base64!".utf8), Data("AAAA".utf8), rawSignature, Data([0xFF, 0xFE])] {
            XCTAssertThrowsError(try stagingVerifier.verifyingKey(manifest: try fixture("main_config.json"), signature: signature)) {
                XCTAssertEqual($0 as? BrokerBundleVerificationError, .signatureInvalid)
            }
        }
    }

    func testRevocationCheckerOnlyMatchesKeysForTheCurrentEnvironment() {
        let checker = BrokerBundleKeyRevocationChecker(privacyConfigurationManager: privacyConfigurationManager, settings: settings)

        for (revokedKeyIDs, isRevoked) in [([Self.productionKeyID, Self.stagingKeyID], true),
                                           ([Self.stagingKeyID.uppercased()], true),
                                           ([Self.productionKeyID], false),
                                           ([], false)] {
            privacyConfig.featureSettings[.dbp] = ["revokedBundleSigningKeys": revokedKeyIDs]
            XCTAssertEqual(checker.isAnyKeyRevoked, isRevoked, "\(revokedKeyIDs)")
        }

        settings.selectedEnvironment = .production
        privacyConfig.featureSettings[.dbp] = ["revokedBundleSigningKeys": [Self.productionKeyID]]
        XCTAssertTrue(checker.isAnyKeyRevoked)
    }

    func testRevocationCheckerTreatsMissingOrMalformedSettingAsNotRevoked() {
        let checker = BrokerBundleKeyRevocationChecker(privacyConfigurationManager: privacyConfigurationManager, settings: settings)

        for dbpSettings: [String: Any] in [[:], ["revokedBundleSigningKeys": Self.stagingKeyID], ["revokedBundleSigningKeys": [1, 2]]] {
            privacyConfig.featureSettings[.dbp] = dbpSettings
            XCTAssertFalse(checker.isAnyKeyRevoked)
        }
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
        XCTAssertEqual(firedVerificationSuccessCount, 1)
        XCTAssertEqual(MockURLProtocol.lastRequest?.url?.path, "/dbp/remote/v0/main_config.json.sig")
    }

    func testWhenMainConfigIsUnchangedThenVerificationSuccessIsReported() async throws {
        settings.mainConfigETag = eTag
        let notModified = HTTPURLResponse(url: URL(string: "http://www.example.com")!, statusCode: 304, httpVersion: nil, headerFields: [:])!
        MockURLProtocol.requestHandlerQueue.append { [weak self] request in
            self?.mainConfigRequests.append(request)
            return (notModified, nil)
        }

        try await makeService().checkForUpdates()

        XCTAssertEqual(mainConfigRequests.count, 1)
        XCTAssertTrue(firedVerificationFailures.isEmpty)
        XCTAssertEqual(firedVerificationSuccessCount, 1)
    }

    func testWhenMainConfigRequestFailsThenNoVerificationPixelIsFired() async throws {
        MockURLProtocol.requestHandlerQueue.append { _ in (HTTPURLResponse.internalServerError, nil) }

        do {
            try await makeService().checkForUpdates()
            XCTFail("Expected an error")
        } catch RemoteBrokerJSONService.Error.serverError(let code) {
            XCTAssertEqual(code, 500)
        }
        XCTAssertTrue(firedVerificationFailures.isEmpty)
        XCTAssertEqual(firedVerificationSuccessCount, 0)
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

    func testWhenSignatureRequestFailsThenOtherIsReported() async throws {
        appendFixtureResponses(signatureResponse: (HTTPURLResponse.internalServerError, nil))

        await assertCheckForUpdatesFails(with: .other)
        assertNothingMarkedUpToDate()
    }

    func testWhenSignatureRequestHasNetworkErrorThenOtherIsReported() async throws {
        MockURLProtocol.requestHandlerQueue.append { [weak self] request in
            self?.mainConfigRequests.append(request)
            return (HTTPURLResponse(url: URL(string: "http://www.example.com")!, statusCode: 200, httpVersion: nil, headerFields: ["ETag": self?.eTag ?? ""])!,
                    try? self?.fixture("main_config.json"))
        }
        MockURLProtocol.requestHandlerQueue.append { _ in throw URLError(.notConnectedToInternet) }

        await assertCheckForUpdatesFails(with: .other)
        assertNothingMarkedUpToDate()
    }

    func testWhenSignedManifestCannotBeParsedThenOtherIsReported() async throws {
        let manifestVersionKey = "\"manifest_version\""
        let fixtureManifest = try XCTUnwrap(String(data: try fixture("main_config.json"), encoding: .utf8))
        let manifestWithoutVersion = Data(fixtureManifest.replacingOccurrences(of: manifestVersionKey, with: "\"renamed_version\"").utf8)
        XCTAssertNotEqual(manifestWithoutVersion, try fixture("main_config.json"))

        for manifest in [Data("not json".utf8), manifestWithoutVersion] {
            pixelHandler.clear()
            let privateKey = P256.Signing.PrivateKey()
            let signature = try privateKey.signature(for: manifest).derRepresentation.base64EncodedData()
            appendFixtureResponses(manifest: manifest, signatureResponse: (HTTPURLResponse.ok, signature))

            await assertCheckForUpdatesFails(with: .other,
                                             signingKeys: .init(production: [], staging: [privateKey.publicKey.derRepresentation.base64EncodedString()]))
            assertNothingMarkedUpToDate()
        }
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

    func testWhenBuiltInKeyIsRevokedThenUpdateIsSkippedAndStoredDataIsUntouched() async throws {
        privacyConfig.featureSettings[.dbp] = ["revokedBundleSigningKeys": [Self.stagingKeyID]]
        settings.mainConfigETag = "previous"
        settings.lastManifestVersions = [Self.stagingKeyID: Self.fixtureManifestVersion]
        vault.shouldReturnNewVersionBroker = true
        let olderBundledBroker = try DataBroker.initFromResource(try XCTUnwrap(Bundle.module.url(forResource: "valid-broker",
                                                                                                 withExtension: "json",
                                                                                                 subdirectory: "BundleResources")))
        resources.brokerResourcesList = [olderBundledBroker]
        appendFixtureResponses()

        await assertCheckForUpdatesFails(with: .keyRevoked)

        XCTAssertEqual(MockURLProtocol.requestHandlerQueue.count, 2, "No remote request should be made")
        XCTAssertFalse(vault.wasBrokerSavedCalled)
        XCTAssertFalse(vault.wasBrokerUpdateCalled, "Bundled brokers must not replace stored ones")
        XCTAssertEqual(try vault.fetchBroker(with: "broker.com")?.version, "1.0.1")
        XCTAssertEqual(settings.mainConfigETag, "previous")
        XCTAssertEqual(settings.lastManifestVersions, [Self.stagingKeyID: Self.fixtureManifestVersion])
        XCTAssertEqual(firedVerificationSuccessCount, 0)
    }

    func testWhenRevokedKeyIsDroppedThenUpdatesResume() async throws {
        privacyConfig.featureSettings[.dbp] = ["revokedBundleSigningKeys": [Self.stagingKeyID]]
        await assertCheckForUpdatesFails(with: .keyRevoked)

        /// An app update drops the revoked key, so privacy-config no longer affects this app's keys
        privacyConfig.featureSettings[.dbp] = ["revokedBundleSigningKeys": [Self.productionKeyID]]
        pixelHandler.clear()
        try stageExtractedBrokers()
        appendFixtureResponses()

        try await makeService().checkForUpdates(skipsLimiter: true)

        XCTAssertTrue(vault.wasBrokerSavedCalled)
        XCTAssertEqual(settings.mainConfigETag, eTag)
        XCTAssertEqual(settings.lastManifestVersions, [Self.stagingKeyID: Self.fixtureManifestVersion])
        XCTAssertTrue(firedVerificationFailures.isEmpty)
        XCTAssertEqual(firedVerificationSuccessCount, 1)
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

    func testLastManifestVersionsSurviveResettingBrokerDeliveryData() {
        settings.mainConfigETag = "previous"
        settings.lastManifestVersions = [Self.stagingKeyID: Self.fixtureManifestVersion]

        settings.resetBrokerDeliveryData()

        XCTAssertNil(settings.mainConfigETag)
        XCTAssertEqual(settings.lastManifestVersions, [Self.stagingKeyID: Self.fixtureManifestVersion])
    }

    func testBundleVerificationSuccessPixel() {
        let pixel = DataBrokerProtectionSharedPixels.bundleVerificationSuccess
        XCTAssertEqual(pixel.parameters, [:])
        XCTAssertEqual(pixel.platformSuffixPolicy, .standard)
        XCTAssertEqual(pixel.namePrefix, .none)
#if os(macOS)
        XCTAssertEqual(pixel.name, "dbp_bundle_verification_success_macos")
#else
        XCTAssertEqual(pixel.name, "dbp_bundle_verification_success")
#endif
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

    private var firedVerificationSuccessCount: Int {
        MockDataBrokerProtectionPixelsHandler.lastPixelsFired.filter {
            guard case .bundleVerificationSuccess = $0 else { return false }
            return true
        }.count
    }

    private func fixture(_ fileName: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.resourceURL?
            .appendingPathComponent("BundleResources/BrokerBundleSigning")
            .appendingPathComponent(fileName))
        return try Data(contentsOf: url)
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
        XCTAssertEqual(firedVerificationSuccessCount, 0, file: file, line: line)
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

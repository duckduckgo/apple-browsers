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
import PixelKit
@testable import DataBrokerProtectionCore
import DataBrokerProtectionCoreTestsUtils

/// The fixtures in `BundleResources/BrokerBundleSigning` are real dbp-api packaging output, signed with the TEST staging key.
final class BrokerBundleVerificationTests: XCTestCase {

    private static let testStagingKeyID = "7d70813fd5b624988cc80dc8a59eae4773c8ed8beb2998ed99e13326439afe65"
    private static let testProductionKeyID = "5f36a83cf7110611f6151e579a80349e55eacf252e7bd8fa95fe8b8d04fa571b"
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

    func testBuiltInKeysMatchTheDbpAPIKeys() throws {
        let keys = try BrokerBundleSigningKeys.loadBuiltIn()
        XCTAssertEqual(BrokerBundleSigningKeys.builtIn, keys)
        XCTAssertEqual(keys.production, ["MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE+H2eWmevflETRxo3CYQiTaAVOevf0bniWcBOVRZR7yLPWl6vQKO1ltVtPsBFJvNT0UZ90ZHO4p1YMnoPo1cCxg=="])
        XCTAssertEqual(keys.staging, ["MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEVdn9FvuBCQnWNwGdOnOv5qPQCQYrWP90khQ+sJSnTjpXYg+jLst5b9PmGAlYuhMMEnkVcjVusmV6Yp+4oV2ZbQ=="])
        XCTAssertEqual(keys.keys(isProductionEndpoint: true).map(\.id), ["9f203b1713089cb240e7b76ba60146bc6c1c4f231206c7ae071dff555b7e6e60"])
        XCTAssertEqual(keys.keys(isProductionEndpoint: false).map(\.id), ["47b8e7e7113853a373207e6e75f377500928821df118e402a52da022074e0880"])
    }

    func testBuiltInKeysDoNotVerifyTheTestSignedFixtures() throws {
        for isProductionEndpoint in [true, false] {
            let verifier = BrokerBundleVerifier(keys: BrokerBundleSigningKeys.builtIn.keys(isProductionEndpoint: isProductionEndpoint))
            XCTAssertThrowsError(try verifier.verifyingKey(manifest: try fixture("main_config.json"), signature: try fixture("main_config.json.sig"))) {
                XCTAssertEqual($0 as? BrokerBundleVerificationError, .signatureInvalid)
            }
        }
    }

    func testInvalidKeyIsRejected() {
        XCTAssertNil(BrokerBundleSigningKey(base64SPKI: "not a key"))
        XCTAssertNil(BrokerBundleSigningKey(base64SPKI: Data("not a key".utf8).base64EncodedString()))
    }

    // MARK: - Verifier

    func testWhenSignatureIsValidThenVerifyingKeyIsReturned() throws {
        let key = try stagingVerifier.verifyingKey(manifest: try fixture("main_config.json"), signature: try fixture("main_config.json.sig"))
        XCTAssertEqual(key.id, Self.testStagingKeyID)
    }

    func testWhenSignatureHasSurroundingWhitespaceThenItIsAccepted() throws {
        let signature = Data(" \n".utf8) + (try fixture("main_config.json.sig")) + Data("\r\n".utf8)
        XCTAssertNoThrow(try stagingVerifier.verifyingKey(manifest: try fixture("main_config.json"), signature: signature))
    }

    func testWhenManifestIsTamperedThenSignatureIsInvalid() throws {
        var flippedByte = try fixture("main_config.json")
        flippedByte[flippedByte.count / 2] ^= 0x01
        let trailingNewline = try fixture("main_config.json") + Data("\n".utf8)

        for manifest in [flippedByte, trailingNewline] {
            XCTAssertThrowsError(try stagingVerifier.verifyingKey(manifest: manifest, signature: try fixture("main_config.json.sig"))) {
                XCTAssertEqual($0 as? BrokerBundleVerificationError, .signatureInvalid)
            }
        }
    }

    func testWhenVerifiedWithWrongKeyThenSignatureIsInvalid() throws {
        let verifier = BrokerBundleVerifier(keys: BrokerBundleSigningKeys.dbpAPITestKeys.keys(isProductionEndpoint: true))

        XCTAssertThrowsError(try verifier.verifyingKey(manifest: try fixture("main_config.json"), signature: try fixture("main_config.json.sig"))) {
            XCTAssertEqual($0 as? BrokerBundleVerificationError, .signatureInvalid)
        }
    }

    func testWhenAnyKeyMatchesThenSignatureIsValid() throws {
        let otherKey = BrokerBundleSigningKey(base64SPKI: P256.Signing.PrivateKey().publicKey.derRepresentation.base64EncodedString())!
        let verifier = BrokerBundleVerifier(keys: [otherKey] + BrokerBundleSigningKeys.dbpAPITestKeys.keys(isProductionEndpoint: false))

        let key = try verifier.verifyingKey(manifest: try fixture("main_config.json"), signature: try fixture("main_config.json.sig"))
        XCTAssertEqual(key.id, Self.testStagingKeyID)
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
        XCTAssertEqual(settings.lastManifestVersions, [Self.testStagingKeyID: Self.fixtureManifestVersion])
        XCTAssertEqual(settings.mainConfigETag, eTag)
        XCTAssertTrue(firedVerificationFailures.isEmpty)
        XCTAssertEqual(firedVerificationSuccessCount, 1)
        XCTAssertEqual(MockURLProtocol.lastRequest?.url?.path, "/dbp/remote/v0/main_config.json.sig")
    }

    func testWhenMainConfigIsUnchangedThenVerificationSuccessIsReported() async throws {
        settings.mainConfigETag = eTag
        appendNotModifiedResponse()

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
        let productionKey = BrokerBundleSigningKeys.dbpAPITestKeys.production

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

    func testWhenUnsignedFallbackConfigIsServedThenLastGoodBrokersAreKept() async throws {
        try stageExtractedBrokers()
        settings.mainConfigETag = "last-good"
        settings.lastManifestVersions = [Self.testStagingKeyID: Self.fixtureManifestVersion - 1]
        appendFixtureResponses(signatureResponse: (HTTPURLResponse.notFound, nil))

        await assertCheckForUpdatesFails(with: .signatureMissing)

        XCTAssertFalse(vault.wasBrokerSavedCalled)
        XCTAssertFalse(vault.wasBrokerUpdateCalled)
        XCTAssertEqual(settings.mainConfigETag, "last-good", "Next check should request the update again")
        XCTAssertEqual(settings.lastManifestVersions, [Self.testStagingKeyID: Self.fixtureManifestVersion - 1])
    }

    func testMainConfigSignatureAndArchiveAreNotServedFromLocalCache() async throws {
        appendFixtureResponses()
        var archiveRequests = [URLRequest]()
        MockURLProtocol.requestHandlerQueue.append { request in
            archiveRequests.append(request)
            return (HTTPURLResponse.internalServerError, nil)
        }

        try? await makeService().checkForUpdates()

        XCTAssertEqual(mainConfigRequests.map(\.cachePolicy), [.reloadIgnoringLocalCacheData])
        XCTAssertEqual(signatureRequests.map(\.cachePolicy), [.reloadIgnoringLocalCacheData])
        XCTAssertEqual(archiveRequests.map(\.cachePolicy), [.reloadIgnoringLocalCacheData])
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
        settings.lastManifestVersions = [Self.testStagingKeyID: Self.fixtureManifestVersion + 1]
        appendFixtureResponses()

        await assertCheckForUpdatesFails(with: .rollback)
        XCTAssertFalse(vault.wasBrokerSavedCalled)
        XCTAssertNil(settings.mainConfigETag)
        XCTAssertEqual(settings.lastManifestVersions, [Self.testStagingKeyID: Self.fixtureManifestVersion + 1])
    }

    func testWhenManifestVersionIsUnchangedThenItIsAccepted() async throws {
        try stageExtractedBrokers()
        settings.lastManifestVersions = [Self.testStagingKeyID: Self.fixtureManifestVersion]
        appendFixtureResponses()

        try await makeService().checkForUpdates()

        XCTAssertTrue(vault.wasBrokerSavedCalled)
        XCTAssertEqual(settings.mainConfigETag, eTag)
    }

    func testWhenOnlyAnotherKeyHasSeenANewerManifestThenItIsAccepted() async throws {
        try stageExtractedBrokers()
        settings.lastManifestVersions = [Self.testProductionKeyID: 9999999999]
        appendFixtureResponses()

        try await makeService().checkForUpdates()

        XCTAssertEqual(settings.lastManifestVersions, [Self.testProductionKeyID: 9999999999, Self.testStagingKeyID: Self.fixtureManifestVersion])
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

    func testWhenInactiveBrokerDoesNotMatchDigestThenUpdateSucceeds() async throws {
        try stageExtractedBrokers()
        let inactiveBrokerFileName = "publicdatacheck.com.json"
        let mainConfig = try JSONDecoder().decode(MainConfig.self, from: try fixture("main_config.json"))
        XCTAssertNotNil(mainConfig.jsonETags.current[inactiveBrokerFileName])
        XCTAssertFalse(mainConfig.activeDataBrokers.contains(inactiveBrokerFileName))
        try Data("not the signed broker".utf8).write(to: extractedDirectoryURL.appendingPathComponent("json/\(inactiveBrokerFileName)"))
        appendFixtureResponses()

        try await makeService().checkForUpdates()

        XCTAssertTrue(firedVerificationFailures.isEmpty)
        XCTAssertEqual(settings.mainConfigETag, eTag)
    }

    func testSigningKeyStateSurvivesResettingBrokerDeliveryData() {
        settings.mainConfigETag = "previous"
        settings.lastManifestVersions = [Self.testStagingKeyID: Self.fixtureManifestVersion]
        settings.bundleSigningKeyFingerprint = Self.testStagingKeyID

        settings.resetBrokerDeliveryData()

        XCTAssertNil(settings.mainConfigETag)
        XCTAssertEqual(settings.lastManifestVersions, [Self.testStagingKeyID: Self.fixtureManifestVersion])
        XCTAssertEqual(settings.bundleSigningKeyFingerprint, Self.testStagingKeyID)
    }

    // MARK: - Signing key changes

    func testWhenSigningKeysAreFirstSeenOrUnchangedThenStoredBrokersAreKept() async throws {
        settings.mainConfigETag = eTag
        vault.brokers = [try inflatedAnyWhoBroker()]

        for _ in 0..<2 {
            appendNotModifiedResponse()
            try await makeService().checkForUpdates(skipsLimiter: true)
        }

        XCTAssertEqual(settings.bundleSigningKeyFingerprint, Self.testStagingKeyID)
        XCTAssertEqual(mainConfigRequests.map { $0.value(forHTTPHeaderField: "If-None-Match") }, [eTag, eTag])
        XCTAssertEqual(vault.brokers.map(\.version), ["99.0.0"])
    }

    func testWhenSigningKeysChangeThenBrokersSignedByTheOldKeyAreReplaced() async throws {
        settings.bundleSigningKeyFingerprint = Self.testProductionKeyID
        settings.mainConfigETag = eTag
        vault.brokers = [try inflatedAnyWhoBroker()]
        try stageExtractedBrokers()
        appendFixtureResponses()

        try await makeService().checkForUpdates()

        XCTAssertNil(mainConfigRequests.first?.value(forHTTPHeaderField: "If-None-Match"))
        XCTAssertEqual(vault.lastUpdatedBrokerResource?.broker.url, "anywho.com")
        XCTAssertEqual(vault.lastUpdatedBrokerResource?.broker.version, "0.4.0")
        XCTAssertEqual(settings.bundleSigningKeyFingerprint, Self.testStagingKeyID)
    }

    func testVerificationPixelsFollowThePlatformNaming() throws {
        for (platform, source, prefix) in [(DataBrokerProtectionSharedPixelsHandler.Platform.macOS, PixelKit.Source.macDMG, "m_mac_"),
                                           (.iOS, .iOS, "m_ios_")] {
            var firedPixels: [(name: String, parameters: [String: String])] = []
            let suiteName = "\(#function)-\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
            defer { defaults.removePersistentDomain(forName: suiteName) }
            let pixelKit = PixelKit(dryRun: false,
                                    appVersion: "1.0.0",
                                    source: source.rawValue,
                                    defaultHeaders: [:],
                                    defaults: defaults) { name, _, parameters, _, _, _ in
                firedPixels.append((name, parameters))
            }
            let handler = DataBrokerProtectionSharedPixelsHandler(pixelKit: pixelKit, platform: platform)

            handler.fire(.bundleVerificationFailure(reason: .digestMismatch))
            handler.fire(.bundleVerificationSuccess)

            XCTAssertEqual(firedPixels.map(\.name), ["\(prefix)dbp_bundle_verification_failure_daily",
                                                     "\(prefix)dbp_bundle_verification_failure_count",
                                                     "\(prefix)dbp_bundle_verification_success_daily"])
            XCTAssertEqual(firedPixels.map { $0.parameters["reason"] }, ["digest_mismatch", "digest_mismatch", nil])
        }
    }

    // MARK: - Helpers

    private var stagingVerifier: BrokerBundleVerifier {
        BrokerBundleVerifier(keys: BrokerBundleSigningKeys.dbpAPITestKeys.keys(isProductionEndpoint: false))
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

    private func makeService(signingKeys: BrokerBundleSigningKeys = .dbpAPITestKeys) -> RemoteBrokerJSONService {
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
                                       signingKeys: signingKeys)
    }

    /// A broker a compromised key could have signed: the real broker's ETag with a version no real update would exceed.
    private func inflatedAnyWhoBroker() throws -> DataBroker {
        let mainConfig = try JSONDecoder().decode(MainConfig.self, from: try fixture("main_config.json"))
        return DataBroker(id: 1,
                          name: "AnyWho",
                          url: "anywho.com",
                          steps: [],
                          version: "99.0.0",
                          schedulingConfig: .mock,
                          optOutUrl: "",
                          eTag: try XCTUnwrap(mainConfig.jsonETags.current["anywho.com.json"]),
                          removedAt: nil)
    }

    private func appendNotModifiedResponse() {
        let notModified = HTTPURLResponse(url: URL(string: "http://www.example.com")!, statusCode: 304, httpVersion: nil, headerFields: [:])!
        MockURLProtocol.requestHandlerQueue.append { [weak self] request in
            self?.mainConfigRequests.append(request)
            return (notModified, nil)
        }
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

    private func appendFixtureResponses(manifest: Data? = nil, signatureResponse: (HTTPURLResponse, Data?)? = nil) {
        let manifest = manifest ?? (try? fixture("main_config.json"))
        let mainConfigResponse = HTTPURLResponse(url: URL(string: "http://www.example.com")!,
                                                 statusCode: 200,
                                                 httpVersion: nil,
                                                 headerFields: ["ETag": eTag])!
        let signatureResponse = signatureResponse ?? (HTTPURLResponse(url: URL(string: "http://www.example.com")!,
                                                                      statusCode: 200,
                                                                      httpVersion: nil,
                                                                      headerFields: [:])!,
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

    private func assertCheckForUpdatesFails(with expectedError: BrokerBundleVerificationError,
                                            signingKeys: BrokerBundleSigningKeys = .dbpAPITestKeys,
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

extension BrokerBundleSigningKeys {
    /// dbp-api's test key pair, which signed the fixtures in `BundleResources/BrokerBundleSigning`. Never ship these.
    static let dbpAPITestKeys = BrokerBundleSigningKeys(
        production: ["MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAErmuPs8CapwHjt32La//bKRjV9ercvqY3jTzjWFSmdtnqI8ZrxOqMgEoKR6o0He6XZUy/oKOpW70+zur/7//+KQ=="],
        staging: ["MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEqpP7ubErpgXf5cpp1OFghScG7tJbhUhrKyzkxFdXGErtklupZcJx078xfZRmdYoxLbnaIAt3NYs9XeOr1oJESA=="]
    )
}

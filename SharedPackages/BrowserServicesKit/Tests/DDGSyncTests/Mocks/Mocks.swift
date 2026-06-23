//
//  Mocks.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

import Combine
import Common
import Foundation
import Gzip
import Persistence
import PersistenceTestingUtils
import PrivacyConfig
import PrivacyConfigTestsUtils
import Networking

@testable import DDGSync

extension SyncAccount {
    static var mock: SyncAccount {
        SyncAccount(
            deviceId: "deviceId",
            deviceName: "deviceName",
            deviceType: "deviceType",
            userId: "userId",
            primaryKey: "primaryKey".data(using: .utf8)!,
            secretKey: "secretKey".data(using: .utf8)!,
            token: "token",
            state: .active
        )
    }
}

extension RegisteredDevice {
    static var mock: RegisteredDevice {
        RegisteredDevice(id: "1", name: "2", type: "3")
    }
}

extension ProtectedKeyPublicKey {
    static var mock: ProtectedKeyPublicKey {
        ProtectedKeyPublicKey(alg: "RSA-OAEP-256",
                              e: "AQAB",
                              ext: true,
                              keyOps: ["encrypt"],
                              kty: "RSA",
                              n: "mod",
                              use: "enc")
    }
}

extension LoginResult {
    static var mock: LoginResult {
        LoginResult(account: .mock, devices: [.mock])
    }
}

class AccountManagingMock: AccountManaging {
    var createAccountCalls: [(deviceName: String, deviceType: String)] = []
    var createAccountError: Error?
    func createAccount(deviceName: String, deviceType: String) async throws -> SyncAccount {
        createAccountCalls.append((deviceName: deviceName, deviceType: deviceType))
        if let error = createAccountError {
            throw error
        }
        return .mock
    }

    func deleteAccount(_ account: SyncAccount) async throws {}

    var loginStub: LoginResult?
    var loginError: Error?
    var loginSpy: (SyncCode.RecoveryKey, String, String) -> Void = { _, _, _ in }
    var loginCalled: Bool = false
    func login(_ recoveryKey: SyncCode.RecoveryKey, deviceName: String, deviceType: String) async throws -> LoginResult {
        loginCalled = true
        loginSpy(recoveryKey, deviceName, deviceType)
        if let error = loginError {
            throw error
        }
        return loginStub ?? .mock
    }

    var refreshTokenStub: LoginResult?
    var refreshTokenError: Error?
    var refreshTokenCalled: Bool = false
    func refreshToken(_ account: SyncAccount, deviceName: String) async throws -> LoginResult {
        refreshTokenCalled = true
        if let refreshTokenError {
            throw refreshTokenError
        }
        return refreshTokenStub ?? .mock
    }

    var logoutCalls: [(deviceId: String, token: String)] = []
    var logoutError: Error?
    func logout(deviceId: String, token: String) async throws {
        logoutCalls.append((deviceId: deviceId, token: token))
        if let logoutError {
            throw logoutError
        }
    }

    func fetchDevicesForAccount(_ account: SyncAccount) async throws -> [RegisteredDevice] {
        [.mock]
    }
}

final class SchedulerMock: SchedulingInternal {
    var isEnabled: Bool = false

    let startSyncPublisher: AnyPublisher<Void, Never>
    let cancelSyncPublisher: AnyPublisher<Void, Never>
    let resumeSyncPublisher: AnyPublisher<Void, Never>

    init() {
        startSyncPublisher = startSyncSubject.eraseToAnyPublisher()
        cancelSyncPublisher = cancelSyncSubject.eraseToAnyPublisher()
        resumeSyncPublisher = resumeSyncSubject.eraseToAnyPublisher()
    }

    func notifyDataChanged() {
        if isEnabled {
            startSyncSubject.send()
        }
    }

    func notifyAppLifecycleEvent() {
        if isEnabled {
            startSyncSubject.send()
        }
    }

    func requestSyncImmediately() {
        if isEnabled {
            startSyncSubject.send()
        }
    }

    func cancelSyncAndSuspendSyncQueue() {
        cancelSyncSubject.send()
    }

    func resumeSyncQueue() {
        resumeSyncSubject.send()
    }

    private var startSyncSubject = PassthroughSubject<Void, Never>()
    private var cancelSyncSubject = PassthroughSubject<Void, Never>()
    private var resumeSyncSubject = PassthroughSubject<Void, Never>()
}

class MockErrorHandler: EventMapping<SyncError> {

    private var _handledErrors: NSMutableArray?
    var handledErrors: [SyncError] {
        _handledErrors as? [SyncError] ?? []
    }

    convenience init() {
        let handledErrors = NSMutableArray()
        self.init { e, _, _, _ in
            handledErrors.add(e)
        }
        _handledErrors = handledErrors
    }
}

extension DefaultInternalUserDecider {
    convenience init(mockedStore: MockInternalUserStoring = MockInternalUserStoring()) {
        self.init(store: mockedStore)
    }
}

class MockPrivacyConfiguration: PrivacyConfiguration {

    func isEnabled(featureKey: PrivacyFeature, versionProvider: AppVersionProvider, defaultValue: Bool) -> Bool { true }

    func stateFor(featureKey: PrivacyFeature, versionProvider: AppVersionProvider) -> PrivacyConfigurationFeatureState {
        return .enabled
    }

    func isSubfeatureEnabled(_ subfeature: any PrivacySubfeature, versionProvider: AppVersionProvider, randomizer: (Range<Double>) -> Double, defaultValue: Bool) -> Bool {
        true
    }

    func stateFor(_ subfeature: any PrivacySubfeature, versionProvider: AppVersionProvider, randomizer: (Range<Double>) -> Double) -> PrivacyConfigurationFeatureState {
        return .enabled
    }

    func stateFor(subfeatureID: SubfeatureID, parentFeatureID: ParentFeatureID, versionProvider: AppVersionProvider, randomizer: (Range<Double>) -> Double) -> PrivacyConfigurationFeatureState {
        return .enabled
    }

    func cohorts(for subfeature: any PrivacySubfeature) -> [PrivacyConfigurationData.Cohort]? {
        return nil
    }

    func cohorts(subfeatureID: SubfeatureID, parentFeatureID: ParentFeatureID) -> [PrivacyConfigurationData.Cohort]? {
        return nil
    }

    func settings(for subfeature: any PrivacySubfeature) -> PrivacyConfigurationData.PrivacyFeature.SubfeatureSettings? {
        return nil
    }

    var identifier: String = "abcd"
    var version: String? = "123456789"
    var userUnprotectedDomains: [String] = []
    var tempUnprotectedDomains: [String] = []
    var trackerAllowlist: PrivacyConfigurationData.TrackerAllowlist = .init(json: ["state": "disabled"])!
    func exceptionsList(forFeature featureKey: PrivacyFeature) -> [String] { [] }
    func isFeature(_ feature: PrivacyFeature, enabledForDomain: String?) -> Bool { true }
    func isProtected(domain: String?) -> Bool { false }
    func isUserUnprotected(domain: String?) -> Bool { false }
    func isTempUnprotected(domain: String?) -> Bool { false }
    func isInExceptionList(domain: String?, forFeature featureKey: PrivacyFeature) -> Bool { false }
    func settings(for feature: PrivacyFeature) -> PrivacyConfigurationData.PrivacyFeature.FeatureSettings { .init() }
    func userEnabledProtection(forDomain: String) {}
    func userDisabledProtection(forDomain: String) {}
}

final class MockSyncDependencies: SyncDependencies, SyncDependenciesDebuggingSupport {

    var endpoints: Endpoints = Endpoints(baseURL: URL(string: "https://dev.null")!)
    var account: AccountManaging = AccountManagingMock()
    var scopedAccess: ScopedAccessCredentialManaging = ScopedAccessCredentialManagingMock()
    var api: RemoteAPIRequestCreating = RemoteAPIRequestCreatingMock()
    var payloadCompressor: SyncPayloadCompressing = SyncGzipPayloadCompressorMock()
    var secureStore: SecureStoring = SecureStorageStub()
    var crypter: CryptingInternal = CryptingMock()
    var scheduler: SchedulingInternal = SchedulerMock()
    var privacyConfigurationManager: PrivacyConfigurationManaging = MockPrivacyConfigurationManager(privacyConfig: MockPrivacyConfiguration())
    var errorEvents: EventMapping<SyncError> = MockErrorHandler()
    var shouldPreserveAccountWhenSyncDisabled: () -> Bool = { false }
    var isScopedAccessCredentialsEnabled: () -> Bool = { true }
    var isPairingV2ScanningEnabled: () -> Bool = { true }
    var isPairingV2CodeEnabled: () -> Bool = { true }
    lazy var syncFeatureFlags: any SyncFeatureFlagProviding = SyncFeatureFlagProvider(
        isScopedAccessCredentialsEnabled: { [weak self] in self?.isScopedAccessCredentialsEnabled() == true },
        isPairingV2ScanningEnabled: { [weak self] in self?.isPairingV2ScanningEnabled() == true },
        isPairingV2CodeEnabled: { [weak self] in self?.isPairingV2CodeEnabled() == true }
    )
    var keyValueStore: ThrowingKeyValueStoring = try! MockKeyValueFileStore()
    var legacyKeyValueStore: KeyValueStoring = MockKeyValueStore()

    var request = HTTPRequestingMock()

    init() {
        (api as! RemoteAPIRequestCreatingMock).request = request
    }

    var createRemoteConnectorStub: RemoteConnecting?
    func createRemoteConnector() throws -> RemoteConnecting {
        createRemoteConnectorStub ?? MockRemoteConnecting()
    }

    var createRemoteKeyExchangerStub: RemoteKeyExchanging?
    func createRemoteKeyExchanger() throws -> any RemoteKeyExchanging {
        createRemoteKeyExchangerStub ?? MockRemoteKeyExchanging()
    }

    var createRemoteExchangeRecoverer: RemoteExchangeRecovering?
    func createRemoteExchangeRecoverer(_ exchangeInfo: ExchangeInfo) throws -> any RemoteExchangeRecovering {
        createRemoteExchangeRecoverer ?? MockRemoteExchangeRecovering()
    }

    var createRecoveryTransmitterStub: RecoveryKeyTransmitting?
    func createRecoveryKeyTransmitter() throws -> RecoveryKeyTransmitting {
        createRecoveryTransmitterStub ?? MockRecoveryKeyTransmitting()
    }

    var createExchangePublicKeyTransmitterStub: ExchangePublicKeyTransmitting?
    func createExchangePublicKeyTransmitter() throws -> ExchangePublicKeyTransmitting {
        createExchangePublicKeyTransmitterStub ?? MockExchangePublicKeyTransmitting()
    }

    var createExchangeRecoveryKeyTransmitterStub: ExchangeRecoveryKeyTransmitting?
    func createExchangeRecoveryKeyTransmitter(exchangeMessage: ExchangeMessage) throws -> ExchangeRecoveryKeyTransmitting {
        createExchangeRecoveryKeyTransmitterStub ?? MockExchangeRecoveryKeyTransmitting()
    }

    var createPairingV2MessageExchangerStub: PairingV2MessageExchanging?
    var createPairingV2MessageExchangerCallCount = 0
    func createPairingV2MessageExchanger() -> PairingV2MessageExchanging {
        createPairingV2MessageExchangerCallCount += 1
        return createPairingV2MessageExchangerStub ?? PairingV2MessageExchangingMock()
    }

    var createThirdPartyAccountUpgradeCoordinatorStub: ThirdPartyAccountUpgradeCoordinating?
    func createThirdPartyAccountUpgradeCoordinator() -> ThirdPartyAccountUpgradeCoordinating {
        createThirdPartyAccountUpgradeCoordinatorStub ?? ThirdPartyAccountUpgradeCoordinatingMock()
    }

    func updateServerEnvironment(_ serverEnvironment: ServerEnvironment) {}

    var createTokenRescopeStub: TokenRescoping?
    func createTokenRescope() -> any TokenRescoping {
        createTokenRescopeStub ?? MockTokenRescoping()
    }

    var createAIChatsStub: AIChatsHandling?
    func createAIChats() -> any AIChatsHandling {
        createAIChatsStub ?? MockAIChatsHandling()
    }

}

final class PairingV2MessageExchangingMock: PairingV2MessageExchanging {
    var openChannelCalls: [String] = []
    var openChannelHandler: ((String) async throws -> Void)?
    var sendCalls: [(messages: [PairingV2EncryptedMessage], channelID: String)] = []
    var sendHandler: (([PairingV2EncryptedMessage], String) async throws -> Void)?
    var sendError: Error?
    var fetchMessagesCalls: [(channelID: String, sequence: Int)] = []
    var fetchMessagesHandler: ((String, Int) async throws -> [PairingV2SequencedMessage])?
    var fetchMessagesStub: [PairingV2SequencedMessage] = []
    var fetchMessagesError: Error?
    var closeChannelCalls: [String] = []
    var closeChannelHandler: ((String) async throws -> Void)?

    func openChannel(_ channelID: String) async throws {
        openChannelCalls.append(channelID)
        try await openChannelHandler?(channelID)
    }

    func send(_ messages: [PairingV2EncryptedMessage], to channelID: String) async throws {
        sendCalls.append((messages: messages, channelID: channelID))
        if let sendError {
            throw sendError
        }
        if let sendHandler {
            try await sendHandler(messages, channelID)
        }
    }

    func fetchMessages(from channelID: String, after sequence: Int) async throws -> [PairingV2SequencedMessage] {
        fetchMessagesCalls.append((channelID: channelID, sequence: sequence))
        if let fetchMessagesError {
            throw fetchMessagesError
        }
        if let fetchMessagesHandler {
            return try await fetchMessagesHandler(channelID, sequence)
        }
        return fetchMessagesStub
    }

    func closeChannel(_ channelID: String) async throws {
        closeChannelCalls.append(channelID)
        try await closeChannelHandler?(channelID)
    }
}

final class ScopedAccessCredentialManagingMock: ScopedAccessCredentialManaging {

    var recoverScopedPasswordCalls: [(accessCredentials: [AccessCredential]?, primaryKey: Data, userID: String)] = []
    var recoverScopedPasswordStub: Data?
    var recoverScopedPasswordError: Error?
    func recoverScopedPassword(from accessCredentials: [AccessCredential]?, primaryKey: Data, userID: String) throws -> Data? {
        recoverScopedPasswordCalls.append((accessCredentials: accessCredentials, primaryKey: primaryKey, userID: userID))
        if let recoverScopedPasswordError {
            throw recoverScopedPasswordError
        }
        return recoverScopedPasswordStub
    }

    var ensureThirdPartyScopedPasswordCalls: [(account: SyncAccount, purpose: String)] = []
    var ensureThirdPartyScopedPasswordStub: EnsuredThirdPartyCredential?
    var ensureThirdPartyScopedPasswordError: Error?
    func ensureThirdPartyScopedPassword(for account: SyncAccount,
                                        purpose: String,
                                        cachedScopedPassword: () throws -> Data?) async throws -> EnsuredThirdPartyCredential {
        ensureThirdPartyScopedPasswordCalls.append((account: account, purpose: purpose))
        if let ensureThirdPartyScopedPasswordError {
            throw ensureThirdPartyScopedPasswordError
        }
        if let ensureThirdPartyScopedPasswordStub {
            return ensureThirdPartyScopedPasswordStub
        }
        return EnsuredThirdPartyCredential(scopedPassword: try cachedScopedPassword() ?? Data(repeating: 1, count: 32),
                                           protectedKeysToCache: [])
    }

    var makeRecoveryCodeCalls: [(account: SyncAccount, scopedPassword: Data)] = []
    var makeRecoveryCodeStub: String?
    func makeRecoveryCode(for account: SyncAccount, scopedPassword: Data) -> String? {
        makeRecoveryCodeCalls.append((account: account, scopedPassword: scopedPassword))
        if let makeRecoveryCodeStub {
            return makeRecoveryCodeStub
        }
        guard !scopedPassword.isEmpty else {
            return nil
        }
        let payload = SyncCode.RecoveryKeyV2(
            userId: account.userId,
            secret: Base64URL.encode(scopedPassword),
            cid: SyncCode.RecoveryKeyV2.thirdPartyCredentialId,
            v: SyncCode.RecoveryKeyV2.currentVersion
        )
        guard let json = try? SyncCode(recovery: .v2(payload)).toJSON() else {
            return nil
        }
        return Base64URL.encode(json)
    }

    var fetchAccessCredentialsCalls: [SyncAccount] = []
    var fetchAccessCredentialsStub: [AccessCredential] = []
    var fetchAccessCredentialsError: Error?
    func fetchAccessCredentials(_ account: SyncAccount) async throws -> [AccessCredential] {
        fetchAccessCredentialsCalls.append(account)
        if let fetchAccessCredentialsError {
            throw fetchAccessCredentialsError
        }
        return fetchAccessCredentialsStub
    }

    var fetchProtectedKeysCalls: [SyncAccount] = []
    var fetchProtectedKeysStub: [ProtectedKey] = []
    var fetchProtectedKeysError: Error?
    func fetchProtectedKeys(_ account: SyncAccount) async throws -> [ProtectedKey] {
        fetchProtectedKeysCalls.append(account)
        if let fetchProtectedKeysError {
            throw fetchProtectedKeysError
        }
        return fetchProtectedKeysStub
    }

    var setKeyIfAbsentCalls: [(purpose: String, key: ProtectedKey, account: SyncAccount)] = []
    var setKeyIfAbsentStub: ProtectedKey?
    var setKeyIfAbsentError: Error?
    func setKeyIfAbsent(purpose: String, key: ProtectedKey, for account: SyncAccount) async throws -> ProtectedKey? {
        setKeyIfAbsentCalls.append((purpose: purpose, key: key, account: account))
        if let setKeyIfAbsentError {
            throw setKeyIfAbsentError
        }
        return setKeyIfAbsentStub
    }
}

final class ThirdPartyAccountUpgradeCoordinatingMock: ThirdPartyAccountUpgradeCoordinating {
    var upgradeThirdPartyAccountCalls: [(recoveryCode: String, deviceName: String, deviceType: String)] = []
    var upgradeThirdPartyAccountStub = UpgradedThirdPartyAccount(account: .mock,
                                                                devices: [.mock],
                                                                scopedPassword: Data(repeating: 1, count: 32),
                                                                protectedKeys: [])
    var upgradeThirdPartyAccountError: Error?

    func upgradeThirdPartyAccountToDefaultCredential(_ recoveryCode: String,
                                                     deviceName: String,
                                                     deviceType: String) async throws -> UpgradedThirdPartyAccount {
        upgradeThirdPartyAccountCalls.append((recoveryCode: recoveryCode, deviceName: deviceName, deviceType: deviceType))
        if let upgradeThirdPartyAccountError {
            throw upgradeThirdPartyAccountError
        }
        return upgradeThirdPartyAccountStub
    }
}

final class MockRemoteConnecting: RemoteConnecting {
    var code: String = ""

    var pollForRecoveryKeyCalled = 0
    var pollForRecoveryKeyError: Error?
    var pollForRecoveryKeyStub: SyncCode.RecoveryKey?
    func pollForRecoveryKey() async throws -> SyncCode.RecoveryKey? {
        if let error = pollForRecoveryKeyError {
            throw error
        }
        pollForRecoveryKeyCalled += 1
        return pollForRecoveryKeyStub
    }

    var stopPollingCalled = 0
    func stopPolling() {
        stopPollingCalled += 1
    }
}

final class MockRemoteKeyExchanging: RemoteKeyExchanging {
    var code: String
    var pollForPublicKeyCalled = 0
    var pollForPublicKeyResult: ExchangeMessage?
    var pollForPublicKeyError: Error?
    var stopPollingCalled = 0
    var stopPollingCallback: (() -> Void) = { }

    init(code: String = "", pollResult: ExchangeMessage? = nil) {
        self.code = code
        self.pollForPublicKeyResult = pollResult
    }

    func pollForPublicKey() async throws -> ExchangeMessage? {
        pollForPublicKeyCalled += 1
        if let error = pollForPublicKeyError { throw error }
        return pollForPublicKeyResult
    }

    func stopPolling() {
        stopPollingCalled += 1
        stopPollingCallback()
    }
}

final class MockRecoveryKeyTransmitting: RecoveryKeyTransmitting {
    var sendCalled = 0
    var sendSpy: SyncCode.ConnectCode?
    var sendError: Error?
    func send(_ code: SyncCode.ConnectCode) async throws {
        if let error = sendError {
            throw error
        }
        sendCalled += 1
        sendSpy = code
    }
}

final class MockExchangePublicKeyTransmitting: ExchangePublicKeyTransmitting {

    var sendGeneratedExchangeInfoCalled = 0
    var sendGeneratedExchangeInfoError: Error?
    var sendGeneratedExchangeInfoStub: ExchangeInfo?
    func sendGeneratedExchangeInfo(_ code: SyncCode.ExchangeKey, deviceName: String) async throws -> ExchangeInfo {
        if let sendGeneratedExchangeInfoError { throw sendGeneratedExchangeInfoError }
        sendGeneratedExchangeInfoCalled += 1
        return sendGeneratedExchangeInfoStub ?? ExchangeInfo(keyId: "", publicKey: .init(), secretKey: .init())
    }
}

final class MockExchangeRecoveryKeyTransmitting: ExchangeRecoveryKeyTransmitting {

    var sendCalled = 0
    var sendError: Error?
    func send() async throws {
        guard sendError == nil else { throw sendError! }
        sendCalled += 1
    }
}

final class MockTokenRescoping: TokenRescoping {

    private(set) var rescopeCalls: [(scope: String, token: String)] = []
    var rescopeResult: String?
    var rescopeError: Error?

    func rescope(scope: String, token: String) async throws -> String? {
        rescopeCalls.append((scope: scope, token: token))
        if let rescopeError {
            throw rescopeError
        }
        return rescopeResult
    }
}

final class MockAIChatsHandling: AIChatsHandling {

    private(set) var deleteCalls: [(until: Date, token: String)] = []
    private(set) var deleteChatIdsCalls: [(chatIds: [String], token: String)] = []
    private(set) var patchCalls: [(updates: [AIChatUpdate], token: String)] = []
    var deleteError: Error?
    var patchError: Error?

    func delete(until: Date, token: String) async throws {
        deleteCalls.append((until: until, token: token))
        if let deleteError {
            throw deleteError
        }
    }

    func delete(chatIds: [String], token: String) async throws {
        deleteChatIdsCalls.append((chatIds: chatIds, token: token))
        if let deleteError {
            throw deleteError
        }
    }

    func patch(updates: [AIChatUpdate], token: String) async throws {
        patchCalls.append((updates: updates, token: token))
        if let patchError {
            throw patchError
        }
    }
}

final class MockDataProvidersSource: DataProvidersSource {
    var dataProviders: [DataProviding] = []

    func makeDataProviders() -> [DataProviding] {
        dataProviders
    }
}

class HTTPRequestingMock: HTTPRequesting {

    init(result: HTTPResult = .init(data: Data(), response: HTTPURLResponse())) {
        self.result = result
    }

    var executeCallCount = 0
    var error: SyncError?
    var result: HTTPResult

    func execute() async throws -> HTTPResult {
        executeCallCount += 1
        if let error {
            throw error
        }
        return result
    }
}

final class SequencedHTTPRequestingMock: HTTPRequestingMock {
    private var results: [HTTPResult]

    init(results: [HTTPResult]) {
        self.results = results
        super.init(result: results.last ?? .init(data: Data(), response: HTTPURLResponse()))
    }

    override func execute() async throws -> HTTPResult {
        executeCallCount += 1
        if let error {
            throw error
        }
        if results.count > 1 {
            return results.removeFirst()
        }
        return results.first ?? result
    }
}

class RemoteAPIRequestCreatingMock: RemoteAPIRequestCreating {
    var createRequestCallCount = 0
    var createRequestCallArgs: [CreateRequestCallArgs] = []
    var request: HTTPRequesting = HTTPRequestingMock()
    var fakeRequests: [URL: HTTPRequestingMock] = [:]
    private let lock = NSLock()

    struct CreateRequestCallArgs: Equatable {
        let url: URL
        let method: Networking.APIRequest.HTTPMethod
        let headers: [String: String]
        let parameters: [String: String]
        let body: Data?
        let contentType: String?
    }

    func createRequest(url: URL, method: Networking.APIRequest.HTTPMethod, headers: [String: String], parameters: [String: String], body: Data?, contentType: String?) -> HTTPRequesting {
        lock.lock()
        defer { lock.unlock() }
        createRequestCallCount += 1
        createRequestCallArgs.append(CreateRequestCallArgs(url: url, method: method, headers: headers, parameters: parameters, body: body, contentType: contentType))
        return fakeRequests[url] ?? request
    }
}

class InspectableSyncRequestMaker: SyncRequestMaking {

    struct MakePatchRequestCallArgs {
        let result: SyncRequest
        let clientTimestamp: Date
        let isCompressed: Bool
    }

    func makeGetRequest(with result: SyncRequest) throws -> HTTPRequesting {
        try requestMaker.makeGetRequest(with: result)
    }

    func makePatchRequest(with result: SyncRequest, clientTimestamp: Date, isCompressed: Bool) throws -> HTTPRequesting {
        lock.lock()
        defer { lock.unlock() }

        makePatchRequestCallCount += 1
        makePatchRequestCallArgs.append(.init(result: result, clientTimestamp: clientTimestamp, isCompressed: isCompressed))
        return try requestMaker.makePatchRequest(with: result, clientTimestamp: clientTimestamp, isCompressed: isCompressed)
    }

    let requestMaker: SyncRequestMaker
    private let lock = NSLock()

    init(requestMaker: SyncRequestMaker) {
        self.requestMaker = requestMaker
    }

    var makePatchRequestCallCount = 0
    var makePatchRequestCallArgs: [MakePatchRequestCallArgs] = []
}

class SyncGzipPayloadCompressorMock: SyncPayloadCompressing {
    var error: Error?

    func compress(_ payload: Data) throws -> Data {
        if let error {
            throw error
        }
        return try payload.gzipped()
    }
}

struct CryptingMock: CryptingInternal {

    var _encryptAndBase64Encode: (String) throws -> String = { "encrypted_\($0)" }
    var _base64DecodeAndDecrypt: (String) throws -> String = { $0.dropping(prefix: "encrypted_") }
    var _extractLoginInfo: (SyncCode.RecoveryKey) throws -> ExtractedLoginInfo = { _ in
        ExtractedLoginInfo(userId: "user", primaryKey: Data(), passwordHash: Data(), stretchedPrimaryKey: Data())
    }
    var _createAccountCreationKeys: (String, String) throws -> AccountCreationKeys = { _, _ in
        AccountCreationKeys(primaryKey: Data(), secretKey: Data(), protectedSecretKey: Data(), passwordHash: Data())
    }
    var _extractSecretKey: (Data, Data) throws -> Data = { _, _ in Data() }

    func fetchSecretKey() throws -> Data {
        .init()
    }

    func encrypt(_ value: Data, using secretKey: Data) throws -> Data {
        // Test helper: treat input as UTF-8 if possible, otherwise pass through.
        if let string = String(data: value, encoding: .utf8) {
            return try encrypt(string, using: secretKey)
        }
        return Data(Base64URL.encode(value).utf8)
    }

    func decryptData(_ value: Data, using secretKey: Data) throws -> Data {
        if let string = String(data: value, encoding: .utf8), let decoded = Base64URL.decode(string) {
            return decoded
        }
        // Test helper: decrypt to UTF-8 string and return UTF-8 bytes.
        return Data(try decrypt(value, using: secretKey).utf8)
    }

    func encrypt(_ value: String, using secretKey: Data) throws -> Data {
        Data(try _encryptAndBase64Encode(value).utf8)
    }

    func decrypt(_ value: Data, using secretKey: Data) throws -> String {
        guard let string = String(data: value, encoding: .utf8) else {
            throw SyncError.failedToDecryptValue("bytes could not be converted to string")
        }
        return try _base64DecodeAndDecrypt(string)
    }

    func encryptAndBase64Encode(_ value: String) throws -> String {
        try _encryptAndBase64Encode(value)
    }

    func base64DecodeAndDecrypt(_ value: String) throws -> String {
        try _base64DecodeAndDecrypt(value)
    }

    func encryptAndBase64Encode(_ value: String, using secretKey: Data) throws -> String {
        try _encryptAndBase64Encode(value)
    }

    func base64DecodeAndDecrypt(_ value: String, using secretKey: Data) throws -> String {
        try _base64DecodeAndDecrypt(value)
    }

    func seal(_ data: Data, secretKey: Data) throws -> Data {
        data
    }

    func unseal(encryptedData: Data, publicKey: Data, secretKey: Data) throws -> Data {
        encryptedData
    }

    func jwtSeal(_ data: Data, secretKey key: Data) throws -> Data {
        data
    }

    func jwtUnseal(_ data: Data, secretKey key: Data) throws -> Data {
        data
    }

    func createAccountCreationKeys(userId: String, password: String) throws -> AccountCreationKeys {
        try _createAccountCreationKeys(userId, password)
    }

    func extractLoginInfo(recoveryKey: SyncCode.RecoveryKey) throws -> ExtractedLoginInfo {
        try _extractLoginInfo(recoveryKey)
    }

    func extractSecretKey(protectedSecretKey: Data, stretchedPrimaryKey: Data) throws -> Data {
        try _extractSecretKey(protectedSecretKey, stretchedPrimaryKey)
    }

    func prepareForConnect() throws -> ConnectInfo {
        ConnectInfo(deviceID: "1234", publicKey: Data(), secretKey: Data())
    }

    func prepareForExchange() throws -> ExchangeInfo {
        ExchangeInfo(keyId: "1234", publicKey: Data(), secretKey: Data())
    }
}

class SyncMetadataStoreMock: SyncMetadataStore {
    struct FeatureInfo: Equatable {
        var timestamp: String?
        var localTimestamp: Date?
        var state: FeatureSetupState
    }

    var features: [String: FeatureInfo] = [:]

    func isFeatureRegistered(named name: String) -> Bool {
        features.keys.contains(name)
    }

    func registerFeature(named name: String, setupState: FeatureSetupState) throws {
        features[name] = .init(state: setupState)
    }

    func deregisterFeature(named name: String) throws {
        features.removeValue(forKey: name)
    }

    func timestamp(forFeatureNamed name: String) -> String? {
        features[name]?.timestamp
    }

    func updateTimestamp(_ timestamp: String?, forFeatureNamed name: String) {
        features[name]?.timestamp = timestamp
    }

    func localTimestamp(forFeatureNamed name: String) -> Date? {
        features[name]?.localTimestamp
    }

    func state(forFeatureNamed name: String) -> FeatureSetupState {
        features[name]?.state ?? .readyToSync
    }

    func updateLocalTimestamp(_ localTimestamp: Date?, forFeatureNamed name: String) {
        features[name]?.localTimestamp = localTimestamp
    }

    func update(_ serverTimestamp: String?, _ localTimestamp: Date?, _ state: FeatureSetupState, forFeatureNamed name: String) {
        features[name]?.state = state
        features[name]?.timestamp = serverTimestamp
        features[name]?.localTimestamp = localTimestamp
    }
}

class DataProvidingMock: DataProvider {

    init(feature: Feature, syncDidUpdateData: @escaping () -> Void = {}) {
        super.init(feature: feature, metadataStore: SyncMetadataStoreMock(), syncDidUpdateData: syncDidUpdateData)
    }

    var _prepareForFirstSync: () throws -> Void = {}
    var _fetchChangedObjects: (Crypting) async throws -> [Syncable] = { _ in return [] }
    var handleInitialSyncResponse: ([Syncable], Date, String?, Crypting) async throws -> Void = { _, _, _, _ in }
    var handleSyncResponse: ([Syncable], [Syncable], Date, String?, Crypting) async throws -> Void = { _, _, _, _, _ in }
    var _handleSyncError: (Error) -> Void = { _ in }

    override func prepareForFirstSync() throws {
        try _prepareForFirstSync()
    }

    override func fetchChangedObjects(encryptedUsing crypter: Crypting) async throws -> [Syncable] {
        try await _fetchChangedObjects(crypter)
    }

    override func handleInitialSyncResponse(received: [Syncable], clientTimestamp: Date, serverTimestamp: String?, crypter: Crypting) async throws {
        try await handleInitialSyncResponse(received, clientTimestamp, serverTimestamp, crypter)
        updateSyncTimestamps(server: serverTimestamp, local: clientTimestamp)
    }

    override func handleSyncResponse(sent: [Syncable], received: [Syncable], clientTimestamp: Date, serverTimestamp: String?, crypter: Crypting) async throws {
        try await handleSyncResponse(sent, received, clientTimestamp, serverTimestamp, crypter)
        updateSyncTimestamps(server: serverTimestamp, local: clientTimestamp)
    }

    override func handleSyncError(_ error: Error) {
        _handleSyncError(error)
    }
}

//
//  DDGSync.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
import CombineExtensions
import Common
import FoundationExtensions
import DDGSyncCrypto
import Foundation
import os.log
import Persistence
import PrivacyConfig
import Security

public class DDGSync: DDGSyncing {

    public static let bundle = Bundle.module

    @Published public private(set) var featureFlags: SyncFeatureFlags = .all
    public var featureFlagsPublisher: AnyPublisher<SyncFeatureFlags, Never> {
        $featureFlags.eraseToAnyPublisher()
    }

    public enum Constants {
        public static let syncEnabledKey = "com.duckduckgo.sync.enabled"
        static let auditLogReviewStateKey = "com.duckduckgo.sync.audit-log.review-state"
        public static let keychainAttrMigratedKey = "com.duckduckgo.sync.keychain.attr.migrated"
        static let aiChatHistoryEnabledKey = "com.duckduckgo.aichat.sync.chatHistoryEnabled"
        static let auditLogPageSize = 100
    }

    private enum UnauthenticatedHandling {
        case logoutOn401
        case doNotLogoutOn401
    }

    @Published public private(set) var authState = SyncAuthState.initializing
    public var authStatePublisher: AnyPublisher<SyncAuthState, Never> {
        $authState.eraseToAnyPublisher()
    }

    public var account: SyncAccount? {
        do {
            return try dependencies.secureStore.account()
        } catch {
            if let syncError = error as? SyncError {
                dependencies.errorEvents.fire(syncError, error: syncError)
            }
            return nil
        }
    }

    public var recoveryCode: String? {
        guard dependencies.syncFeatureFlags.isPairingV2ScanningEnabled(),
              dependencies.syncFeatureFlags.isPairingV2CodeEnabled() else {
            return account?.legacyRecoveryCodeV1
        }
        return account?.recoveryCodeV2
    }

    public var scheduler: Scheduling {
        dependencies.scheduler
    }

    public let syncDailyStats = SyncDailyStats()

    @Published public var isSyncInProgress: Bool = false

    public var isSyncInProgressPublisher: AnyPublisher<Bool, Never> {
        $isSyncInProgress.dropFirst().removeDuplicates().eraseToAnyPublisher()
    }

    public weak var dataProvidersSource: DataProvidersSource?
    private var customOperations: [any SyncCustomOperation] = []
    private let deviceInfoMigrationCoordinator: DeviceInfoMigrationCoordinating

    /// This is the constructor intended for use by app clients.
    public convenience init(dataProvidersSource: DataProvidersSource,
                            errorEvents: EventMapping<SyncError>,
                            unifiedDeviceListEvents: EventMapping<UnifiedDeviceListEvent>? = nil,
                            privacyConfigurationManager: PrivacyConfigurationManaging,
                            keyValueStore: ThrowingKeyValueStoring,
                            environment: ServerEnvironment = .production,
                            syncFeatureFlags: any SyncFeatureFlagProviding,
                            shouldPreserveAccountWhenSyncDisabled: @escaping () -> Bool = { false }) {
        let dependencies = ProductionDependencies(
            serverEnvironment: environment,
            privacyConfigurationManager: privacyConfigurationManager,
            keyValueStore: keyValueStore,
            errorEvents: errorEvents,
            unifiedDeviceListEvents: unifiedDeviceListEvents,
            syncFeatureFlags: syncFeatureFlags,
            shouldPreserveAccountWhenSyncDisabled: shouldPreserveAccountWhenSyncDisabled
        )
        self.init(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
    }

    public func createAccount(deviceName: String, deviceType: String) async throws {
        guard try dependencies.secureStore.account() == nil else {
            throw SyncError.accountAlreadyExists
        }

        let result = try await dependencies.account.createAccount(deviceName: deviceName, deviceType: deviceType)
        try updateAccount(result.account)
        if result.didPublishDeviceInfo {
            deviceInfoMigrationCoordinator.recordSuccessfulUnifiedWrite(for: result.account)
        } else {
            scheduleDeviceInfoMigration(for: result.account)
        }
        scheduler.requestSyncImmediately()
    }

    public func login(_ recoveryKey: SyncCode.RecoveryKey, deviceName: String, deviceType: String) async throws -> [RegisteredDevice] {
        guard try dependencies.secureStore.account() == nil else {
            throw SyncError.accountAlreadyExists
        }

        let result = try await dependencies.account.login(recoveryKey, deviceName: deviceName, deviceType: deviceType)
        try updateAccount(result.account)
        persistRecoveredThirdPartyScopedPasswordIfAvailable(from: result.accessCredentials, account: result.account)
        updateProtectedKeysCache(with: result.keys)
        scheduleDeviceInfoMigration(for: result.account)
        scheduler.requestSyncImmediately()
        return result.devices
    }

    public func remoteConnect() throws -> RemoteConnecting {
        guard try dependencies.secureStore.account() == nil else {
            throw SyncError.accountAlreadyExists
        }
        return try dependencies.createRemoteConnector()
    }

    public func transmitRecoveryKey(_ connectCode: SyncCode.ConnectCode) async throws {
        guard try dependencies.secureStore.account() != nil else {
            throw SyncError.accountNotFound
        }

        do {
            try await dependencies.createRecoveryKeyTransmitter().send(connectCode)
        } catch {
            throw handleUnauthenticatedAndMap(error)
        }
    }

    public func createConnectionController(deviceName: String, deviceType: String, delegate: SyncConnectionControllerDelegate) -> SyncConnectionControlling {
        SyncConnectionController(deviceName: deviceName, deviceType: deviceType, delegate: delegate, syncService: self, dependencies: dependencies)
    }

    public func transmitGeneratedExchangeInfo(_ exchangeCode: SyncCode.ExchangeKey, deviceName: String) async throws -> ExchangeInfo {
        do {
            return try await dependencies.createExchangePublicKeyTransmitter().sendGeneratedExchangeInfo(exchangeCode, deviceName: deviceName)
        } catch {
            throw handleUnauthenticatedAndMap(error)
        }
    }

    public func transmitExchangeRecoveryKey(for exchangeMessage: ExchangeMessage) async throws {
        do {
            try await dependencies.createExchangeRecoveryKeyTransmitter(exchangeMessage: exchangeMessage).send()
        } catch {
            throw handleUnauthenticatedAndMap(error)
        }
    }

    public func mainTokenRescope(to scope: String) async throws -> String? {
        guard let account = account else { throw SyncError.accountNotFound }
        guard let token = account.token else { throw SyncError.noToken }
        do {
            return try await dependencies.createTokenRescope().rescope(scope: scope, token: token)
        } catch {
            throw handleUnauthenticatedAndMap(error)
        }
    }

    public func deleteAIChats(until: Date) async throws {
        guard let account = account else { throw SyncError.accountNotFound }
        guard let token = account.token else { throw SyncError.noToken }
        do {
            try await dependencies.createAIChats().delete(until: until, token: token)
        } catch {
            throw handleUnauthenticatedAndMap(error, policy: .doNotLogoutOn401)
        }
    }

    public func deleteAIChats(chatIds: [String]) async throws {
        guard let account = account else { throw SyncError.accountNotFound }
        guard let token = account.token else { throw SyncError.noToken }
        do {
            try await dependencies.createAIChats().delete(chatIds: chatIds, token: token)
        } catch {
            throw handleUnauthenticatedAndMap(error, policy: .doNotLogoutOn401)
        }
    }

    public func patchAIChats(updates: [AIChatUpdate]) async throws {
        guard let account = account else { throw SyncError.accountNotFound }
        guard let token = account.token else { throw SyncError.noToken }
        do {
            try await dependencies.createAIChats().patch(updates: updates, token: token)
        } catch {
            throw handleUnauthenticatedAndMap(error, policy: .doNotLogoutOn401)
        }
    }

    public func setAIChatHistoryEnabled(_ enabled: Bool) {
        try? dependencies.keyValueStore.set(enabled, forKey: Constants.aiChatHistoryEnabledKey)
    }

    public var isAIChatHistoryEnabled: Bool {
        (try? dependencies.keyValueStore.object(forKey: Constants.aiChatHistoryEnabledKey) as? Bool) == true
    }

    public func disconnect() async throws {
        guard let deviceId = try dependencies.secureStore.account()?.deviceId else {
            throw SyncError.accountNotFound
        }
        do {
            try await disconnect(deviceId: deviceId)
            try removeAccount(reason: .userTurnedOffSync)
        } catch {
            throw handleUnauthenticatedAndMap(error)
        }
    }

    public func disconnect(deviceId: String) async throws {
        guard let token = try dependencies.secureStore.account()?.token else {
            throw SyncError.noToken
        }
        do {
            try await dependencies.account.logout(deviceId: deviceId, token: token)
        } catch {
            throw handleUnauthenticatedAndMap(error)
        }
    }

    public func fetchDevices() async throws -> [RegisteredDevice] {
        guard let account = try dependencies.secureStore.account() else {
            throw SyncError.accountNotFound
        }

        let wasDeviceInfoMigrationRunning = deviceInfoUpdateState.isMigrationRunning
        do {
            let result = try await dependencies.account.fetchDevicesForAccount(account)
            fireUnifiedReadObservations(result.unifiedReadObservations, for: account)
            if result.needsCurrentDeviceInfoRepair && !wasDeviceInfoMigrationRunning {
                scheduleCurrentDeviceInfoRepair(for: account)
            }
            return result.devices
        } catch {
            throw handleUnauthenticatedAndMap(error)
        }
    }

    public func updateDeviceName(_ name: String) async throws -> [RegisteredDevice] {
        let isUnifiedWriteEnabled = dependencies.syncFeatureFlags.canWriteUnifiedDeviceList()
        deviceInfoUpdateState.setRenameInProgress(true)
        defer { deviceInfoUpdateState.setRenameInProgress(false) }
        await deviceInfoUpdateState.cancelAllAndWait()

        guard let account = try dependencies.secureStore.account() else {
            throw SyncError.accountNotFound
        }

        do {
            return try await deviceInfoMigrationCoordinator.renameCurrentDevice(to: name,
                                                                                 for: account,
                                                                                 mode: isUnifiedWriteEnabled ? .unified : .legacyOnly)
        } catch {
            throw handleUnauthenticatedAndMap(error)
        }
    }

    public func deleteAccount() async throws {
        guard let account = try dependencies.secureStore.account() else {
            throw SyncError.accountNotFound
        }

        do {
            try await dependencies.account.deleteAccount(account)
            try removeAccount(reason: .userDeletedAccount)
        } catch {
            throw handleUnauthenticatedAndMap(error)
        }
    }

    public var serverEnvironment: ServerEnvironment {
        if dependencies.endpoints.baseURL == ServerEnvironment.production.baseURL {
            return .production
        }
        return .development
    }

    public func updateServerEnvironment(_ serverEnvironment: ServerEnvironment) {
        try? removeAccount(reason: .serverEnvironmentUpdated)
        dependencies.updateServerEnvironment(serverEnvironment)
        authState = .initializing
        initializeIfNeeded()
    }

    public func ensureAccountInfoKeyForDebug() async throws -> Int {
        guard let account = try dependencies.secureStore.account() else {
            throw SyncError.accountNotFound
        }

        return try await dependencies.scopedAccess.ensureAccountInfoProtectedKeys(for: account).count
    }

    public func validateAccountInfoKeyForDebug() async throws -> (refreshedKeyID: String, reloadedKeyID: String, keySizeInBits: Int) {
        guard let account = try dependencies.secureStore.account() else {
            throw SyncError.accountNotFound
        }

        let refreshedKey = try await dependencies.accountInfoKeys.refreshKey(for: account)
        let reloadedKey = try await dependencies.accountInfoKeys.loadKey(for: account)
        return (refreshedKeyID: refreshedKey.kid,
                reloadedKeyID: reloadedKey.kid,
                keySizeInBits: SecKeyGetBlockSize(reloadedKey.publicKey) * 8)
    }

    public func fetchDevicesForDebug() async throws -> [RegisteredDeviceDebugInfo] {
        guard let account = try dependencies.secureStore.account() else {
            throw SyncError.accountNotFound
        }

        do {
            return try await dependencies.account.fetchDevicesForAccount(account).debugDevices
        } catch {
            throw handleUnauthenticatedAndMap(error)
        }
    }

    public func auditLogDumpForDebug() async throws -> String {
        guard let account = try dependencies.secureStore.account() else {
            throw SyncError.accountNotFound
        }

        do {
            let page = try await dependencies.account.fetchAuditLog(for: account, cursor: nil, limit: nil)
            var description = ""
            dump(page, to: &description)
            return description
        } catch {
            throw handleUnauthenticatedAndMap(error)
        }
    }

    public func auditLogAccountIdentifier() throws -> String? {
        try dependencies.secureStore.account()?.userId
    }

    @MainActor
    public func makeAuditLogReader() throws -> any SyncAuditLogReading {
        guard let account = try dependencies.secureStore.account() else { throw SyncError.accountNotFound }
        return SyncAuditLogReader(account: account) { [self] readerAccount, cursor in
            guard try isCurrent(readerAccount) else {
                throw CancellationError()
            }
            do {
                let page = try await dependencies.account.fetchAuditLog(for: readerAccount,
                                                                        cursor: cursor.map(AuditLogCursor.before),
                                                                        limit: Constants.auditLogPageSize)
                guard try isCurrent(readerAccount) else {
                    throw CancellationError()
                }
                return page
            } catch {
                guard try isCurrent(readerAccount) else {
                    throw CancellationError()
                }
                throw handleUnauthenticatedAndMap(error)
            }
        }
    }

    private func isCurrent(_ account: SyncAccount) throws -> Bool {
        guard let currentAccount = try dependencies.secureStore.account() else { return false }
        return currentAccount.userId == account.userId && currentAccount.deviceId == account.deviceId
    }

    /// The platform schedules notifications for a completed poll before its checkpoint is committed.
    public var loginNotificationHandler: ((SyncLoginNotification) async -> Void)?

    private let pendingActivityDidChange = PassthroughSubject<Void, Never>()

    public var pendingLoginEventsPublisher: AnyPublisher<[SyncLoginEvent], Never> {
        let updates = auditLogPoller?.stateDidChange.eraseToAnyPublisher() ?? Empty().eraseToAnyPublisher()
        return updates.merge(with: authStatePublisher.map { _ in () }, pendingActivityDidChange)
            .prepend(())
            .receive(on: DispatchQueue.main)
            .map { [weak self] _ in
                do { return try self?.pendingLoginEvents() ?? [] } catch {
                    Logger.sync.error("Failed to load pending Sync activity: \(String(reflecting: error), privacy: .private)")
                    return []
                }
            }
            .eraseToAnyPublisher()
    }

    public func pendingLoginEvents() throws -> [SyncLoginEvent] {
        guard dependencies.syncFeatureFlags.isLoginAuditLogEnabled(), let account else { return [] }
        let events = try auditLogPoller?.pendingEvents(for: account.userId) ?? []
        guard !events.isEmpty, let reviewedThrough = try auditLogReviewState(for: account.userId)?.reviewedThrough else {
            return events
        }
        return events.filter { $0.occurredAt > reviewedThrough }
    }

    public func dismissPendingLoginEvents(withIDs ids: Set<String>) throws {
        guard let account else { return }
        try auditLogPoller?.dismissEvents(withIDs: ids, for: account.userId)
    }

    public func auditLogReviewState(for accountID: String) throws -> SyncAuditLogReviewState? {
        guard let data = try dependencies.keyValueStore.object(forKey: auditLogReviewStateKey(for: accountID)) as? Data else {
            return nil
        }
        do {
            return try JSONDecoder().decode(SyncAuditLogReviewState.self, from: data)
        } catch is DecodingError {
            // Leave the record in place until a successful activity fetch can seed a new baseline.
            Logger.sync.error("Saved Device Activity review state could not be decoded")
            return nil
        }
    }

    public func setAuditLogReviewState(_ reviewState: SyncAuditLogReviewState, for accountID: String) throws {
        let didSave = try auditLogReviewStateLock.withLock {
            if let current = try auditLogReviewState(for: accountID), !canAdvanceReviewState(from: current, to: reviewState) {
                return false
            }
            try persistAuditLogReviewState(reviewState, for: accountID)
            return true
        }
        if didSave, let date = reviewState.reviewedThrough {
            do {
                try auditLogPoller?.removeReviewedEvents(through: date, for: accountID)
            } catch {
                // The review date was saved, so refresh pending activity even if pruning failed.
                pendingActivityDidChange.send()
                throw error
            }
        }
    }

    public func resetAuditLogReviewStateForDebug(to date: Date) throws {
        guard let account = try dependencies.secureStore.account() else {
            throw SyncError.accountNotFound
        }
        // Debug resets intentionally bypass the forward-only rule used by setAuditLogReviewState.
        try auditLogReviewStateLock.withLock {
            try persistAuditLogReviewState(SyncAuditLogReviewState(reviewedThrough: date, isInitialized: true), for: account.userId)
        }
    }

    private func persistAuditLogReviewState(_ reviewState: SyncAuditLogReviewState, for accountID: String) throws {
        let data = try JSONEncoder().encode(reviewState)
        try dependencies.keyValueStore.set(data, forKey: auditLogReviewStateKey(for: accountID))
    }

    private func canAdvanceReviewState(from current: SyncAuditLogReviewState, to next: SyncAuditLogReviewState) -> Bool {
        guard current.isInitialized else { return true }
        guard next.isInitialized else { return false }
        guard let currentDate = current.reviewedThrough else { return true }
        guard let nextDate = next.reviewedThrough else { return false }
        return nextDate >= currentDate
    }

    private func auditLogReviewStateKey(for accountID: String) -> String {
        "\(Constants.auditLogReviewStateKey).\(accountID)"
    }

    public func isDeviceInfoMigrationCompleteForDebug() throws -> Bool {
        guard let account = try dependencies.secureStore.account() else {
            throw SyncError.accountNotFound
        }
        return deviceInfoMigrationCoordinator.hasCompletedMigration(for: account)
    }

    public func resetDeviceInfoMigrationForDebug() {
        deviceInfoMigrationCoordinator.reset()
    }

    public func prepareThirdPartyRecoveryCode(purpose: String) async throws -> String {
        guard let account else {
            throw SyncError.accountNotFound
        }

        do {
            let scopedPassword = try await ensureThirdPartyScopedPassword(for: account, purpose: purpose)
            let code = try makeThirdPartyRecoveryCode(account: account, scopedPassword: scopedPassword)
            cacheScopedPasswordInBackground(scopedPassword)
            return code
        } catch {
            throw handleUnauthenticatedAndMap(error)
        }
    }

    public func upgradeThirdPartyAccountToDefaultCredential(_ recoveryCode: String,
                                                            deviceName: String,
                                                            deviceType: String) async throws -> [RegisteredDevice] {
        guard try dependencies.secureStore.account() == nil else {
            throw SyncError.accountAlreadyExists
        }

        do {
            let upgradeCoordinator = dependencies.createThirdPartyAccountUpgradeCoordinator()
            let result = try await upgradeCoordinator.upgradeThirdPartyAccountToDefaultCredential(recoveryCode,
                                                                                                 deviceName: deviceName,
                                                                                                 deviceType: deviceType)
            do {
                try updateAccount(result.account)
            } catch {
                Logger.sync.error("3party account upgrade failed to persist the native account: \(String(reflecting: error), privacy: .public)")
                throw ThirdPartyAccountUpgradeError.localStorageFailed
            }
            cacheScopedPasswordInBackground(result.scopedPassword)
            updateProtectedKeysCache(with: result.protectedKeys)
            scheduleDeviceInfoMigration(for: result.account)
            scheduler.requestSyncImmediately()
            return result.devices
        } catch {
            throw handleUnauthenticatedAndMap(error)
        }
    }

    public func encryptAndBase64Encode(_ values: [String]) throws -> [String] {
        let key = try dependencies.crypter.fetchSecretKey()
        return try values.map { try dependencies.crypter.encryptAndBase64Encode($0, using: key) }
    }

    public func base64DecodeAndDecrypt(_ values: [String]) throws -> [String] {
        let key = try dependencies.crypter.fetchSecretKey()
        return try values.map { try dependencies.crypter.base64DecodeAndDecrypt($0, using: key) }
    }

    public func encryptAndBase64URLEncode(_ values: [String]) throws -> [String] {
        let key = try dependencies.crypter.fetchSecretKey()
        return try values.map { value in
            guard let plaintextData = Base64URL.decode(value) else {
                throw SyncError.failedToEncryptValue("Unable to decode Base64URL value")
            }
            return try Base64URL.encode(dependencies.crypter.encrypt(plaintextData, using: key))
        }
    }

    public func base64URLDecodeAndDecrypt(_ values: [String]) throws -> [String] {
        let key = try dependencies.crypter.fetchSecretKey()
        return try values.map { value in
            guard !value.isEmpty else { return "" }

            guard let encryptedData = Base64URL.decode(value) else {
                throw SyncError.failedToDecryptValue("Unable to decode Base64URL value")
            }

            return try Base64URL.encode(dependencies.crypter.decryptData(encryptedData, using: key))
        }
    }

    // MARK: -

    var dependencies: SyncDependencies

    init(dataProvidersSource: DataProvidersSource, dependencies: SyncDependencies) {
        self.dataProvidersSource = dataProvidersSource
        self.dependencies = dependencies
        self.deviceInfoMigrationCoordinator = dependencies.createDeviceInfoMigrationCoordinator()

        auditLogPoller = makeAuditLogPoller()

        featureFlagsCancellable = Publishers.Merge(
            self.dependencies.privacyConfigurationManager.updatesPublisher,
            self.dependencies.privacyConfigurationManager.internalUserDecider.isInternalUserPublisher.map { _ in () })
        .compactMap { [weak self] in
            self?.dependencies.privacyConfigurationManager.privacyConfig
        }
        .prepend(dependencies.privacyConfigurationManager.privacyConfig)
        .map(SyncFeatureFlags.init)
        .handleEvents(receiveOutput: { [weak self] flags in
            guard let self else { return }
            if !flags.contains(.dataSyncing) || !self.dependencies.syncFeatureFlags.isLoginAuditLogEnabled() {
                self.auditLogPoller?.cancel()
            }
            self.pendingActivityDidChange.send()
        })
        .removeDuplicates()
        .receive(on: DispatchQueue.main)
        .assign(to: \.featureFlags, onWeaklyHeld: self)
    }

    // swiftlint:disable:next cyclomatic_complexity
    public func initializeIfNeeded() {
        guard authState == .initializing else { return }

        // Obtain or migrate sync status
        var syncEnabled: Bool
        do {
            syncEnabled = try dependencies.keyValueStore.object(forKey: Constants.syncEnabledKey) != nil

            if !syncEnabled {
                // Try to migrate
                let legacyFlag = dependencies.legacyKeyValueStore.object(forKey: Constants.syncEnabledKey)
                if legacyFlag != nil {
                    do {
                        try dependencies.keyValueStore.set(true, forKey: Constants.syncEnabledKey)
                        dependencies.legacyKeyValueStore.removeObject(forKey: Constants.syncEnabledKey)
                        syncEnabled = true
                        dependencies.errorEvents.fire(.migratedToFileStore)
                    } catch {
                        // Failed migration, retry later.
                        dependencies.errorEvents.fire(.failedToMigrateToFileStore, error: error)
                        return
                    }
                }
            }
        } catch {
            // No access to kvs, retry later.
            dependencies.errorEvents.fire(.failedToInitFileStore, error: error)
            return
        }

        // Proceed to initialization - if needed
        guard syncEnabled else {
            let shouldPreserveAccount = dependencies.shouldPreserveAccountWhenSyncDisabled()

            let storedAccount: SyncAccount?
            let accountReadFailed: Bool
            do {
                storedAccount = try dependencies.secureStore.account()
                accountReadFailed = false
            } catch {
                dependencies.errorEvents.fire(.failedToLoadAccount, error: error)
                storedAccount = nil
                accountReadFailed = true
            }

            // Feature-flagged in the app layer (FeatureFlag.syncAutoRestore) and only true when the user opted in.
            if shouldPreserveAccount, storedAccount != nil || accountReadFailed {
                authState = .inactive
                return
            }

            var didRemoveAccount = false
            do {
                deviceInfoUpdateState.cancelAll()
                try dependencies.secureStore.removeAccount()
                clearAccountInfoKeyCache(for: storedAccount)
                deviceInfoMigrationCoordinator.reset()
                clearAuditLogState(for: storedAccount)
                didRemoveAccount = true
            } catch {
                dependencies.errorEvents.fire(.failedToRemoveAccount, error: error)
            }

            if didRemoveAccount, storedAccount != nil {
                dependencies.errorEvents.fire(.accountRemoved(.syncEnabledNotSetOnKeyValueStore))
            }
            authState = .inactive
            return
        }

        let account: SyncAccount?
        do {
            account = try dependencies.secureStore.account()
        } catch {
            dependencies.errorEvents.fire(.failedToLoadAccount, error: error)
            return
        }

        authState = account?.state ?? .inactive

        guard let account else {
            do {
                try removeAccount(reason: .notFoundInSecureStorage)
            } catch {
                dependencies.errorEvents.fire(.failedToRemoveAccount, error: error)
            }
            return
        }

        do {
            try updateAccount(account)
            if isSyncEngineReady {
                scheduleDeviceInfoMigration(for: account)
            }
        } catch {
            dependencies.errorEvents.fire(.failedToSetupEngine, error: error)
        }
    }

    public func enableSyncFromPreservedAccount() async throws {
        if isSyncEngineReady {
            return
        }

        try dependencies.keyValueStore.set(true, forKey: Constants.syncEnabledKey)
        authState = .initializing
        initializeIfNeeded()

        guard isSyncEngineReady else {
            authState = .inactive
            do {
                try dependencies.keyValueStore.removeObject(forKey: Constants.syncEnabledKey)
            } catch {
                try? dependencies.keyValueStore.set(nil, forKey: Constants.syncEnabledKey)
            }
            throw SyncError.failedToSetupEngine
        }

        dependencies.scheduler.notifyAppLifecycleEvent()
    }

    public func removePreservedSyncAccount() throws {
        guard authState == .inactive else { return }
        guard try dependencies.secureStore.account() != nil else { return }
        try removeAccount(reason: .userStartedFreshSetup)
    }

    private func makeAuditLogPoller() -> AuditLogPoller {
        AuditLogPoller(
            accountManager: dependencies.account,
            keyValueStore: dependencies.keyValueStore,
            canPoll: { [weak self] account in
                try self?.canPollAuditLog(for: account) ?? false
            },
            initializeReviewState: { [weak self] page, account in
                try self?.initializeAuditLogReviewState(from: page, for: account)
            },
            onError: { error in
                Logger.sync.error("Failed to poll the audit log: \(String(reflecting: error), privacy: .private)")
            },
            notify: { [weak self] notification in
                await self?.loginNotificationHandler?(notification)
            },
            reviewedThrough: { [weak self] accountID in
                try self?.auditLogReviewState(for: accountID)?.reviewedThrough
            }
        )
    }

    public func pollAuditLog() async throws -> Bool {
        guard let account = try accountForAuditLogPolling() else { return false }
        return try await auditLogPoller?.pollIfNeeded(for: account) ?? false
    }

    public func isAuditLogPollingAvailable(forAccountID accountID: String? = nil) throws -> Bool {
        guard let account = try accountForAuditLogPolling() else { return false }
        return accountID == nil || account.userId == accountID
    }

    private func accountForAuditLogPolling() throws -> SyncAccount? {
        // Read current flags rather than waiting for their published main-queue update.
        guard SyncFeatureFlags(privacyConfig: dependencies.privacyConfigurationManager.privacyConfig).contains(.dataSyncing),
              dependencies.syncFeatureFlags.isLoginAuditLogEnabled(),
              try dependencies.keyValueStore.object(forKey: Constants.syncEnabledKey) != nil,
              let account = try dependencies.secureStore.account(),
              account.state == .active || account.state == .addingNewDevice,
              let token = account.token, !token.isEmpty else { return nil }
        return account
    }

    private func canPollAuditLog(for polledAccount: SyncAccount) throws -> Bool {
        guard let account = try accountForAuditLogPolling() else { return false }
        return account.userId == polledAccount.userId && account.deviceId == polledAccount.deviceId
            && account.token == polledAccount.token && account.primaryKey == polledAccount.primaryKey
            && account.secretKey == polledAccount.secretKey
    }

    private func startForegroundAuditLogPolling() {
        // Scheduler-triggered polls follow normal Sync suspension; explicit audit polls remain independent.
        guard syncQueue?.isSuspended == false else { return }
        do {
            guard let account = try accountForAuditLogPolling(),
                  let task = auditLogPoller?.startPolling(for: account) else { return }
            foregroundAuditLogTask = task
        } catch {
            Logger.sync.error("Failed to start audit-log polling: \(String(reflecting: error), privacy: .private)")
        }
    }

    private func initializeAuditLogReviewState(from page: AuditLogPage, for account: SyncAccount) throws {
        guard try auditLogReviewState(for: account.userId) == nil else { return }
        let newestDate = page.entries.compactMap { result -> Date? in
            guard case .decoded(let event) = result else { return nil }
            return event.occurredAt
        }.max()
        // Let Device Activity find the baseline when there may be readable entries on an older page.
        guard newestDate != nil || page.before == nil else { return }
        try setAuditLogReviewState(SyncAuditLogReviewState(reviewedThrough: newestDate, isInitialized: true), for: account.userId)
    }

    private func updateAccount(_ account: SyncAccount) throws {
        guard account.state != .initializing else {
            assertionFailure("Sync has not been initialized properly")
            return
        }

        guard account.state != .inactive else {
            try removeAccount(reason: .authStateInactive)
            return
        }

        assert(syncQueue == nil, "Sync queue is not nil")

        let providers = dataProvidersSource?.makeDataProviders() ?? []
        let syncQueue = SyncQueue(dataProviders: providers, dependencies: dependencies)
        try syncQueue.prepareDataModelsForSync(needsRemoteDataFetch: account.state == .addingNewDevice)

        do {
            if try dependencies.keyValueStore.object(forKey: Constants.keychainAttrMigratedKey) == nil {
                // Remove account from keychain to re-apply attribute changes
                try dependencies.secureStore.removeAccount()

                try dependencies.keyValueStore.set(true, forKey: Constants.keychainAttrMigratedKey)
            }
        } catch {}

        if account.state != .active {
            let activatedAccount = account.updatingState(.active)
            try dependencies.secureStore.persistAccount(activatedAccount)
        } else {
            try dependencies.secureStore.persistAccount(account)
        }

        // By this point kvs is already loaded into memory, so no read error should occur
        if (try? dependencies.keyValueStore.object(forKey: Constants.syncEnabledKey)) == nil {
            try dependencies.keyValueStore.set(true, forKey: Constants.syncEnabledKey)
        }

        authState = account.state

        syncQueueCancellable = syncQueue.isSyncInProgressPublisher
            .handleEvents(receiveCancel: { [weak self] in
                self?.isSyncInProgress = false
            })
            .sink(receiveCompletion: { [weak self] _ in
                self?.isSyncInProgress = false
            }, receiveValue: { [weak self] isInProgress in
                self?.isSyncInProgress = isInProgress
            })

        syncDidFinishCancellable = syncQueue.syncDidFinishPublisher
            .sink(receiveValue: { [weak self] result in
                var syncError: SyncOperationError?
                if case let .failure(error) = result {
                    syncError = error as? SyncOperationError
                }
                self?.syncDailyStats.onSyncFinished(with: syncError)
            })

        startSyncCancellable = dependencies.scheduler.startSyncPublisher
            .sink { [weak self] in
                self?.syncQueue?.startSync()
                self?.startForegroundAuditLogPolling()
            }

        syncQueueRequestErrorCancellable = syncQueue.syncHTTPRequestErrorPublisher
            .sink { [weak self] error in
                // Safe to try? because the error is reported to Sync Data Provider anyway
                // and here we only care about logging the user out of Sync
                _ = self?.handleUnauthenticatedAndMap(error)
            }

        cancelSyncCancellable = dependencies.scheduler.cancelSyncPublisher
            .sink { [weak self] in
                self?.syncQueue?.cancelOngoingSyncAndSuspendQueue()
                self?.foregroundAuditLogTask?.cancel()
            }

        resumeSyncCancellable = dependencies.scheduler.resumeSyncPublisher
            .sink { [weak self] in
                self?.syncQueue?.resumeQueue()
            }

        isDataSyncingFeatureFlagEnabledCancellable = featureFlagsPublisher.prepend(featureFlags).map { $0.contains(.dataSyncing) }
            .assign(to: \.isDataSyncingFeatureFlagEnabled, onWeaklyHeld: syncQueue)

        dependencies.scheduler.isEnabled = true
        self.syncQueue = syncQueue
        setCustomOperations(customOperations)
    }

    private func updateProtectedKeysCache(with keys: [ProtectedKey]?) {
        guard let keys, !keys.isEmpty else {
            return
        }

        let keysToCache = keys.preservingCachedWrappersForMatchingKeys(cachedProtectedKeys())
        guard let encodedKeys = try? JSONEncoder.snakeCaseKeys.encode(keysToCache) else {
            try? dependencies.secureStore.removeProtectedKeys()
            return
        }

        try? dependencies.secureStore.persistProtectedKeys(encodedKeys)
    }

    private func cachedProtectedKeys() -> [ProtectedKey] {
        guard let data = try? dependencies.secureStore.protectedKeys() else {
            return []
        }
        return (try? JSONDecoder.snakeCaseKeys.decode([ProtectedKey].self, from: data)) ?? []
    }

    private func scheduleDeviceInfoMigration(for account: SyncAccount) {
        let deviceInfoMigrationCoordinator = deviceInfoMigrationCoordinator
        deviceInfoUpdateState.scheduleMigration {
            await deviceInfoMigrationCoordinator.migrateCurrentDeviceIfNeeded(for: account)
        }
    }

    private func fireUnifiedReadObservations(_ observations: [UnifiedDeviceListReadObservation],
                                             for account: SyncAccount) {
        let canReportOwnRowFallback = dependencies.syncFeatureFlags.canWriteUnifiedDeviceList()
        var missingDeviceInfoReason: UnifiedDeviceListEvent.DeviceInfoFallbackReason?
        for observation in observations {
            switch observation {
            case .event(let event):
                if !canReportOwnRowFallback {
                    switch event {
                    case .ownRowResolvedLegacy, .ownRowResolvedPlaceholder:
                        continue
                    default:
                        break
                    }
                }
                dependencies.unifiedDeviceListEvents.fire(event)
            case .ownRowMissingDeviceInfo(.legacy):
                guard canReportOwnRowFallback else {
                    continue
                }
                let reason = missingDeviceInfoReason ?? ownRowMissingDeviceInfoReason(for: account)
                missingDeviceInfoReason = reason
                dependencies.unifiedDeviceListEvents.fire(.ownRowResolvedLegacy(reason))
            case .ownRowMissingDeviceInfo(.placeholder):
                guard canReportOwnRowFallback else {
                    continue
                }
                let reason = missingDeviceInfoReason ?? ownRowMissingDeviceInfoReason(for: account)
                missingDeviceInfoReason = reason
                dependencies.unifiedDeviceListEvents.fire(.ownRowResolvedPlaceholder(reason))
            }
        }
    }

    private func ownRowMissingDeviceInfoReason(for account: SyncAccount) -> UnifiedDeviceListEvent.DeviceInfoFallbackReason {
        deviceInfoMigrationCoordinator.hasCompletedMigration(for: account) ? .blobAbsent : .notPublishedYet
    }

    private func scheduleCurrentDeviceInfoRepair(for account: SyncAccount) {
        guard dependencies.syncFeatureFlags.canWriteUnifiedDeviceList(),
              let currentAccount = try? dependencies.secureStore.account(),
              currentAccount.userId == account.userId,
              currentAccount.deviceId == account.deviceId else {
            return
        }
        let deviceInfoMigrationCoordinator = deviceInfoMigrationCoordinator
        deviceInfoUpdateState.scheduleRepair {
            Logger.sync.debug("Sync-UnifiedDevices: scheduling current device_info repair")
            await deviceInfoMigrationCoordinator.repairCurrentDeviceInfo(for: currentAccount)
        }
    }

    private func persistRecoveredThirdPartyScopedPasswordIfAvailable(from accessCredentials: [AccessCredential]?, account: SyncAccount) {
        guard dependencies.syncFeatureFlags.isScopedAccessCredentialsEnabled() else {
            return
        }

        do {
            if let scopedPassword = try recoverScopedPasswordIfAvailable(from: accessCredentials, account: account) {
                try dependencies.secureStore.persistScopedPassword(scopedPassword)
            }
        } catch {
            if containsThirdPartyAccessCredential(accessCredentials) {
                try? dependencies.secureStore.removeScopedPassword()
            }
            Logger.sync.error("Failed to recover scoped password during native account flow: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func recoverScopedPasswordIfAvailable(from accessCredentials: [AccessCredential]?, account: SyncAccount) throws -> Data? {
        try dependencies.scopedAccess.recoverScopedPassword(from: accessCredentials, primaryKey: account.primaryKey,
                                                            userID: account.userId)
    }

    private func containsThirdPartyAccessCredential(_ accessCredentials: [AccessCredential]?) -> Bool {
        accessCredentials?.contains { $0.id == SyncCode.RecoveryKeyV2.thirdPartyCredentialId } == true
    }

    private func ensureThirdPartyScopedPassword(for account: SyncAccount, purpose: String) async throws -> Data {
        let result = try await dependencies.scopedAccess.ensureThirdPartyScopedPassword(for: account,
                                                                                       purpose: purpose,
                                                                                       cachedScopedPassword: dependencies.secureStore.scopedPassword)
        updateProtectedKeysCache(with: result.protectedKeysToCache)
        return result.scopedPassword
    }

    private func makeThirdPartyRecoveryCode(account: SyncAccount, scopedPassword: Data) throws -> String {
        guard let code = dependencies.scopedAccess.makeRecoveryCode(for: account, scopedPassword: scopedPassword) else {
            throw SyncError.invalidRecoveryKey
        }
        return code
    }

    private func cacheScopedPasswordInBackground(_ scopedPassword: Data) {
        let secureStore = dependencies.secureStore
        Task {
            try? secureStore.persistScopedPassword(scopedPassword)
        }
    }

    public func setCustomOperations(_ operations: [any SyncCustomOperation]) {
        customOperations = operations
        syncQueue?.customOperations = operations
    }

    private var isSyncEngineReady: Bool {
        (authState == .active || authState == .addingNewDevice)
        && syncQueue != nil
        && dependencies.scheduler.isEnabled
    }

    private func removeAccount(reason: SyncError.AccountRemovedReason) throws {
        let account = try? dependencies.secureStore.account()
        deviceInfoUpdateState.cancelAll()
        auditLogPoller?.cancel()
        dependencies.scheduler.isEnabled = false
        startSyncCancellable?.cancel()
        syncQueueCancellable?.cancel()
        isDataSyncingFeatureFlagEnabledCancellable?.cancel()
        let providersToDeregister: [DataProviding]
        if let activeProviders = syncQueue?.dataProviders, !activeProviders.isEmpty {
            providersToDeregister = activeProviders
        } else {
            providersToDeregister = dataProvidersSource?.makeDataProviders() ?? []
        }
        try providersToDeregister.forEach { try $0.deregisterFeature() }
        syncQueue = nil
        authState = .inactive
        try dependencies.secureStore.removeAccount()
        clearAccountInfoKeyCache(for: account)
        deviceInfoMigrationCoordinator.reset()
        defer { clearAuditLogState(for: account) }
        try dependencies.keyValueStore.set(nil, forKey: Constants.syncEnabledKey)
        dependencies.errorEvents.fire(.accountRemoved(reason))
    }

    private func clearAuditLogState(for account: SyncAccount?) {
        guard let account else { return }
        do {
            try auditLogPoller?.clearState(for: account.userId)
        } catch {
            Logger.sync.error("Failed to clear the audit log cursor during account removal: \(String(reflecting: error), privacy: .private)")
        }
        do {
            try auditLogReviewStateLock.withLock {
                try dependencies.keyValueStore.removeObject(forKey: auditLogReviewStateKey(for: account.userId))
            }
        } catch {
            Logger.sync.error("Failed to clear Device Activity review state during account removal: \(String(reflecting: error), privacy: .private)")
        }
    }

    private func clearAccountInfoKeyCache(for account: SyncAccount?) {
        guard let account else {
            return
        }
        let accountInfoKeys = dependencies.accountInfoKeys
        Task {
            await accountInfoKeys.clearCachedKey(for: account)
        }
    }

    private func handleUnauthenticatedAndMap(_ error: Error,
                                             policy: UnauthenticatedHandling = .logoutOn401) -> Error {
        guard let syncError = error as? SyncError,
              case .unexpectedStatusCode(let statusCode) = syncError,
              statusCode == 401 else {
            return error
        }

        if policy == .doNotLogoutOn401 {
            return error
        }

        do {
            try removeAccount(reason: .unauthenticatedRequest)
            throw SyncError.unauthenticatedWhileLoggedIn
        } catch {
            Logger.sync.error("Failed to delete account upon unauthenticated server response: \(error.localizedDescription, privacy: .public)")
            if error is SyncError {
                return error
            } else {
                return SyncError.failedToRemoveAccount
            }
        }
    }

    private var foregroundAuditLogTask: Task<Void, Error>?
    private var startSyncCancellable: AnyCancellable?
    private var cancelSyncCancellable: AnyCancellable?
    private var resumeSyncCancellable: AnyCancellable?
    private var featureFlagsCancellable: AnyCancellable?
    private var isDataSyncingFeatureFlagEnabledCancellable: AnyCancellable?

    private var syncQueue: SyncQueue?
    private var syncQueueCancellable: AnyCancellable?
    private var syncDidFinishCancellable: AnyCancellable?
    private var syncQueueRequestErrorCancellable: AnyCancellable?
    private let deviceInfoUpdateState = DeviceInfoUpdateState()
    private var auditLogPoller: AuditLogPoller?
    // Serialize the screen and poller's review-date comparisons and writes.
    private let auditLogReviewStateLock = NSLock()

    deinit {
        auditLogPoller?.cancel()
    }
}

final class DeviceInfoUpdateState {

    // Background tasks clear their handles on completion; synchronize that cleanup with scheduling and cancellation
    private struct TrackedTask {
        let id: UUID
        let task: Task<Void, Never>
    }

    private let lock = NSLock()
    private var migrationTask: TrackedTask?
    private var repairTask: TrackedTask?
    private var isRenameInProgress = false
    private var hasAttemptedRepair = false

    var isMigrationRunning: Bool {
        lock.withLock { migrationTask != nil }
    }

    func setRenameInProgress(_ isInProgress: Bool) {
        lock.withLock {
            isRenameInProgress = isInProgress
        }
    }

    func scheduleMigration(_ operation: @escaping () async -> Void) {
        lock.withLock {
            guard migrationTask == nil else {
                return
            }

            let taskID = UUID()
            migrationTask = TrackedTask(id: taskID, task: Task { [weak self] in
                await operation()
                self?.clearMigrationTask(withID: taskID)
            })
        }
    }

    func scheduleRepair(_ operation: @escaping () async -> Void) {
        lock.withLock {
            guard migrationTask == nil,
                  repairTask == nil,
                  !isRenameInProgress,
                  !hasAttemptedRepair else {
                return
            }

            // A failed best-effort repair retries on a later app launch, not on every device-list poll.
            hasAttemptedRepair = true
            let taskID = UUID()
            repairTask = TrackedTask(id: taskID, task: Task { [weak self] in
                await operation()
                self?.clearRepairTask(withID: taskID)
            })
        }
    }

    func cancelAll() {
        let tasks = lock.withLock { () -> (migration: TrackedTask?, repair: TrackedTask?) in
            let tasks = (migration: migrationTask, repair: repairTask)
            migrationTask = nil
            repairTask = nil
            hasAttemptedRepair = false
            return tasks
        }
        tasks.migration?.task.cancel()
        tasks.repair?.task.cancel()
    }

    func cancelAllAndWait() async {
        let tasks = lock.withLock { (migration: migrationTask, repair: repairTask) }
        tasks.migration?.task.cancel()
        tasks.repair?.task.cancel()
        await tasks.migration?.task.value
        await tasks.repair?.task.value

        lock.withLock {
            hasAttemptedRepair = false
        }
    }

    private func clearMigrationTask(withID taskID: UUID) {
        lock.withLock {
            guard migrationTask?.id == taskID else {
                return
            }
            migrationTask = nil
        }
    }

    private func clearRepairTask(withID taskID: UUID) {
        lock.withLock {
            guard repairTask?.id == taskID else {
                return
            }
            repairTask = nil
        }
    }
}

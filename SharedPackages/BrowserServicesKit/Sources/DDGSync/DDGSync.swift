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

import BrowserServicesKit
import Combine
import Common
import DDGSyncCrypto
import Persistence
import Foundation
import os.log

public class DDGSync: DDGSyncing {

    public static let bundle = Bundle.module

    @Published public private(set) var featureFlags: SyncFeatureFlags = .all
    public var featureFlagsPublisher: AnyPublisher<SyncFeatureFlags, Never> {
        $featureFlags.eraseToAnyPublisher()
    }

    enum Constants {
        public static let syncEnabledKey = "com.duckduckgo.sync.enabled"
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

    public var scheduler: Scheduling {
        dependencies.scheduler
    }

    public let syncDailyStats = SyncDailyStats()

    @Published public var isSyncInProgress: Bool = false

    public var isSyncInProgressPublisher: AnyPublisher<Bool, Never> {
        $isSyncInProgress.dropFirst().removeDuplicates().eraseToAnyPublisher()
    }

    public weak var dataProvidersSource: DataProvidersSource?

    /// This is the constructor intended for use by app clients.
    public convenience init(dataProvidersSource: DataProvidersSource,
                            errorEvents: EventMapping<SyncError>,
                            privacyConfigurationManager: PrivacyConfigurationManaging,
                            keyValueStore: ThrowingKeyValueStoring,
                            environment: ServerEnvironment = .production) {
        let dependencies = ProductionDependencies(
            serverEnvironment: environment,
            privacyConfigurationManager: privacyConfigurationManager,
            keyValueStore: keyValueStore,
            errorEvents: errorEvents
        )
        self.init(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
    }

    public func createAccount(deviceName: String, deviceType: String) async throws {
        guard try dependencies.secureStore.account() == nil else {
            throw SyncError.accountAlreadyExists
        }

        let account = try await dependencies.account.createAccount(deviceName: deviceName, deviceType: deviceType)
        try updateAccount(account)
        scheduler.requestSyncImmediately()
    }

    public func login(_ recoveryKey: SyncCode.RecoveryKey, deviceName: String, deviceType: String) async throws -> [RegisteredDevice] {
        guard try dependencies.secureStore.account() == nil else {
            throw SyncError.accountAlreadyExists
        }

        let result = try await dependencies.account.login(recoveryKey, deviceName: deviceName, deviceType: deviceType)
        try updateAccount(result.account)
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

        do {
            return try await dependencies.account.fetchDevicesForAccount(account)
        } catch {
            throw handleUnauthenticatedAndMap(error)
        }
    }

    public func updateDeviceName(_ name: String) async throws -> [RegisteredDevice] {
        guard let account = try dependencies.secureStore.account() else {
            throw SyncError.accountNotFound
        }

        do {
            let result = try await dependencies.account.refreshToken(account, deviceName: name)
            try dependencies.secureStore.persistAccount(result.account)
            return result.devices
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

    // MARK: -

    var dependencies: SyncDependencies

    init(dataProvidersSource: DataProvidersSource, dependencies: SyncDependencies) {
        self.dataProvidersSource = dataProvidersSource
        self.dependencies = dependencies

        featureFlagsCancellable = Publishers.Merge(
            self.dependencies.privacyConfigurationManager.updatesPublisher,
            self.dependencies.privacyConfigurationManager.internalUserDecider.isInternalUserPublisher.map { _ in () })
        .compactMap { [weak self] in
            self?.dependencies.privacyConfigurationManager.privacyConfig
        }
        .prepend(dependencies.privacyConfigurationManager.privacyConfig)
        .map(SyncFeatureFlags.init)
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
            if account != nil {
                dependencies.errorEvents.fire(.accountRemoved(.syncEnabledNotSetOnKeyValueStore))
            }
            try? dependencies.secureStore.removeAccount()
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
        } catch {
            dependencies.errorEvents.fire(.failedToSetupEngine, error: error)
        }
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
            }

        resumeSyncCancellable = dependencies.scheduler.resumeSyncPublisher
            .sink { [weak self] in
                self?.syncQueue?.resumeQueue()
            }

        isDataSyncingFeatureFlagEnabledCancellable = featureFlagsPublisher.prepend(featureFlags).map { $0.contains(.dataSyncing) }
            .assign(to: \.isDataSyncingFeatureFlagEnabled, onWeaklyHeld: syncQueue)

        dependencies.scheduler.isEnabled = true
        self.syncQueue = syncQueue
    }

    private func removeAccount(reason: SyncError.AccountRemovedReason) throws {
        dependencies.scheduler.isEnabled = false
        startSyncCancellable?.cancel()
        syncQueueCancellable?.cancel()
        isDataSyncingFeatureFlagEnabledCancellable?.cancel()
        try syncQueue?.dataProviders.forEach { try $0.deregisterFeature() }
        syncQueue = nil
        authState = .inactive
        try dependencies.secureStore.removeAccount()
        try dependencies.keyValueStore.set(nil, forKey: Constants.syncEnabledKey)
        dependencies.errorEvents.fire(.accountRemoved(reason))
    }

    private func handleUnauthenticatedAndMap(_ error: Error) -> Error {
        guard let syncError = error as? SyncError,
              case .unexpectedStatusCode(let statusCode) = syncError,
              statusCode == 401 else {
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

    private var startSyncCancellable: AnyCancellable?
    private var cancelSyncCancellable: AnyCancellable?
    private var resumeSyncCancellable: AnyCancellable?
    private var featureFlagsCancellable: AnyCancellable?
    private var isDataSyncingFeatureFlagEnabledCancellable: AnyCancellable?

    private var syncQueue: SyncQueue?
    private var syncQueueCancellable: AnyCancellable?
    private var syncDidFinishCancellable: AnyCancellable?
    private var syncQueueRequestErrorCancellable: AnyCancellable?
}

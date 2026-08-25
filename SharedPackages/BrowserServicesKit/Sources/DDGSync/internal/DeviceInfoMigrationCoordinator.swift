//
//  DeviceInfoMigrationCoordinator.swift
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
import Common
import os.log
import Persistence

enum DeviceInfoRenameMode: Equatable {
    case unified
    /// Updates legacy fields and omits `info`, clearing stale server-side `device_info`.
    case legacyOnly
}

protocol DeviceInfoMigrationCoordinating {
    func migrateCurrentDeviceIfNeeded(for account: SyncAccount) async
    func repairCurrentDeviceInfo(for account: SyncAccount) async
    func renameCurrentDevice(to name: String, for account: SyncAccount, mode: DeviceInfoRenameMode) async throws -> [RegisteredDevice]
    func hasCompletedMigration(for account: SyncAccount) -> Bool
    func reset()
}

private struct DeviceInfoMigrationIdentity: Hashable {
    let userID: String
    let deviceID: String

    init(account: SyncAccount) {
        userID = account.userId
        deviceID = account.deviceId
    }

    var persistedValue: String {
        "\(userID):\(deviceID)"
    }
}

enum DeviceInfoMigrationError: Error, Equatable {
    case missingAccountInfoProtectedKey
    case encryptedDeviceInfoTooLarge
}

struct DeviceInfoMigrationCoordinator: DeviceInfoMigrationCoordinating {

    private enum DeviceInfoWrite {
        case firstWrite
        case repair

        var successEvent: UnifiedDeviceListEvent {
            switch self {
            case .firstWrite: return .ownRowDeviceInfoFirstWriteSuccess
            case .repair: return .ownRowDeviceInfoRepairSuccess
            }
        }

        func failureEvent(_ reason: UnifiedDeviceListEvent.DeviceInfoWriteFailureReason) -> UnifiedDeviceListEvent {
            switch self {
            case .firstWrite: return .ownRowDeviceInfoFirstWriteFailed(reason)
            case .repair: return .ownRowDeviceInfoRepairFailed(reason)
            }
        }
    }

    private enum Key: String {
        case completedAccountDevice = "com.duckduckgo.sync.device-info-migration.completed-account-device"
    }

    private let accountManager: AccountManaging
    private let scopedAccess: ScopedAccessCredentialManaging
    private let updateBuilder: DeviceInfoUpdateBuilder
    private let secureStore: SecureStoring
    private let keyValueStore: ThrowingKeyValueStoring
    private let unifiedDeviceListEvents: EventMapping<UnifiedDeviceListEvent>
    private let canWriteUnifiedDeviceList: () -> Bool

    init(accountManager: AccountManaging,
         scopedAccess: ScopedAccessCredentialManaging,
         crypter: CryptingInternal,
         deviceInfoCodec: DeviceInfoCoding = DeviceInfoCodec(),
         secureStore: SecureStoring,
         keyValueStore: ThrowingKeyValueStoring,
         unifiedDeviceListEvents: EventMapping<UnifiedDeviceListEvent>? = nil,
         canWriteUnifiedDeviceList: @escaping () -> Bool) {
        self.accountManager = accountManager
        self.scopedAccess = scopedAccess
        self.updateBuilder = DeviceInfoUpdateBuilder(crypter: crypter, deviceInfoCodec: deviceInfoCodec)
        self.secureStore = secureStore
        self.keyValueStore = keyValueStore
        self.unifiedDeviceListEvents = unifiedDeviceListEvents ?? EventMapping { _, _, _, onComplete in
            onComplete(nil)
        }
        self.canWriteUnifiedDeviceList = canWriteUnifiedDeviceList
    }

    func migrateCurrentDeviceIfNeeded(for account: SyncAccount) async {
        let identity = DeviceInfoMigrationIdentity(account: account)
        guard canWriteUnifiedDeviceList(),
              !hasCompletedMigration(for: account),
              currentAccount(matching: identity) != nil,
              !Task.isCancelled else {
            return
        }
        Logger.sync.debug("Sync-UnifiedDevices: migrating current device_info")
        await updateCurrentDeviceInfo(for: account, identity: identity, write: .firstWrite)
    }

    func repairCurrentDeviceInfo(for account: SyncAccount) async {
        let identity = DeviceInfoMigrationIdentity(account: account)
        guard canWriteUnifiedDeviceList(),
              currentAccount(matching: identity) != nil,
              !Task.isCancelled else {
            return
        }
        await updateCurrentDeviceInfo(for: account, identity: identity, write: .repair)
    }

    func renameCurrentDevice(to name: String, for account: SyncAccount, mode: DeviceInfoRenameMode) async throws -> [RegisteredDevice] {
        let identity = DeviceInfoMigrationIdentity(account: account)
        guard let currentAccount = currentAccount(matching: identity),
              isCurrentAccountSnapshot(account, identity: identity) else {
            throw SyncError.accountNotFound
        }

        let update: UpdateDevices.Update
        switch mode {
        case .unified:
            let protectedKey = try await prepareAccountInfoProtectedKey(for: currentAccount,
                                                                         identity: identity)
            guard !Task.isCancelled,
                  isCurrentAccountSnapshot(currentAccount, identity: identity) else {
                throw CancellationError()
            }
            do {
                update = try updateBuilder.makeUpdate(deviceID: currentAccount.deviceId,
                                                       deviceName: name,
                                                       deviceType: currentAccount.deviceType,
                                                       primaryKey: currentAccount.primaryKey,
                                                       protectedKey: protectedKey)
            } catch {
                unifiedDeviceListEvents.fire(
                    .ownRowDeviceInfoUpdateFailed(.encryptFailed),
                    error: error)
                throw error
            }
        case .legacyOnly:
            update = try updateBuilder.makeUpdateWithoutUnifiedInfo(deviceID: currentAccount.deviceId,
                                                                     deviceName: name,
                                                                     deviceType: currentAccount.deviceType,
                                                                     primaryKey: currentAccount.primaryKey)
        }

        let devices = try await applyRename(update,
                                            newDeviceName: name,
                                            account: currentAccount,
                                            identity: identity,
                                            unifiedWrite: mode == .unified)
        switch mode {
        case .unified:
            markMigrationComplete(for: currentAccount)
            Logger.sync.debug("Sync-UnifiedDevices: current device rename complete")
        case .legacyOnly:
            Logger.sync.debug("Sync-UnifiedDevices: current device rename PATCH without unified info complete")
        }
        return devices
    }

    private func updateCurrentDeviceInfo(for account: SyncAccount,
                                         identity: DeviceInfoMigrationIdentity,
                                         write: DeviceInfoWrite) async {
        let protectedKey: ProtectedKey
        do {
            protectedKey = try await prepareAccountInfoProtectedKey(for: account,
                                                                    identity: identity)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else {
                return
            }
            logDeviceInfoUpdateFailure(error)
            return
        }

        guard !Task.isCancelled,
              let currentAccount = currentAccount(matching: identity) else {
            return
        }
        let update: UpdateDevices.Update
        do {
            update = try updateBuilder.makeUpdate(deviceID: currentAccount.deviceId,
                                                   deviceName: currentAccount.deviceName,
                                                   deviceType: currentAccount.deviceType,
                                                   primaryKey: currentAccount.primaryKey,
                                                   protectedKey: protectedKey)
        } catch {
            guard !Task.isCancelled else {
                return
            }
            unifiedDeviceListEvents.fire(
                write.failureEvent(.encryptFailed),
                error: error)
            logDeviceInfoUpdateFailure(error)
            return
        }
        guard !Task.isCancelled,
              isCurrentAccountSnapshot(currentAccount, identity: identity) else {
            return
        }
        do {
            _ = try await accountManager.updateDevice(update, for: currentAccount)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else {
                return
            }
            unifiedDeviceListEvents.fire(
                write.failureEvent(UnifiedDeviceListTelemetry.deviceInfoRequestFailureReason(for: error)),
                error: error)
            logDeviceInfoUpdateFailure(error)
            return
        }

        guard !Task.isCancelled,
              isCurrentAccountSnapshot(currentAccount, identity: identity) else {
            return
        }
        markMigrationComplete(for: currentAccount)
        unifiedDeviceListEvents.fire(write.successEvent)
        Logger.sync.debug("Sync-UnifiedDevices: current device_info update complete")
    }

    private func applyRename(_ update: UpdateDevices.Update,
                             newDeviceName: String,
                             account: SyncAccount,
                             identity: DeviceInfoMigrationIdentity,
                             unifiedWrite: Bool) async throws -> [RegisteredDevice] {
        guard !Task.isCancelled,
              isCurrentAccountSnapshot(account, identity: identity) else {
            throw CancellationError()
        }

        let devices: [RegisteredDevice]
        do {
            devices = try await accountManager.updateDevice(update, for: account)
        } catch {
            if unifiedWrite, !(error is CancellationError) {
                unifiedDeviceListEvents.fire(
                    .ownRowDeviceInfoUpdateFailed(UnifiedDeviceListTelemetry.deviceInfoRequestFailureReason(for: error)),
                    error: error)
            }
            throw error
        }
        guard !Task.isCancelled,
              isCurrentAccountSnapshot(account, identity: identity) else {
            throw CancellationError()
        }

        do {
            try secureStore.persistAccount(account.updatingDeviceName(newDeviceName))
        } catch {
            if unifiedWrite {
                unifiedDeviceListEvents.fire(.ownRowDeviceInfoUpdateFailed(.persistFailed), error: error)
            }
            throw error
        }
        if unifiedWrite {
            unifiedDeviceListEvents.fire(.ownRowDeviceInfoUpdateSuccess)
        }
        return devices
    }

    private func logDeviceInfoUpdateFailure(_ error: Error) {
        let errorType = String(describing: Swift.type(of: error))
        Logger.sync.error("Sync-UnifiedDevices: failed to update current device_info: \(errorType)")
    }

    func reset() {
        try? keyValueStore.removeObject(forKey: Key.completedAccountDevice.rawValue)
    }

    func hasCompletedMigration(for account: SyncAccount) -> Bool {
        guard let storedValue = try? keyValueStore.object(forKey: Key.completedAccountDevice.rawValue) else {
            return false
        }
        return storedValue as? String == DeviceInfoMigrationIdentity(account: account).persistedValue
    }

    private func markMigrationComplete(for account: SyncAccount) {
        try? keyValueStore.set(DeviceInfoMigrationIdentity(account: account).persistedValue,
                               forKey: Key.completedAccountDevice.rawValue)
    }

    private func prepareAccountInfoProtectedKey(for account: SyncAccount,
                                                identity: DeviceInfoMigrationIdentity) async throws -> ProtectedKey {
        let protectedKeys = try await scopedAccess.ensureAccountInfoProtectedKeys(for: account)
        guard let protectedKey = protectedKeys.first(where: { $0.purpose == ProtectedKeyPurpose.accountInfo }) else {
            throw DeviceInfoMigrationError.missingAccountInfoProtectedKey
        }
        guard !Task.isCancelled,
              currentAccount(matching: identity) != nil else {
            throw CancellationError()
        }
        return protectedKey
    }

    private func currentAccount(matching identity: DeviceInfoMigrationIdentity) -> SyncAccount? {
        do {
            guard let currentAccount = try secureStore.account() else {
                return nil
            }
            guard DeviceInfoMigrationIdentity(account: currentAccount) == identity else {
                return nil
            }
            return currentAccount
        } catch {
            return nil
        }
    }

    private func isCurrentAccountSnapshot(_ account: SyncAccount,
                                          identity: DeviceInfoMigrationIdentity) -> Bool {
        guard let currentAccount = currentAccount(matching: identity) else {
            return false
        }
        return currentAccount.deviceName == account.deviceName
            && currentAccount.deviceType == account.deviceType
            && currentAccount.primaryKey == account.primaryKey
            && currentAccount.secretKey == account.secretKey
            && currentAccount.token == account.token
    }
}

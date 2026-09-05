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
import os.log
import Persistence

protocol DeviceInfoMigrationCoordinating {
    func migrateCurrentDeviceIfNeeded(for account: SyncAccount) async
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

    private enum Key: String {
        case completedAccountDevice = "com.duckduckgo.sync.device-info-migration.completed-account-device"
    }

    private let accountManager: AccountManaging
    private let scopedAccess: ScopedAccessCredentialManaging
    private let crypter: CryptingInternal
    private let deviceInfoCodec: DeviceInfoCoding
    private let secureStore: SecureStoring
    private let keyValueStore: ThrowingKeyValueStoring
    private let canWriteUnifiedDeviceList: () -> Bool

    init(accountManager: AccountManaging,
         scopedAccess: ScopedAccessCredentialManaging,
         crypter: CryptingInternal,
         deviceInfoCodec: DeviceInfoCoding = DeviceInfoCodec(),
         secureStore: SecureStoring,
         keyValueStore: ThrowingKeyValueStoring,
         canWriteUnifiedDeviceList: @escaping () -> Bool) {
        self.accountManager = accountManager
        self.scopedAccess = scopedAccess
        self.crypter = crypter
        self.deviceInfoCodec = deviceInfoCodec
        self.secureStore = secureStore
        self.keyValueStore = keyValueStore
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

        do {
            let protectedKey = try await prepareAccountInfoProtectedKey(for: account,
                                                                        identity: identity)
            guard !Task.isCancelled,
                  let currentAccount = currentAccount(matching: identity) else {
                return
            }

            let encryptedDeviceInfo = try deviceInfoCodec.encrypt(
                DeviceInfo(name: currentAccount.deviceName, type: currentAccount.deviceType),
                using: protectedKey)
            guard encryptedDeviceInfo.utf8.count <= DeviceInfo.maximumEncryptedLength else {
                throw DeviceInfoMigrationError.encryptedDeviceInfoTooLarge
            }

            let update = UpdateDevices.Update(
                id: currentAccount.deviceId,
                name: try crypter.encryptAndBase64Encode(currentAccount.deviceName, using: currentAccount.primaryKey),
                type: try crypter.encryptAndBase64Encode(currentAccount.deviceType, using: currentAccount.primaryKey),
                info: encryptedDeviceInfo)
            guard !Task.isCancelled,
                  isCurrentAccountSnapshot(currentAccount, identity: identity) else {
                return
            }
            _ = try await accountManager.updateDevice(update, for: currentAccount)

            guard !Task.isCancelled,
                  isCurrentAccountSnapshot(currentAccount, identity: identity) else {
                return
            }
            markMigrationComplete(for: currentAccount)
            Logger.sync.debug("Sync-UnifiedDevices: current device_info update complete")
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else {
                return
            }
            let errorType = String(describing: type(of: error))
            Logger.sync.error("Sync-UnifiedDevices: failed to migrate current device_info: \(errorType)")
        }
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

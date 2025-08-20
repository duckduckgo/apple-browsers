//
//  ProductionDependencies.swift
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
import Common
import Foundation
import Persistence

struct ProductionDependencies: SyncDependencies {

    let fileStorageUrl: URL
    let endpoints: Endpoints
    let account: AccountManaging
    let api: RemoteAPIRequestCreating
    let payloadCompressor: SyncPayloadCompressing
    var keyValueStore: ThrowingKeyValueStoring
    var legacyKeyValueStore: KeyValueStoring
    let secureStore: SecureStoring
    var crypter: CryptingInternal
    let scheduler: SchedulingInternal
    let privacyConfigurationManager: PrivacyConfigurationManaging
    let errorEvents: EventMapping<SyncError>

    init(
        serverEnvironment: ServerEnvironment,
        privacyConfigurationManager: PrivacyConfigurationManaging,
        keyValueStore: ThrowingKeyValueStoring,
        errorEvents: EventMapping<SyncError>
    ) {
        self.init(fileStorageUrl: FileManager.default.applicationSupportDirectoryForComponent(named: "Sync"),
                  serverEnvironment: serverEnvironment,
                  keyValueStore: keyValueStore,
                  legacyKeyValueStore: UserDefaults(),
                  secureStore: SecureStorage(),
                  privacyConfigurationManager: privacyConfigurationManager,
                  errorEvents: errorEvents)
    }

    init(
        fileStorageUrl: URL,
        serverEnvironment: ServerEnvironment,
        keyValueStore: ThrowingKeyValueStoring,
        legacyKeyValueStore: KeyValueStoring,
        secureStore: SecureStoring,
        privacyConfigurationManager: PrivacyConfigurationManaging,
        errorEvents: EventMapping<SyncError>
    ) {
        self.fileStorageUrl = fileStorageUrl
        self.endpoints = Endpoints(serverEnvironment: serverEnvironment)
        self.keyValueStore = keyValueStore
        self.legacyKeyValueStore = legacyKeyValueStore
        self.secureStore = secureStore
        self.privacyConfigurationManager = privacyConfigurationManager
        self.errorEvents = errorEvents

        api = RemoteAPIRequestCreator()
        payloadCompressor = SyncGzipPayloadCompressor()

        crypter = Crypter(secureStore: secureStore)
        account = AccountManager(endpoints: endpoints, api: api, crypter: crypter)
        scheduler = SyncScheduler()
    }

    func createRemoteConnector() throws -> RemoteConnecting {
        return try RemoteConnector(crypter: crypter, api: api, endpoints: endpoints)
    }

    func createRemoteKeyExchanger() throws -> any RemoteKeyExchanging {
        return try RemoteKeyExchanger(
            crypter: crypter,
            api: api,
            endpoints: endpoints
        )
    }

    func createRemoteExchangeRecoverer(_ exchangeInfo: ExchangeInfo) throws -> any RemoteExchangeRecovering {
        return try RemoteExchangeRecoverer(
            crypter: crypter,
            api: api,
            endpoints: endpoints,
            exchangeInfo: exchangeInfo
        )
    }

    func createRecoveryKeyTransmitter() throws -> RecoveryKeyTransmitting {
        return RecoveryKeyTransmitter(endpoints: endpoints, api: api, storage: secureStore, crypter: crypter)
    }

    func createExchangePublicKeyTransmitter() throws -> any ExchangePublicKeyTransmitting {
        return ExchangePublicKeyTransmitter(endpoints: endpoints, api: api, crypter: crypter)
    }

    func createExchangeRecoveryKeyTransmitter(exchangeMessage: ExchangeMessage) throws -> any ExchangeRecoveryKeyTransmitting {
        return ExchangeRecoveryKeyTransmitter(endpoints: endpoints, api: api, crypter: crypter, storage: secureStore, exchangeMessage: exchangeMessage)
    }

    func updateServerEnvironment(_ serverEnvironment: ServerEnvironment) {
        endpoints.updateBaseURL(for: serverEnvironment)
    }
}

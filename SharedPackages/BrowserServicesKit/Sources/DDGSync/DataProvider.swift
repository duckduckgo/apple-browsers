//
//  DataProvider.swift
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

/**
 * Defines sync feature, i.e. type of synced data.
 */
public struct Feature: Hashable {
    public var name: String

    public init(name: String) {
        self.name = name
    }
}

/**
 * Defines sync feature's setup state.
 */
public enum FeatureSetupState: String {
    /// This value denotes a state where a feature requires "initial sync" to be performed,
    /// i.e. fetching remote data and merging it with local, with data deduplication as needed.
    case needsRemoteDataFetch
    /// Default value where feature is included in regular sync
    case readyToSync
}

/**
 * Describes a data model that is supported by Sync.
 *
 * Any data model that is passed to Sync is supposed to be encrypted as needed.
 */
public struct Syncable {
    public var payload: [String: Any]

    public init(jsonObject: [String: Any]) {
        payload = jsonObject
    }

    public var isDeleted: Bool {
        payload["deleted"] != nil
    }
}

/**
 * Describes data source for objects to be synced with the server.
 *
 * This protocol should not be implemented from scratch. Instead, clients should
 * inherit `DataProvider` abstract class which implements this protocol partially,
 * only leaving syncable data management functions to be implemented:
 *   - `prepareForFirstSync`
 *   - `fetchChangedObjects`
 *   - `handleInitialSyncResponse`
 *   - `handleSyncResponse`
 */
public protocol DataProviding: AnyObject {

    /**
     * Feature that is supported by this provider.
     *
     * This is passed to `GET /{types_csv}`.
     */
    var feature: Feature { get }

    /**
     * Describes feature's sync setup state and defines the behavior of a feature in Sync Operation.
     *
     * Regular sync flow consists of sending local changes (if exists) to the server, receiving server
     * response with remote changes, and applying these changes locally.
     *
     * Sometimes a syncable model has to go through a setup phase (a.k.a. initial sync) before it's ready
     * to be synced the regular way. Initial sync starts with remote data being fetched from the server
     * and merged with local data (applying deduplication as needed). After that, the model is ready
     * for regular sync. This happens for:
     *   - newly added features – when a new app release adds a new syncable model,
     *   - all features – when adding a device to an existing Sync account.
     */
    var featureSyncSetupState: FeatureSetupState { get }

    /**
     * Returns a boolean value stating whether a feature is locally registered with Sync.
     *
     * All features are registered when Sync is turned on. Additionally, when the app is updated
     * to a new version that adds a new syncable model, feature representing that model is
     * also automatically registered. Newly registered features may require special handling
     * (a.k.a. initial sync).
     */
    var isFeatureRegistered: Bool { get }

    /**
     * Registers feature with Sync using provided `setupState`.
     *
     * This function stores feature metadata in Sync Metadata Store and enables feature to be synced.
     */
    func registerFeature(withState setupState: FeatureSetupState) throws

    /**
     * Deregisters feature.
     *
     * This function removes feature metadata from Sync Metadata Store, effectively disabling Sync
     * for the feature. Deregistered feature needs to be registered again in order to be included
     * in Sync (which will cause initial sync with data merging and deduplication).
     */
    func deregisterFeature() throws

    /**
     * Time of last successful sync of a given feature.
     *
     * Note that it's a String as this is the server timestamp and should not be treated as date
     * and as such used in comparing timestamps. It's merely an identifier of the last sync operation.
     */
    var lastSyncTimestamp: String? { get }

    /**
     * Local timestamp of the last successful sync of a given feature.
     *
     * This timestamp should only be used to identify objects that failed to sync
     * (see `fetchDescriptionsForObjectsThatFailedValidation`) as it is not immune to
     * changing date/time on client devices.
     */
    var lastSyncLocalTimestamp: Date? { get set }

    /**
     * Update server and local timestamps of the last successful sync of a given feature.
     */
    func updateSyncTimestamps(server: String?, local: Date?)

    /**
     * Prepare data models for first sync.
     *
     * This function is called before the initial sync is performed.
     */
    func prepareForFirstSync() throws

    /**
     * Find objects that failed local validation and weren't synced with the server.
     *
     * Instead of returning entire syncable objects, this function is supposed to return
     * a property of the object that would hint the user which object it is. The strings
     * returned by this function should be safe to be displayed verbatim in the app UI.
     */
    func fetchDescriptionsForObjectsThatFailedValidation() throws -> [String]

    /**
     * Return objects that have changed since last sync, or all objects in case of the initial sync.
     */
    func fetchChangedObjects(encryptedUsing crypter: Crypting) async throws -> [Syncable]

    /**
     * Apply initial sync operation response.
     *
     * - Parameter received: Objects that were received from the server.
     * - Parameter clientTimestamp: Local timestamp of the sync network request.
     * - Parameter serverTimestamp: Server timestamp describing server data validity.
     * - Parameter crypter: Crypter object to decrypt received data.
     */
    func handleInitialSyncResponse(received: [Syncable], clientTimestamp: Date, serverTimestamp: String?, crypter: Crypting) async throws

    /**
     * Apply sync operation result.
     *
     * - Parameter sent: Objects that were sent to the server.
     * - Parameter received: Objects that were received from the server.
     * - Parameter clientTimestamp: Local timestamp of the sync network request.
     * - Parameter serverTimestamp: Server timestamp describing server data validity.
     * - Parameter crypter: Crypter object to decrypt sent and received data.
     */
    func handleSyncResponse(sent: [Syncable], received: [Syncable], clientTimestamp: Date, serverTimestamp: String?, crypter: Crypting) async throws

    /**
     * Called when sync operation fails.
     *
     * - Parameter error: Sync operation error.
     */
    func handleSyncError(_ error: Error)
}

/**
 * Base class for Sync data providers.
 *
 * Clients should subclass this class to implement data providers for syncable data models.
 * New data provider must implement functions declared as `open`, without calling super.
 */
open class DataProvider: DataProviding {

    public enum SyncResult: Equatable {
        case noData
        case someNewData
        case newData(modifiedIds: Set<String>, deletedIds: Set<String>)

        public var hasNewData: Bool {
            switch self {
            case .noData:
                return false
            case .someNewData, .newData:
                return true
            }
        }

        public var modifiedIds: Set<String> {
            guard case .newData(let modifiedIds, _) = self else {
                return []
            }
            return modifiedIds
        }

        public var deletedIds: Set<String> {
            guard case .newData(_, let deletedIds) = self else {
                return []
            }
            return deletedIds
        }
    }

    public let feature: Feature
    public var syncDidUpdateData: () -> Void
    public var syncDidFinish: () -> Void
    public let syncErrorPublisher: AnyPublisher<Error, Never>

    public var isFeatureRegistered: Bool {
        metadataStore.isFeatureRegistered(named: feature.name)
    }

    public func registerFeature(withState setupState: FeatureSetupState) throws {
        try metadataStore.registerFeature(named: feature.name, setupState: setupState)
    }

    public func deregisterFeature() throws {
        try metadataStore.deregisterFeature(named: feature.name)
    }

    public var featureSyncSetupState: FeatureSetupState {
        metadataStore.state(forFeatureNamed: feature.name)
    }

    public var lastSyncTimestamp: String? {
        metadataStore.timestamp(forFeatureNamed: feature.name)
    }

    public var lastSyncLocalTimestamp: Date? {
        get {
            metadataStore.localTimestamp(forFeatureNamed: feature.name)
        }
        set {
            metadataStore.updateLocalTimestamp(newValue, forFeatureNamed: feature.name)
        }
    }

    public func updateSyncTimestamps(server: String?, local: Date?) {
        metadataStore.update(server, local, .readyToSync, forFeatureNamed: feature.name)
    }

    public init(
        feature: Feature,
        metadataStore: SyncMetadataStore,
        syncDidUpdateData: @escaping () -> Void = {},
        syncDidFinish: @escaping () -> Void = {}
    ) {
        self.feature = feature
        self.metadataStore = metadataStore
        self.syncDidUpdateData = syncDidUpdateData
        self.syncDidFinish = syncDidFinish
        self.syncErrorPublisher = syncErrorSubject.eraseToAnyPublisher()
    }

    open func prepareForFirstSync() throws {
        assertionFailure("\(#function) is not implemented")
    }

    open func fetchDescriptionsForObjectsThatFailedValidation() throws -> [String] {
        assertionFailure("\(#function) is not implemented")
        return []
    }

    open func fetchChangedObjects(encryptedUsing crypter: Crypting) async throws -> [Syncable] {
        assertionFailure("\(#function) is not implemented")
        return []
    }

    open func handleInitialSyncResponse(received: [Syncable], clientTimestamp: Date, serverTimestamp: String?, crypter: Crypting) async throws {
        assertionFailure("\(#function) is not implemented")
    }

    open func handleSyncResponse(sent: [Syncable],
                                 received: [Syncable],
                                 clientTimestamp: Date,
                                 serverTimestamp: String?,
                                 crypter: Crypting) async throws {
        assertionFailure("\(#function) is not implemented")
    }

    public func handleSyncError(_ error: Error) {
        syncErrorSubject.send(error)
    }

    /**
     * Allows to stream errors from additional error publishers (such as publishing errors
     * related to specific data provider's internal logic) to `syncErrorPublisher`.
     */
    public func register(errorPublisher: AnyPublisher<Error, Never>) {
        errorPublisher
            .sink { [weak self] error in
                self?.syncErrorSubject.send(error)
            }
            .store(in: &additionalErrorPublisherCancellables)
    }

    // MARK: - Private

    private let syncErrorSubject = PassthroughSubject<Error, Never>()
    private let metadataStore: SyncMetadataStore
    private var additionalErrorPublisherCancellables = Set<AnyCancellable>()
}

//
//  UpdateManager.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import Common
import Foundation
import Networking
import os
import PixelKit

public protocol MaliciousSiteUpdateManaging {
    #if os(iOS)
    var lastHashPrefixSetUpdateDate: Date { get }
    var lastFilterSetUpdateDate: Date { get }
    func updateData(datasetType: DataManager.StoredDataType.Kind) -> Task<Void, Never>
    #elseif os(macOS)
    func startPeriodicUpdates() -> Task<Void, Error>
    #endif
}

protocol InternalUpdateManaging: MaliciousSiteUpdateManaging {
    func updateData(for key: some MaliciousSiteDataKey) async throws
}

public struct UpdateManager: InternalUpdateManaging {

    private let apiClient: APIClient.Mockable
    private let dataManager: DataManaging
    private let eventMapping: EventMapping<Event>

    public typealias UpdateIntervalProvider = (DataManager.StoredDataType) -> TimeInterval?
    private let updateIntervalProvider: UpdateIntervalProvider
    private let sleeper: Sleeper
    private let updateInfoStorage: MaliciousSiteProtectioUpdateManagerInfoStorage
    private let supportedThreatsProvider: SupportedThreatsProvider

    #if os(iOS)
    public var lastHashPrefixSetUpdateDate: Date {
        updateInfoStorage.lastHashPrefixSetsUpdateDate
    }

    public var lastFilterSetUpdateDate: Date {
        updateInfoStorage.lastFilterSetsUpdateDate
    }
    #endif

    public init(apiEnvironment: APIClientEnvironment, service: APIService, dataManager: DataManager, eventMapping: EventMapping<Event>, updateIntervalProvider: @escaping UpdateIntervalProvider, supportedThreatsProvider: @escaping SupportedThreatsProvider) {
        self.init(apiClient: APIClient(environment: apiEnvironment, service: service), dataManager: dataManager, eventMapping: eventMapping, updateIntervalProvider: updateIntervalProvider, supportedThreatsProvider: supportedThreatsProvider)
    }

    init(apiClient: APIClient.Mockable, dataManager: DataManaging, eventMapping: EventMapping<Event>, sleeper: Sleeper = .default, updateInfoStorage: MaliciousSiteProtectioUpdateManagerInfoStorage = UpdateManagerInfoStore(), updateIntervalProvider: @escaping UpdateIntervalProvider, supportedThreatsProvider: @escaping SupportedThreatsProvider) {
        self.apiClient = apiClient
        self.dataManager = dataManager
        self.eventMapping = eventMapping
        self.updateIntervalProvider = updateIntervalProvider
        self.sleeper = sleeper
        self.updateInfoStorage = updateInfoStorage
        self.supportedThreatsProvider = supportedThreatsProvider
    }

    func updateData<DataKey: MaliciousSiteDataKey>(for key: DataKey) async throws {
        let supportedThreats = supportedThreatsProvider()
        if !supportedThreats.contains(key.threatKind) {
            return
        }

        // load currently stored data set
        let oldRevision = await dataManager.dataSet(for: key).revision

        // get change set from current revision from API
        let changeSet: APIClient.ChangeSetResponse<DataKey.DataSet.Element>
        do {
            let request = DataKey.DataSet.APIRequest(threatKind: key.threatKind, revision: oldRevision)
            changeSet = try await apiClient.load(request)
        } catch {
            Logger.updateManager.error("error fetching \(type(of: key)).\(key.threatKind): \(error)")

            // Fire a Pixel if it fails to load initial datasets
            if case APIRequestV2.Error.urlSession(URLError.notConnectedToInternet) = error, oldRevision == 0 {
                eventMapping.fire(MaliciousSiteProtection.Event.failedToDownloadInitialDataSets(category: key.threatKind, type: key.dataType.kind))
            }

            throw error
        }

        guard !changeSet.isEmpty || changeSet.revision != oldRevision else {
            Logger.updateManager.debug("no changes to \(type(of: key)).\(key.threatKind)")
            return
        }

        // apply and save changes
        do {
            try await dataManager.updateDataSet(with: key, changeSet: changeSet)
            Logger.updateManager.debug("\(type(of: key)).\(key.threatKind) updated from rev.\(oldRevision) to rev.\(changeSet.revision)")
        } catch {
            Logger.updateManager.error("\(type(of: key)).\(key.threatKind) failed to be saved")
            throw error
        }
    }

    #if os(macOS)
    public func startPeriodicUpdates() -> Task<Void, any Error> {
        Task.detached {
            // run update jobs in background for every data type
            try await withThrowingTaskGroup(of: Never.self) { group in
                let supportedThreats = supportedThreatsProvider()
                let filteredDataTypes = DataManager.StoredDataType.allCases.filter { supportedThreats.contains($0.threatKind) }
                for dataType in filteredDataTypes {
                    // get update interval from provider
                    guard let updateInterval = updateIntervalProvider(dataType) else { continue }
                    guard updateInterval > 0 else {
                        assertionFailure("Update interval for \(dataType) must be positive")
                        continue
                    }

                    group.addTask {
                        // run periodically until the parent task is cancelled
                        try await performPeriodicJob(interval: updateInterval, sleeper: sleeper) {
                            do {
                                try await self.updateData(for: dataType.dataKey)
                            } catch {
                                Logger.updateManager.warning("Failed periodic update for kind: \(dataType.dataKey.threatKind). Error: \(error)")
                            }
                        }
                    }
                }
                for try await _ in group {}
            }
        }
    }
    #endif

    #if os(iOS)
    public func updateData(datasetType: DataManager.StoredDataType.Kind) -> Task<Void, Never> {
        Task.detached {
            // run update jobs in background for every data type
            let supportedThreats = supportedThreatsProvider()

            var results: [Bool] = []

            for dataType in DataManager.StoredDataType.dataTypes(for: datasetType, supportedThreats: supportedThreats) {
                do {
                    try await self.updateData(for: dataType.dataKey)
                    results.append(true)
                } catch {
                    Logger.updateManager.error("Failed to update dataset type: \(datasetType.rawValue) for kind: \(dataType.dataKey.threatKind). Error: \(error)")
                    results.append(false)
                }
            }

            // Check that at least one of the dataset type have updated
            let shouldSaveLastUpdateDate = results.contains(true)

            if shouldSaveLastUpdateDate {
                await saveLastUpdateDate(for: datasetType)
            }
        }
    }

    @MainActor
    private func saveLastUpdateDate(for kind: DataManager.StoredDataType.Kind) {
        Logger.updateManager.debug("Saving last update date for kind: \(kind.rawValue)")

        let date = Date()
        switch kind {
        case .hashPrefixSet:
            updateInfoStorage.lastHashPrefixSetsUpdateDate = date
        case .filterSet:
            updateInfoStorage.lastFilterSetsUpdateDate = date
        }
    }
    #endif

}

//
//  DataManager.swift
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
import os

protocol DataManaging {
    func dataSet<DataKey: MaliciousSiteDataKey>(for key: DataKey) async -> DataKey.DataSet
    @discardableResult
    func updateDataSet<DataKey: MaliciousSiteDataKey>(with key: DataKey, changeSet: APIClient.ChangeSetResponse<DataKey.DataSet.Element>) async throws -> Int
    func preloadData(for threatKinds: [ThreatKind]) async
}

public actor DataManager: DataManaging {

    private let embeddedDataProvider: EmbeddedDataProviding?
    private let fileStore: FileStoring

    public typealias FileNameProvider = (DataManager.StoredDataType) -> String
    private nonisolated let fileNameProvider: FileNameProvider
    private let eventMapping: EventMapping<Event>?

    private var store: [StoredDataType: Any] = [:]

    public init(fileStore: FileStoring, embeddedDataProvider: EmbeddedDataProviding?, fileNameProvider: @escaping FileNameProvider, eventMapping: EventMapping<Event>? = nil) {
        self.embeddedDataProvider = embeddedDataProvider
        self.fileStore = fileStore
        self.fileNameProvider = fileNameProvider
        self.eventMapping = eventMapping
    }

    public func preloadData(for threatKinds: [ThreatKind]) {
        for threatKind in threatKinds {
            _=dataSet(for: .filterSet(threatKind: threatKind))
            _=dataSet(for: .hashPrefixes(threatKind: threatKind))
        }
    }

    /// Whether the datasets of `kind` for every one of `threatKinds` are in memory. Doesn't load anything.
    public func isLoaded(_ kind: StoredDataType.Kind, for threatKinds: [ThreatKind]) -> Bool {
        StoredDataType.dataTypes(for: kind, supportedThreats: threatKinds).allSatisfy { store[$0] != nil }
    }

    func dataSet<DataKey: MaliciousSiteDataKey>(for key: DataKey) -> DataKey.DataSet {
        let dataType = key.dataType
        // return cached dataSet if available
        if let data = store[dataType] as? DataKey.DataSet {
            return data
        }

        // read stored dataSet if it‘s newer than the embedded one
        let dataSet: DataKey.DataSet

        let loadStartTime = CFAbsoluteTimeGetCurrent()
        if let storedDataSet = readStoredDataSet(for: key) {
            dataSet = storedDataSet
            fireLoadTimeEvent(for: key, duration: CFAbsoluteTimeGetCurrent() - loadStartTime)
        } else if let embeddedDataProvider {
            // no stored dataSet or the embedded one is newer
            let embeddedRevision = embeddedDataProvider.revision(for: dataType)
            let embeddedItems = embeddedDataProvider.loadDataSet(for: key)
            dataSet = .init(revision: embeddedRevision, items: embeddedItems)
        } else {
            dataSet = DataKey.DataSet(revision: 0, items: [])
        }

        // cache
        store[dataType] = dataSet

        return dataSet
    }

    private func readStoredDataSet<DataKey: MaliciousSiteDataKey>(for key: DataKey) -> DataKey.DataSet? {
        let dataType = key.dataType
        let fileName = fileNameProvider(dataType)
        guard let data = fileStore.read(from: fileName) else { return nil }

        let storedDataSet: DataKey.DataSet
        do {
            storedDataSet = try JSONDecoder().decode(DataKey.DataSet.self, from: data)
        } catch {
            Logger.dataManager.error("Error decoding \(fileName): \(error.localizedDescription)")
            return nil
        }

        // compare to the embedded data revision
        let embeddedDataRevision = embeddedDataProvider?.revision(for: dataType) ?? 0
        guard storedDataSet.revision >= embeddedDataRevision else {
            Logger.dataManager.error("Stored \(fileName) is outdated: revision: \(storedDataSet.revision), embedded revision: \(embeddedDataRevision).")
            return nil
        }

        return storedDataSet
    }

    /// Fires how long reading and decoding a stored dataset file took. Only on iOS, where the event exists.
    private func fireLoadTimeEvent<DataKey: MaliciousSiteDataKey>(for key: DataKey, duration: TimeInterval) {
        #if os(iOS)
        eventMapping?.fire(.dataSetLoadTime(
            category: key.threatKind,
            type: key.dataType.kind,
            bucket: Event.DurationBucketAggregation(seconds: duration)
        ))
        #endif
    }

    @discardableResult
    func updateDataSet<DataKey: MaliciousSiteDataKey>(with key: DataKey, changeSet: APIClient.ChangeSetResponse<DataKey.DataSet.Element>) throws -> Int {
        let dataType = key.dataType
        let fileName = fileNameProvider(dataType)

        // Remove the dataset from `store` before changing it.
        // Datasets are copy-on-write: while `store` also references one, the first change copies all of it,
        // which can crash on low-memory devices (EXC_BREAKPOINT in `_NativeSet.copy`).
        // Safe because no other call on the actor can run in between deleting the dataset and putting it back so no callers can find it missing.
        var dataSet: DataKey.DataSet
        if changeSet.replace {
            // Full replacement: release the old dataset first, so old and new aren't in memory together.
            store[dataType] = nil
            dataSet = DataKey.DataSet(revision: 0, items: [])
        } else {
            // Incremental update: load if needed, then drop `store`'s reference so `apply` changes it in place.
            dataSet = self.dataSet(for: key)
            store[dataType] = nil
        }
        dataSet.apply(changeSet)

        self.store[dataType] = dataSet

        let data: Data
        do {
            data = try JSONEncoder().encode(dataSet)
        } catch {
            Logger.dataManager.error("Error encoding \(fileName): \(error.localizedDescription)")
            assertionFailure("Failed to store data to \(fileName): \(error)")
            throw error
        }

        try fileStore.write(data: data, to: fileName)

        return data.count
    }

}

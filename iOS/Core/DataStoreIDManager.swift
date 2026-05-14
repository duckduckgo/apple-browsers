//
//  DataStoreIDManager.swift
//  DuckDuckGo
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


import WebKit
import Persistence

/// Manages data store identifiers for WebKit data containers.
///
/// This protocol provides two distinct container ID management strategies:
///
/// - **Legacy Container ID (`currentID`)**: Supports existing IDs set in previous app versions for backward compatibility.
///   New IDs are no longer allocated because we've returned to using WebKit's default persistence. This allows us to
///   fireproof data types that lack a direct API for accessing their data (e.g., `localStorage`).
///
/// - **Fire Mode Container ID (`currentFireModeID`)**: Actively allocates and manages a separate container ID used
///   exclusively for Fire Mode browsing sessions. This container is isolated from normal browsing and is invalidated
///   when the user triggers the Fire button to clear their session data.
public protocol DataStoreIDManaging {

    var currentID: UUID? { get }
    func invalidateCurrentID()
    
    var currentFireModeID: UUID { get }
    func invalidateCurrentFireModeID()

    /// IDs of fire mode data stores that have been invalidated but not yet
    /// successfully removed via `WKWebsiteDataStore.remove(forIdentifier:)`.
    var pendingRemovalFireModeIDs: [UUID] { get }
    func removePendingRemovalFireModeID(_ id: UUID)
}

public class DataStoreIDManager: DataStoreIDManaging {

    enum Constants: String {
        case currentWebContainerID = "com.duckduckgo.ios.webcontainer.id"
        case currentFireModeContainerID = "com.duckduckgo.ios.fireMode.webcontainer.id"
        case pendingRemovalFireModeContainerIDs = "com.duckduckgo.ios.fireMode.webcontainer.pendingRemoval"
    }

    public static let shared = DataStoreIDManager()

    private let store: KeyValueStoring
    private let fireModeIDQueue = DispatchQueue(label: "com.duckduckgo.datastoreidmanager.firemode",
                                                qos: .userInitiated)

    init(store: KeyValueStoring = UserDefaults.app) {
        self.store = store
    }
    
    // MARK: - Legacy container ID for backward compatibility

    public var currentID: UUID? {
        guard let uuidString = store.object(forKey: Constants.currentWebContainerID.rawValue) as? String else {
            return nil
        }
        return UUID(uuidString: uuidString)
    }

    public func invalidateCurrentID() {
        store.removeObject(forKey: Constants.currentWebContainerID.rawValue)
    }
    
    // MARK: - Fire Mode Container

    public var currentFireModeID: UUID {
        fireModeIDQueue.sync {
            if let uuidString = store.object(forKey: Constants.currentFireModeContainerID.rawValue) as? String,
               let existingID = UUID(uuidString: uuidString) {
                return existingID
            }
            let newID = UUID()
            store.set(newID.uuidString, forKey: Constants.currentFireModeContainerID.rawValue)
            return newID
        }
    }

    public func invalidateCurrentFireModeID() {
        fireModeIDQueue.sync {
            guard let uuidString = store.object(forKey: Constants.currentFireModeContainerID.rawValue) as? String,
                  let existingID = UUID(uuidString: uuidString) else {
                return
            }
            var pending = storedPendingRemovalIDs()
            if !pending.contains(existingID) {
                pending.append(existingID)
                store.set(pending.map(\.uuidString), forKey: Constants.pendingRemovalFireModeContainerIDs.rawValue)
            }
            store.removeObject(forKey: Constants.currentFireModeContainerID.rawValue)
        }
    }

    // MARK: - Pending Removal

    public var pendingRemovalFireModeIDs: [UUID] {
        fireModeIDQueue.sync {
            storedPendingRemovalIDs()
        }
    }

    public func removePendingRemovalFireModeID(_ id: UUID) {
        fireModeIDQueue.sync {
            var pending = storedPendingRemovalIDs()
            pending.removeAll { $0 == id }
            store.set(pending.map(\.uuidString), forKey: Constants.pendingRemovalFireModeContainerIDs.rawValue)
        }
    }

    private func storedPendingRemovalIDs() -> [UUID] {
        guard let strings = store.object(forKey: Constants.pendingRemovalFireModeContainerIDs.rawValue) as? [String] else {
            return []
        }
        return strings.compactMap { UUID(uuidString: $0) }
    }
}

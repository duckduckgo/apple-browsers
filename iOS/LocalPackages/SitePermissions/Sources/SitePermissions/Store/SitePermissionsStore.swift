//
//  SitePermissionsStore.swift
//  DuckDuckGo
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

import Persistence

enum SitePermissionsStorageKeyNames: String, StorageKeyDescribing {
    case perSitePermissions = "site-permissions-per-site"
    case globalDefaults = "site-permissions-global-defaults"
}

public struct SitePermissionsStoringKeys: StoringKeys {
    let perSitePermissions = StorageKey<[String: [String: String]]>(SitePermissionsStorageKeyNames.perSitePermissions)
    let globalDefaults = StorageKey<[String: String]>(SitePermissionsStorageKeyNames.globalDefaults)

    public init() { }
}

public struct SitePermissionsSnapshot: Equatable, Sendable {
    fileprivate let records: [String: [String: String]]

    public static let empty = SitePermissionsSnapshot(records: [:])

    public var isEmpty: Bool {
        records.isEmpty
    }
}

@MainActor
public final class SitePermissionsStore {

    public typealias SitePermissionRecord = [SitePermissionType: SitePermissionDecision]

    private let storage: any KeyedStoring<SitePermissionsStoringKeys>

    public init(storage: any KeyedStoring<SitePermissionsStoringKeys>) {
        self.storage = storage
    }

    public var storedSites: Set<SitePermissionKey> {
        Set(rawSitePermissions.keys.compactMap(SitePermissionKey.init(storedHost:)))
    }

    public func permissions(for site: SitePermissionKey) -> SitePermissionRecord {
        guard let rawRecord = rawSitePermissions[site.host] else { return [:] }
        return rawRecord.reduce(into: [:]) { record, element in
            guard let type = SitePermissionType(rawValue: element.key),
                  let decision = SitePermissionDecision(rawValue: element.value) else {
                return
            }
            record[type] = decision
        }
    }

    public func decision(for permissionType: SitePermissionType, at site: SitePermissionKey) -> SitePermissionDecision? {
        guard let rawDecision = rawSitePermissions[site.host]?[permissionType.rawValue] else { return nil }
        return SitePermissionDecision(rawValue: rawDecision)
    }

    /// Persists only durable prompt outcomes. Explicit Ask is written by `resetDecision`.
    public func setPersistentDecision(_ decision: SitePermissionDecision,
                                      for permissionType: SitePermissionType,
                                      at site: SitePermissionKey) {
        guard decision != .ask else { return }
        setRawDecision(decision.rawValue, for: permissionType, at: site)
    }

    /// Records an explicit user reset so the site remains visible in permission management.
    public func resetDecision(for permissionType: SitePermissionType, at site: SitePermissionKey) {
        setRawDecision(SitePermissionDecision.ask.rawValue, for: permissionType, at: site)
    }

    public func globalDefault(for permissionType: SitePermissionType) -> GlobalSitePermissionDecision {
        guard let rawDecision = rawGlobalDefaults[permissionType.rawValue] else { return .ask }
        return GlobalSitePermissionDecision(rawValue: rawDecision) ?? .ask
    }

    public func setGlobalDefault(_ decision: GlobalSitePermissionDecision, for permissionType: SitePermissionType) {
        var defaults = rawGlobalDefaults
        guard defaults[permissionType.rawValue] != decision.rawValue else { return }
        defaults[permissionType.rawValue] = decision.rawValue
        storage.globalDefaults = defaults
    }

    public func resetGlobalDefaults() {
        guard storage.globalDefaults != nil else { return }
        storage.removeValue(for: \.globalDefaults)
    }

    @discardableResult
    public func removePermissions(for site: SitePermissionKey) -> SitePermissionsSnapshot {
        removePermissions(for: [site])
    }

    @discardableResult
    public func removePermissions(for sites: Set<SitePermissionKey>) -> SitePermissionsSnapshot {
        guard !sites.isEmpty else { return SitePermissionsSnapshot(records: [:]) }

        let hosts = Set(sites.map(\.host))
        return removeSitePermissions { hosts.contains($0) }
    }

    /// Clears stored site records except hosts selected by `shouldPreserve`.
    @discardableResult
    public func clearSitePermissions(excluding shouldPreserve: (String) -> Bool = { _ in false }) -> SitePermissionsSnapshot {
        removeSitePermissions { !shouldPreserve($0) }
    }

    /// Restores each removed record only when that site has not received a newer record.
    public func restore(_ snapshot: SitePermissionsSnapshot) {
        guard !snapshot.isEmpty else { return }

        var permissions = rawSitePermissions
        var didChange = false
        for (host, record) in snapshot.records where permissions[host] == nil {
            permissions[host] = record
            didChange = true
        }

        guard didChange else { return }
        storeRawSitePermissions(permissions)
    }

    private var rawSitePermissions: [String: [String: String]] {
        storage.perSitePermissions ?? [:]
    }

    private var rawGlobalDefaults: [String: String] {
        storage.globalDefaults ?? [:]
    }

    private func setRawDecision(_ rawDecision: String, for permissionType: SitePermissionType, at site: SitePermissionKey) {
        var permissions = rawSitePermissions
        var record = permissions[site.host] ?? [:]
        guard record[permissionType.rawValue] != rawDecision else { return }
        record[permissionType.rawValue] = rawDecision
        permissions[site.host] = record
        storage.perSitePermissions = permissions
    }

    private func removeSitePermissions(where shouldRemove: (String) -> Bool) -> SitePermissionsSnapshot {
        let permissions = rawSitePermissions
        var removed: [String: [String: String]] = [:]
        var retained: [String: [String: String]] = [:]
        for (host, record) in permissions {
            if shouldRemove(host) {
                removed[host] = record
            } else {
                retained[host] = record
            }
        }
        guard !removed.isEmpty else { return SitePermissionsSnapshot(records: [:]) }

        storeRawSitePermissions(retained)
        return SitePermissionsSnapshot(records: removed)
    }

    private func storeRawSitePermissions(_ permissions: [String: [String: String]]) {
        if permissions.isEmpty {
            storage.removeValue(for: \.perSitePermissions)
        } else {
            storage.perSitePermissions = permissions
        }
    }
}

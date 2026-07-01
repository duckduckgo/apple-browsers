//
//  PermissionManager.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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
import Combine
import Common
import FoundationExtensions
import os.log

/// Read-path interceptor used by `PermissionManager.permission(forDomain:permissionType:)`. When
/// the override returns a non-nil decision, it is returned as the effective permission without
/// touching storage. Use this to force a decision for a known (domain, permission) pair without
/// writing anything to disk — keeps storage representing actual user intent and lets a rollback
/// (override removed) restore the underlying persisted decision cleanly.
protocol PermissionDecisionOverriding: AnyObject {
    func decision(forDomain domain: String, permissionType: PermissionType) -> PersistedPermissionDecision?
}

protocol PermissionManagerProtocol: AnyObject {

    typealias PublishedPermission = (domain: String, permissionType: PermissionType, decision: PersistedPermissionDecision)
    var permissionPublisher: AnyPublisher<PublishedPermission, Never> { get }

    func hasPermissionPersisted(forDomain domain: String, permissionType: PermissionType) -> Bool
    func hasAnyPermissionPersisted(forDomain domain: String) -> Bool
    func persistedPermissionTypes(forDomain domain: String) -> [PermissionType]
    func permission(forDomain domain: String, permissionType: PermissionType) -> PersistedPermissionDecision
    /// Returns the underlying persisted decision, ignoring any active `PermissionDecisionOverriding`.
    /// `nil` when nothing is persisted. Use only for cleanup or migration paths that genuinely need
    /// to know the on-disk state; everything else should call `permission(forDomain:permissionType:)`.
    func persistedDecision(forDomain domain: String, permissionType: PermissionType) -> PersistedPermissionDecision?
    func setPermission(_ decision: PersistedPermissionDecision, forDomain domain: String, permissionType: PermissionType)

    func burnPermissions(except fireproofDomains: FireproofDomains, completion: @escaping @MainActor (Result<Void, Error>) -> Void)
    func burnPermissions(of baseDomains: Set<String>, tld: TLD, completion: @escaping @MainActor (Result<Void, Error>) -> Void)

    /// Removes a specific permission for a domain (clears from storage)
    func removePermission(forDomain domain: String, permissionType: PermissionType)

    var persistedPermissionTypes: Set<PermissionType> { get }
}

final class PermissionManager: PermissionManagerProtocol {

    private let store: PermissionStore
    private var permissions = [String: [PermissionType: StoredPermission]]()
    private let decisionOverride: PermissionDecisionOverriding?

    private let permissionSubject = PassthroughSubject<PublishedPermission, Never>()
    var permissionPublisher: AnyPublisher<PublishedPermission, Never> { permissionSubject.eraseToAnyPublisher() }

    init(store: PermissionStore, decisionOverride: PermissionDecisionOverriding? = nil) {
        self.store = store
        self.decisionOverride = decisionOverride
        loadPermissions()
    }

    private func loadPermissions() {
        do {
            let entities = try store.loadPermissions()
            for entity in entities {
                self.set(entity.permission, forDomain: entity.domain.droppingWwwPrefix(), permissionType: entity.type)
            }
        } catch {
            Logger.general.error("PermissionStore: Failed to load permissions")
        }
    }

    private func set(_ permission: StoredPermission, forDomain domain: String, permissionType: PermissionType) {
        self.permissions[domain, default: [:]][permissionType] = permission
        persistedPermissionTypes.insert(permissionType)
    }

    private(set) var persistedPermissionTypes = Set<PermissionType>()

    func permission(forDomain domain: String, permissionType: PermissionType) -> PersistedPermissionDecision {
        let normalized = domain.droppingWwwPrefix()
        if let override = decisionOverride?.decision(forDomain: normalized, permissionType: permissionType) {
            return override
        }
        return permissions[normalized]?[permissionType]?.decision ?? .ask
    }

    func persistedDecision(forDomain domain: String, permissionType: PermissionType) -> PersistedPermissionDecision? {
        return permissions[domain.droppingWwwPrefix()]?[permissionType]?.decision
    }

    func hasPermissionPersisted(forDomain domain: String, permissionType: PermissionType) -> Bool {
        return permissions[domain.droppingWwwPrefix()]?[permissionType] != nil
    }

    func hasAnyPermissionPersisted(forDomain domain: String) -> Bool {
        guard let domainPermissions = permissions[domain.droppingWwwPrefix()] else { return false }
        return !domainPermissions.isEmpty
    }

    func persistedPermissionTypes(forDomain domain: String) -> [PermissionType] {
        guard let domainPermissions = permissions[domain.droppingWwwPrefix()] else { return [] }
        return Array(domainPermissions.keys)
    }

    func setPermission(_ decision: PersistedPermissionDecision, forDomain domain: String, permissionType: PermissionType) {

        let storedPermission: StoredPermission
        let domain = domain.droppingWwwPrefix()

        // Check if permission is already stored with the same decision
        // Also check hasPermissionPersisted to allow storing .ask explicitly for permission center visibility
        let currentDecision = self.permission(forDomain: domain, permissionType: permissionType)
        let isAlreadyPersisted = hasPermissionPersisted(forDomain: domain, permissionType: permissionType)
        guard currentDecision != decision || !isAlreadyPersisted else { return }

        defer {
            self.permissionSubject.send( (domain, permissionType, decision) )
        }
        if var oldValue = permissions[domain]?[permissionType] {
            oldValue.decision = decision
            storedPermission = oldValue
            store.update(objectWithId: oldValue.id, decision: decision)
        } else {
            do {
                storedPermission = try store.add(domain: domain, permissionType: permissionType, decision: decision)
            } catch {
                Logger.general.error("PermissionStore: Failed to store permission")
                return
            }
        }
        self.set(storedPermission, forDomain: domain, permissionType: permissionType)
    }

    func burnPermissions(except fireproofDomains: FireproofDomains, completion: @escaping @MainActor (Result<Void, Error>) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))

        permissions = permissions.filter {
            fireproofDomains.isFireproof(fireproofDomain: $0.key)
        }
        store.clear(except: permissions.values.reduce(into: [StoredPermission](), {
            $0.append(contentsOf: $1.values)
        }), completionHandler: { error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        })
    }

    func burnPermissions(of baseDomains: Set<String>, tld: TLD, completion: @escaping @MainActor (Result<Void, Error>) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))

        permissions = permissions.filter { permission in
            let baseDomain = tld.eTLDplus1(permission.key) ?? ""
            return !baseDomains.contains(baseDomain)
        }
        store.clear(except: permissions.values.reduce(into: [StoredPermission](), {
            $0.append(contentsOf: $1.values)
        }), completionHandler: { error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        })
    }

    func removePermission(forDomain domain: String, permissionType: PermissionType) {
        let domain = domain.droppingWwwPrefix()

        guard let storedPermission = permissions[domain]?[permissionType] else { return }

        // Remove from in-memory cache
        permissions[domain]?[permissionType] = nil

        // Remove from persistent storage
        store.remove(objectWithId: storedPermission.id)

        // Notify subscribers
        permissionSubject.send((domain, permissionType, .ask))
    }

}

//
//  PermissionManagerMock.swift
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

#if DEBUG

import Combine
import Common
import ConcurrencyExtensions
import Foundation
import FoundationExtensions

final class PermissionManagerMock: PermissionManagerProtocol {

    var permissionSubject = PassthroughSubject<PublishedPermission, Never>()
    var permissionPublisher: AnyPublisher<PublishedPermission, Never> {
        permissionSubject.eraseToAnyPublisher()
    }

    var savedPermissions = [String: [PermissionType: PersistedPermissionDecision]]()
    var setPermissionCalls: [(decision: PersistedPermissionDecision, domain: String, permissionType: PermissionType)] = []

    /// Stands in for `PermissionDecisionOverriding`: when it returns a decision, that decision is the
    /// effective one and `savedPermissions` is left alone. Nil (the default) means no override.
    var decisionOverride: ((String, PermissionType) -> PersistedPermissionDecision?)?

    // MARK: - PermissionManagerDebugging test storage

    var removeAllPermissionsCalled = false

    var persistedPermissionTypes: Set<PermissionType> {
        savedPermissions.reduce(into: Set<PermissionType>()) { partialResult, permissions in
            partialResult.formUnion(permissions.value.keys)
        }
    }

    func hasPermissionPersisted(forDomain domain: String, permissionType: PermissionType) -> Bool {
        savedPermissions[domain.droppingWwwPrefix()]?[permissionType] != nil
    }

    func hasAnyPermissionPersisted(forDomain domain: String) -> Bool {
        guard let domainPermissions = savedPermissions[domain.droppingWwwPrefix()] else { return false }
        return !domainPermissions.isEmpty
    }

    func persistedPermissionTypes(forDomain domain: String) -> [PermissionType] {
        guard let domainPermissions = savedPermissions[domain.droppingWwwPrefix()] else { return [] }
        return Array(domainPermissions.keys)
    }

    func permission(forDomain domain: String, permissionType: PermissionType) -> PersistedPermissionDecision {
        let domain = domain.droppingWwwPrefix()
        if let override = decisionOverride?(domain, permissionType) {
            return override
        }
        return savedPermissions[domain]?[permissionType] ?? .ask
    }

    func persistedDecision(forDomain domain: String, permissionType: PermissionType) -> PersistedPermissionDecision? {
        savedPermissions[domain.droppingWwwPrefix()]?[permissionType]
    }

    func setPermission(_ decision: PersistedPermissionDecision, forDomain domain: String, permissionType: PermissionType) {
        setPermissionCalls.append((decision: decision, domain: domain, permissionType: permissionType))
        savedPermissions[domain.droppingWwwPrefix(), default: [:]][permissionType] = decision
    }

    func removePermission(forDomain domain: String, permissionType: PermissionType) {
        savedPermissions[domain.droppingWwwPrefix(), default: [:]][permissionType] = nil
    }

    var burnPermissionsCalled = false
    func burnPermissions(except fireproofDomains: FireproofDomains, completion: @MainActor @escaping (Result<Void, Error>) -> Void) {
        savedPermissions = savedPermissions.filter { fireproofDomains.isFireproof(fireproofDomain: $0.key) }
        burnPermissionsCalled = true
        MainActor.assumeMainThread {
            completion(.success(()))
        }
    }

    var burnPermissionsOfDomainsCalled = false
    func burnPermissions(of baseDomains: Set<String>, tld: Common.TLD, completion: @MainActor @escaping (Result<Void, Error>) -> Void) {
        burnPermissionsOfDomainsCalled = true
        MainActor.assumeMainThread {
            completion(.success(()))
        }
    }

    // For testing permission requests from PermissionModel
    var capturedRequests: [(permissions: [PermissionType], domain: String, url: URL, completion: (Bool) -> Void)] = []
    var onPermissionRequested: (() -> Void)?

    func permissions(_ permissions: [PermissionType], requestedForDomain domain: String, url: URL, decisionHandler: @escaping (Bool) -> Void) {
        capturedRequests.append((permissions: permissions, domain: domain, url: url, completion: decisionHandler))
        onPermissionRequested?()
    }

    var lastRequest: (permissions: [PermissionType], domain: String, url: URL, completion: (Bool) -> Void)? {
        return capturedRequests.last
    }

    func respondToLastRequest(with decision: Bool) {
        guard let lastRequest = capturedRequests.last else { return }
        lastRequest.completion(decision)
    }

}

extension PermissionManagerMock: PermissionManagerDebugging {

    func allPermissionsDebugEntries() -> [PermissionDebugEntry] {
        savedPermissions.flatMap { domain, permissionsByType in
            permissionsByType.map { type, decision in
                // Encodes the decision the way `PermissionManagedObject.decision` writes it.
                PermissionDebugEntry(storageIdentifier: domain + "|" + type.rawValue,
                                     domain: domain,
                                     permissionType: type.rawValue,
                                     allow: decision == .allow,
                                     isRemoved: decision == .ask,
                                     effectiveDecision: permission(forDomain: domain, permissionType: type))
            }
        }
    }

    func removePermissionsDebugEntries(withIdentifiers identifiers: Set<String>) -> Int {
        let entries = savedPermissions.flatMap { domain, permissionsByType in
            permissionsByType.keys.map { (identifier: domain + "|" + $0.rawValue, domain: domain, type: $0) }
        }.filter { identifiers.contains($0.identifier) }

        for entry in entries {
            removePermission(forDomain: entry.domain, permissionType: entry.type)
        }
        return entries.count
    }

    func removeAllPermissions() -> Int {
        removeAllPermissionsCalled = true
        let count = savedPermissions.values.reduce(0) { $0 + $1.count }
        savedPermissions = [:]
        return count
    }

}
#endif

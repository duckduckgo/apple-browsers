//
//  PermissionCenterViewModel.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import Foundation

/// Represents a permission item displayed in the Permission Center
struct PermissionCenterItem: Identifiable {
    let id: PermissionType
    let permissionType: PermissionType
    var decision: PersistedPermissionDecision
    var isSystemDisabled: Bool

    var displayName: String {
        permissionType.localizedDescription
    }
}

/// ViewModel for the Permission Center popover
final class PermissionCenterViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published private(set) var domain: String
    @Published private(set) var permissionItems: [PermissionCenterItem] = []

    // MARK: - Dependencies

    private let permissionManager: PermissionManagerProtocol
    private let systemPermissionManager: SystemPermissionManagerProtocol
    private let usedPermissions: Permissions
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(
        domain: String,
        usedPermissions: Permissions,
        permissionManager: PermissionManagerProtocol,
        systemPermissionManager: SystemPermissionManagerProtocol = SystemPermissionManager()
    ) {
        self.domain = domain
        self.usedPermissions = usedPermissions
        self.permissionManager = permissionManager
        self.systemPermissionManager = systemPermissionManager

        loadPermissions()
        subscribeToPermissionChanges()
    }

    // MARK: - Public Methods

    /// Updates the decision for a permission type
    func setDecision(_ decision: PersistedPermissionDecision, for permissionType: PermissionType) {
        permissionManager.setPermission(decision, forDomain: domain, permissionType: permissionType)
    }

    /// Removes the permission (resets to "ask")
    func removePermission(_ permissionType: PermissionType) {
        setDecision(.ask, for: permissionType)
    }

    // MARK: - Private Methods

    private func loadPermissions() {
        permissionItems = usedPermissions.keys.map { permissionType in
            let decision = permissionManager.permission(forDomain: domain, permissionType: permissionType)
            let isSystemDisabled = checkSystemDisabled(for: permissionType)

            return PermissionCenterItem(
                id: permissionType,
                permissionType: permissionType,
                decision: decision,
                isSystemDisabled: isSystemDisabled
            )
        }.sorted { $0.permissionType.rawValue < $1.permissionType.rawValue }
    }

    private func checkSystemDisabled(for permissionType: PermissionType) -> Bool {
        guard permissionType.requiresSystemPermission else { return false }

        let authState = systemPermissionManager.authorizationState(for: permissionType)
        return authState == .denied || authState == .restricted || authState == .systemDisabled
    }

    private func subscribeToPermissionChanges() {
        permissionManager.permissionPublisher
            .filter { [weak self] in $0.domain == self?.domain }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.loadPermissions()
            }
            .store(in: &cancellables)
    }
}

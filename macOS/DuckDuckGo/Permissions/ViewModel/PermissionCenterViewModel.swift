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
    let domain: String
    var decision: PersistedPermissionDecision
    var isSystemDisabled: Bool

    var displayName: String {
        if case .externalScheme = permissionType {
            return UserText.permissionCenterExternalApps
        }
        return permissionType.localizedDescription
    }

    /// Additional description for external schemes (e.g., "zoom.us to open "zoomus" links")
    var externalSchemeDescription: String? {
        guard case .externalScheme(let scheme) = permissionType else { return nil }
        return String(format: UserText.permissionCenterExternalSchemeDescription, domain, scheme)
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
    private let removePermissionFromTab: (PermissionType) -> Void
    private let dismissPopover: () -> Void
    private var cancellables = Set<AnyCancellable>()
    private var removedPermissions = Set<PermissionType>()

    // MARK: - Initialization

    init(
        domain: String,
        usedPermissions: Permissions,
        permissionManager: PermissionManagerProtocol,
        removePermission: @escaping (PermissionType) -> Void,
        dismissPopover: @escaping () -> Void,
        systemPermissionManager: SystemPermissionManagerProtocol = SystemPermissionManager()
    ) {
        self.domain = domain
        self.usedPermissions = usedPermissions
        self.permissionManager = permissionManager
        self.removePermissionFromTab = removePermission
        self.dismissPopover = dismissPopover
        self.systemPermissionManager = systemPermissionManager

        loadPermissions()
        subscribeToPermissionChanges()
    }

    // MARK: - Public Methods

    /// Updates the decision for a permission type
    func setDecision(_ decision: PersistedPermissionDecision, for permissionType: PermissionType) {
        permissionManager.setPermission(decision, forDomain: domain, permissionType: permissionType)
    }

    /// Removes the permission completely (from webview, tracking, and storage)
    func removePermission(_ permissionType: PermissionType) {
        // Track removed permissions to prevent re-adding on reload
        removedPermissions.insert(permissionType)
        removePermissionFromTab(permissionType)
        // Also remove from UI immediately
        permissionItems.removeAll { $0.permissionType == permissionType }

        // Dismiss popover if no permissions left
        if permissionItems.isEmpty {
            dismissPopover()
        }
    }

    // MARK: - Private Methods

    private func loadPermissions() {
        permissionItems = usedPermissions.keys
            .filter { !removedPermissions.contains($0) }
            .map { permissionType in
                let decision = permissionManager.permission(forDomain: domain, permissionType: permissionType)
                let isSystemDisabled = checkSystemDisabled(for: permissionType)

                return PermissionCenterItem(
                    id: permissionType,
                    permissionType: permissionType,
                    domain: domain,
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

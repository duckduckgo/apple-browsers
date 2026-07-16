//
//  PrivacyDashboardPermissionHandler.swift
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

import Foundation
import Combine
import PrivacyDashboard
import AppKit

typealias PrivacyDashboardPermissionAuthorizationState = [(permission: PermissionType, state: PermissionAuthorizationState)]

final class PrivacyDashboardPermissionHandler {

    init(permissionManager: PermissionManagerProtocol) {
        self.permissionManager = permissionManager
    }

    private let permissionManager: PermissionManagerProtocol
    private weak var tabViewModel: TabViewModel?
    private var onPermissionChange: (([AllowedPermission]) -> Void)?
    private var cancellables = Set<AnyCancellable>()

    public func updateTabViewModel(_ tabViewModel: TabViewModel, onPermissionChange: @escaping ([AllowedPermission]) -> Void) {
        cancellables.removeAll()

        self.tabViewModel = tabViewModel
        self.onPermissionChange = onPermissionChange

        subscribeToPermissions()
    }

    public func setPermission(with permissionName: String, paused: Bool) {
        guard let permission = PermissionType(rawValue: permissionName) else { return }

        tabViewModel?.tab.permissions.set([permission], muted: paused)
    }

    public func setPermissionAuthorization(authorizationState: PermissionAuthorizationState, domain: String, permissionName: String) {
        guard let permission = PermissionType(rawValue: permissionName) else { return }

        permissionManager.setPermission(authorizationState.persistedPermissionDecision, forDomain: domain, permissionType: permission)
    }

    private func subscribeToPermissions() {
        tabViewModel?.$usedPermissions.receive(on: DispatchQueue.main).sink { [weak self] _ in
            self?.updatePermissions()
        }.store(in: &cancellables)
    }

    private func updatePermissions() {
        // Permission management is handled by the Permission Center
        onPermissionChange?([])
    }
}

extension PermissionType {
    var jsStyle: String {
        switch self {
        case .camera, .microphone, .geolocation, .popups, .notification, .autoplayPolicy:
            return self.rawValue
        case .externalScheme:
            return "externalScheme"
        }
    }

    var jsTitle: String {
        switch self {
        case .camera, .microphone, .geolocation, .popups, .notification, .autoplayPolicy:
            return self.localizedDescription
        case .externalScheme:
            return String(format: UserText.permissionExternalSchemeOpenFormat, self.localizedDescription)
        }
    }
}

extension PermissionAuthorizationState {

    init(decision: PersistedPermissionDecision) {
        switch decision {
        case .ask:
            self = .ask
        case .allow:
            self = .grant
        case .deny:
            self = .deny
        }
    }

    var persistedPermissionDecision: PersistedPermissionDecision {
        switch self {
        case .ask: return .ask
        case .grant: return .allow
        case .deny: return .deny
        }
    }

    func localizedFormat(for permission: PermissionType) -> String {
        switch (permission, self) {
        case (.popups, .ask):
            return UserText.privacyDashboardPopupsAlwaysAsk
        case (_, .ask):
            return UserText.privacyDashboardPermissionAsk
        case (_, .grant):
            return UserText.privacyDashboardPermissionAlwaysAllow
        case (_, .deny):
            return UserText.privacyDashboardPermissionAlwaysDeny
        }
    }
}

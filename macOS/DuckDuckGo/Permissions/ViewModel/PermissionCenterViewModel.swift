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

import BrowserServicesKit
import Combine
import FeatureFlags
import Foundation

/// Represents a blocked popup URL for the Permission Center
struct BlockedPopup: Identifiable {
    let id = UUID()
    let url: URL?
    let query: PermissionAuthorizationQuery

    var displayURL: String {
        guard let url = url, !url.isEmpty else { return "" }
        return url.absoluteString
    }

    /// Whether this popup has an empty or about: URL (should be grouped, not shown individually)
    var isEmptyOrAboutURL: Bool {
        guard let url = url else { return true }
        return url.isEmpty || url.navigationalScheme == .about
    }
}

/// Represents an external scheme (app) in the grouped External Apps row
struct ExternalSchemeInfo: Identifiable {
    let id: String // scheme name
    let scheme: String
    var decision: PersistedPermissionDecision

    /// Display text like 'Open "mailto" links'
    var displayText: String {
        String(format: UserText.permissionCenterExternalSchemeFormat, scheme)
    }
}

/// Represents a permission item displayed in the Permission Center
struct PermissionCenterItem: Identifiable {
    let id: PermissionType
    let permissionType: PermissionType
    let domain: String
    var decision: PersistedPermissionDecision
    var isSystemDisabled: Bool

    /// Current state of the permission (active, inactive, etc.)
    var state: PermissionState
    /// For popups: the list of blocked popup URLs and their queries
    var blockedPopups: [BlockedPopup]
    /// For external apps: grouped external schemes
    var externalSchemes: [ExternalSchemeInfo]

    /// Whether the permission is currently in use (e.g., camera/mic actively recording)
    var isInUse: Bool {
        state == .active
    }

    /// Whether the permission is allowed (granted or user selected "Always Allow")
    var isAllowed: Bool {
        // Check persisted decision first
        if decision == .allow {
            return true
        }
        // Also check runtime state
        switch state {
        case .active, .inactive, .paused:
            return true
        default:
            return false
        }
    }

    var displayName: String {
        if case .externalScheme = permissionType {
            return UserText.permissionCenterExternalApps
        }
        return permissionType.localizedDescription
    }

    /// Whether this is a grouped external apps row
    var isGroupedExternalApps: Bool {
        if case .externalScheme = permissionType {
            return true
        }
        return false
    }

    /// Header text for popups (e.g., "Blocked 2 pop-ups")
    var blockedPopupsHeaderText: String? {
        guard permissionType == .popups, !blockedPopups.isEmpty else { return nil }
        return UserText.permissionPopupTitle(count: blockedPopups.count)
    }

    /// Popups with actual URLs that should be shown as clickable links
    /// (excludes empty/about: URLs which are grouped and handled via "Only allow for this visit")
    var visibleBlockedPopups: [BlockedPopup] {
        blockedPopups.filter { !$0.isEmptyOrAboutURL }
    }

    /// Popups with empty/about: URLs that are grouped (not shown individually)
    var groupedEmptyPopups: [BlockedPopup] {
        blockedPopups.filter { $0.isEmptyOrAboutURL }
    }
}

/// Popup decision options for the Permission Center dropdown
enum PopupDecision: Hashable {
    case allowForThisVisit
    case notify
    case alwaysAllow

}

/// ViewModel for the Permission Center popover
final class PermissionCenterViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published private(set) var domain: String
    @Published private(set) var permissionItems: [PermissionCenterItem] = []

    // MARK: - Dependencies

    private let permissionManager: PermissionManagerProtocol
    private let systemPermissionManager: SystemPermissionManagerProtocol
    private let featureFlagger: FeatureFlagger
    private let usedPermissions: Permissions
    private var popupQueries: [PermissionAuthorizationQuery]
    private let removePermissionFromTab: (PermissionType) -> Void
    private let dismissPopover: () -> Void
    private let onPermissionRemoved: (() -> Void)?
    private let openPopup: ((PermissionAuthorizationQuery) -> Void)?
    private let setTemporaryPopupAllowance: (() -> Void)?
    private let resetTemporaryPopupAllowance: (() -> Void)?
    private let grantPermission: ((PermissionAuthorizationQuery) -> Void)?
    private var cancellables = Set<AnyCancellable>()
    private var removedPermissions = Set<PermissionType>()
    private(set) var hasTemporaryPopupAllowance: Bool

    /// Whether "Only allow pop-ups for this visit" option should be shown (based on feature flags)
    var showAllowPopupsForThisVisitOption: Bool {
        featureFlagger.isFeatureOn(.popupBlocking) && featureFlagger.isFeatureOn(.allowPopupsForCurrentPage)
    }

    // MARK: - Initialization

    /// Whether a page-initiated popup was opened (auto-allowed due to "Always Allow" setting)
    private let pageInitiatedPopupOpened: Bool

    init(
        domain: String,
        usedPermissions: Permissions,
        popupQueries: [PermissionAuthorizationQuery] = [],
        permissionManager: PermissionManagerProtocol,
        featureFlagger: FeatureFlagger,
        removePermission: @escaping (PermissionType) -> Void,
        dismissPopover: @escaping () -> Void,
        onPermissionRemoved: (() -> Void)? = nil,
        openPopup: ((PermissionAuthorizationQuery) -> Void)? = nil,
        setTemporaryPopupAllowance: (() -> Void)? = nil,
        resetTemporaryPopupAllowance: (() -> Void)? = nil,
        grantPermission: ((PermissionAuthorizationQuery) -> Void)? = nil,
        hasTemporaryPopupAllowance: Bool = false,
        pageInitiatedPopupOpened: Bool = false,
        systemPermissionManager: SystemPermissionManagerProtocol = SystemPermissionManager()
    ) {
        self.domain = domain
        self.usedPermissions = usedPermissions
        self.popupQueries = popupQueries
        self.permissionManager = permissionManager
        self.featureFlagger = featureFlagger
        self.removePermissionFromTab = removePermission
        self.dismissPopover = dismissPopover
        self.onPermissionRemoved = onPermissionRemoved
        self.openPopup = openPopup
        self.setTemporaryPopupAllowance = setTemporaryPopupAllowance
        self.resetTemporaryPopupAllowance = resetTemporaryPopupAllowance
        self.grantPermission = grantPermission
        self.hasTemporaryPopupAllowance = hasTemporaryPopupAllowance
        self.pageInitiatedPopupOpened = pageInitiatedPopupOpened
        self.systemPermissionManager = systemPermissionManager

        loadPermissions()
        subscribeToPermissionChanges()
    }

    // MARK: - Public Methods

    /// Updates the decision for a permission type
    func setDecision(_ decision: PersistedPermissionDecision, for permissionType: PermissionType) {
        permissionManager.setPermission(decision, forDomain: domain, permissionType: permissionType)

        // If setting to "Always Allow" and there's a pending request, grant it
        if decision == .allow, case .requested(let query) = usedPermissions[permissionType] {
            grantPermission?(query)
        }
    }

    /// Updates the decision for a specific external scheme
    func setExternalSchemeDecision(_ decision: PersistedPermissionDecision, for scheme: String) {
        let permissionType = PermissionType.externalScheme(scheme: scheme)
        permissionManager.setPermission(decision, forDomain: domain, permissionType: permissionType)
    }

    /// Removes a specific external scheme from the grouped row
    func removeExternalScheme(_ scheme: String) {
        let permissionType = PermissionType.externalScheme(scheme: scheme)
        removedPermissions.insert(permissionType)
        removePermissionFromTab(permissionType)

        // Update the grouped item by removing this scheme
        if let index = permissionItems.firstIndex(where: { $0.isGroupedExternalApps }) {
            permissionItems[index].externalSchemes.removeAll { $0.scheme == scheme }

            // If no more schemes, remove the entire row
            if permissionItems[index].externalSchemes.isEmpty {
                permissionItems.remove(at: index)
            }
        }

        // Notify that a permission was removed
        onPermissionRemoved?()

        // Dismiss popover if no permissions left
        if permissionItems.isEmpty {
            dismissPopover()
        }
    }

    /// Updates the popup decision (special handling for popups)
    func setPopupDecision(_ decision: PopupDecision) {
        switch decision {
        case .allowForThisVisit:
            // Allow only the grouped empty/about URL popups (non-empty ones are opened via individual links)
            let emptyUrlQueries = popupQueries.filter { query in
                guard let url = query.url else { return true }
                return url.isEmpty || url.navigationalScheme == .about
            }
            for query in emptyUrlQueries {
                openPopup?(query)
            }
            permissionManager.setPermission(.ask, forDomain: domain, permissionType: .popups)
            setTemporaryPopupAllowance?()
            hasTemporaryPopupAllowance = true
        case .notify:
            permissionManager.setPermission(.ask, forDomain: domain, permissionType: .popups)
            resetTemporaryPopupAllowance?()
            hasTemporaryPopupAllowance = false
        case .alwaysAllow:
            // Open all blocked popups
            for query in popupQueries {
                openPopup?(query)
            }
            // Clear popup queries so they don't reappear when loadPermissions() is called
            popupQueries = []
            // Clear blocked popups from UI since they've been opened
            if let index = permissionItems.firstIndex(where: { $0.permissionType == .popups }) {
                permissionItems[index].blockedPopups = []
            }
            permissionManager.setPermission(.allow, forDomain: domain, permissionType: .popups)
            resetTemporaryPopupAllowance?()
            hasTemporaryPopupAllowance = false
        }
    }

    /// Returns the current popup decision based on persisted permission and temporary allowance
    func currentPopupDecision() -> PopupDecision {
        let persistedValue = permissionManager.permission(forDomain: domain, permissionType: .popups)
        if hasTemporaryPopupAllowance && persistedValue == .ask {
            return .allowForThisVisit
        } else if persistedValue == .allow {
            return .alwaysAllow
        } else {
            return .notify
        }
    }

    /// Opens a specific blocked popup
    func openBlockedPopup(_ popup: BlockedPopup) {
        openPopup?(popup.query)
    }

    /// Removes the permission completely (from webview, tracking, and storage)
    func removePermission(_ permissionType: PermissionType) {
        // Track removed permissions to prevent re-adding on reload
        removedPermissions.insert(permissionType)
        removePermissionFromTab(permissionType)
        // Also remove from UI immediately
        permissionItems.removeAll { $0.permissionType == permissionType }

        // Reset temporary popup allowance when removing popup permission
        if permissionType == .popups {
            resetTemporaryPopupAllowance?()
            hasTemporaryPopupAllowance = false
        }

        // Notify that a permission was removed (to update UI like permission button visibility)
        onPermissionRemoved?()

        // Dismiss popover if no permissions left
        if permissionItems.isEmpty {
            dismissPopover()
        }
    }

    // MARK: - Private Methods

    private func loadPermissions() {
        // Clear permissions from removedPermissions if they are re-requested
        for (permissionType, state) in usedPermissions where state.isRequested {
            removedPermissions.remove(permissionType)
        }

        // Separate external schemes from other permissions
        var externalSchemePermissions: [PermissionType] = []
        var otherPermissions: [PermissionType] = []

        for permissionType in usedPermissions.keys where !removedPermissions.contains(permissionType) {
            if case .externalScheme = permissionType {
                externalSchemePermissions.append(permissionType)
            } else if permissionType != .notification {
                otherPermissions.append(permissionType)
            }
        }

        // Add popup permission if a page-initiated popup was auto-allowed (due to "Always Allow" setting)
        // and popup is not already in usedPermissions
        if pageInitiatedPopupOpened,
           !otherPermissions.contains(.popups),
           !removedPermissions.contains(.popups) {
            otherPermissions.append(.popups)
        }

        // Build items for non-external-scheme permissions
        var items: [PermissionCenterItem] = otherPermissions.map { permissionType in
            let decision = permissionManager.permission(forDomain: domain, permissionType: permissionType)
            let isSystemDisabled = checkSystemDisabled(for: permissionType)
            let state = usedPermissions[permissionType] ?? .inactive

            // For popups, populate the blocked popup URLs from queries
            let blockedPopups: [BlockedPopup]
            if permissionType == .popups {
                blockedPopups = popupQueries.map { query in
                    BlockedPopup(url: query.url, query: query)
                }
            } else {
                blockedPopups = []
            }

            return PermissionCenterItem(
                id: permissionType,
                permissionType: permissionType,
                domain: domain,
                decision: decision,
                isSystemDisabled: isSystemDisabled,
                state: state,
                blockedPopups: blockedPopups,
                externalSchemes: []
            )
        }

        // Group all external schemes into a single row
        if !externalSchemePermissions.isEmpty {
            let externalSchemes: [ExternalSchemeInfo] = externalSchemePermissions.compactMap { permissionType in
                guard case .externalScheme(let scheme) = permissionType else { return nil }
                let decision = permissionManager.permission(forDomain: domain, permissionType: permissionType)
                return ExternalSchemeInfo(
                    id: scheme,
                    scheme: scheme,
                    decision: decision
                )
            }.sorted { $0.scheme < $1.scheme }

            // Use the first external scheme as the representative permission type for the grouped row
            let representativeType = externalSchemePermissions[0]
            let state = usedPermissions[representativeType] ?? .inactive

            let groupedItem = PermissionCenterItem(
                id: representativeType,
                permissionType: representativeType,
                domain: domain,
                decision: .ask, // Not used for grouped row
                isSystemDisabled: false,
                state: state,
                blockedPopups: [],
                externalSchemes: externalSchemes
            )
            items.append(groupedItem)
        }

        permissionItems = items.sorted { $0.permissionType.rawValue < $1.permissionType.rawValue }
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

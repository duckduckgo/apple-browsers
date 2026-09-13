//
//  SitePermissionsSheetViewModel.swift
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

import Combine

public enum SitePermissionsSheetState: Equatable, Sendable {
    /// Permission rows without a reminder to enable access in system settings.
    case permissionsOnly
    /// Permission rows and a reminder to enable access in system settings.
    case permissionsAndReminder
    /// A reminder to enable access in system settings, with no permission rows.
    case reminderOnly
}

public enum SitePermissionPickerOption: String, Hashable, Sendable {
    case askEachTime
    case alwaysAllow
    case neverAllow

    public var decision: SitePermissionDecision {
        switch self {
        case .askEachTime:
            return .ask
        case .alwaysAllow:
            return .allow
        case .neverAllow:
            return .deny
        }
    }
}

public struct SitePermissionDecisionChange: Equatable, Sendable {
    public let permissionType: SitePermissionType
    public let from: SitePermissionDecision
    public let to: SitePermissionDecision

    public init(permissionType: SitePermissionType, from: SitePermissionDecision, to: SitePermissionDecision) {
        self.permissionType = permissionType
        self.from = from
        self.to = to
    }
}

public struct SitePermissionsRemoval: Sendable {
    public let snapshot: SitePermissionsSnapshot
    public let permissionTypes: Set<SitePermissionType>

    public init(snapshot: SitePermissionsSnapshot,
                permissionTypes: Set<SitePermissionType>) {
        self.snapshot = snapshot
        self.permissionTypes = permissionTypes
    }
}

public enum SitePermissionsSheetDismissal: Equatable, Sendable {
    case clean
    case dirty
}

@MainActor
public final class SitePermissionsSheetViewModel: ObservableObject {

    public struct Row: Equatable, Identifiable, Sendable {
        public enum IconState: Equatable, Sendable {
            /// Capture is inactive and the site decision is Ask Each Time.
            case outline
            /// Capture is inactive and the site decision is Never Allow.
            case blocked
            /// Capture is paused, or inactive with an Allow decision.
            case solid
            /// The site is actively using the camera or microphone.
            case inUse
        }

        public let permissionType: SitePermissionType
        public let decision: SitePermissionDecision
        public let captureState: SitePermissionCaptureState
        public let options: [SitePermissionPickerOption]
        public let selectedOption: SitePermissionPickerOption
        public let iconState: IconState
        public let title: String
        public let stateText: String
        public let accessibilityValue: String

        public var id: SitePermissionType { permissionType }
    }

    public typealias DecisionChangedHandler = (SitePermissionDecisionChange) -> Void
    public typealias RemovePermissionsHandler = (SitePermissionsRemoval) -> Void
    public typealias OpenSystemSettingsHandler = (Set<SitePermissionType>) -> Void
    public typealias DismissHandler = (SitePermissionsSheetDismissal) -> Void
    public typealias RevokePermissionsHandler = (Set<SitePermissionType>) -> Void

    @Published public private(set) var rows = [Row]()
    @Published public private(set) var state = SitePermissionsSheetState.permissionsOnly
    @Published public private(set) var hasCommittedChanges = false

    public let site: SitePermissionKey

    public var title: String {
        UserText.PermissionManagement.title(domain: site.host)
    }

    public var reminderText: String? {
        guard !systemBlockedPermissionTypes.isEmpty else { return nil }
        return UserText.PermissionManagement.reminder(permissionTypes: systemBlockedPermissionTypes)
    }

    public var systemSettingsPermissionTypes: Set<SitePermissionType> {
        systemBlockedPermissionTypes
    }

    public var dismissalState: SitePermissionsSheetDismissal {
        isEditing ? .dirty : .clean
    }

    private let store: SitePermissionsStore
    private let isFireMode: Bool
    private let onDecisionChanged: DecisionChangedHandler
    private let onRemovePermissions: RemovePermissionsHandler
    private let onOpenSystemSettings: OpenSystemSettingsHandler
    private let onDismiss: DismissHandler
    private let revokePermissions: RevokePermissionsHandler

    private var storedPermissions: SitePermissionsStore.SitePermissionRecord
    private var ephemeralPermissionTypes: Set<SitePermissionType>
    private var siteAllowedPermissionTypesThisVisit: Set<SitePermissionType>
    private var requestedPermissionTypesThisVisit: Set<SitePermissionType>
    private var captureStates: [SitePermissionType: SitePermissionCaptureState]
    private var systemAuthorizationStates: [SitePermissionType: SystemPermissionAuthorizationState]
    private var systemBlockedPermissionTypes: Set<SitePermissionType>
    private var isEditing = false
    private var hasDismissed = false

    public init(snapshot: SitePermissionsManagementSnapshot,
                store: SitePermissionsStore,
                onDecisionChanged: @escaping DecisionChangedHandler = { _ in },
                onRemovePermissions: @escaping RemovePermissionsHandler = { _ in },
                onOpenSystemSettings: @escaping OpenSystemSettingsHandler = { _ in },
                onDismiss: @escaping DismissHandler = { _ in },
                revokePermissions: @escaping RevokePermissionsHandler = { _ in }) {
        site = snapshot.site
        isFireMode = snapshot.isFireMode
        self.store = store
        self.onDecisionChanged = onDecisionChanged
        self.onRemovePermissions = onRemovePermissions
        self.onOpenSystemSettings = onOpenSystemSettings
        self.onDismiss = onDismiss
        self.revokePermissions = revokePermissions
        storedPermissions = snapshot.storedPermissions
        ephemeralPermissionTypes = snapshot.ephemeralPermissionTypes
        siteAllowedPermissionTypesThisVisit = snapshot.siteAllowedPermissionTypesThisVisit
        requestedPermissionTypesThisVisit = snapshot.requestedPermissionTypesThisVisit
        captureStates = snapshot.captureStates
        systemAuthorizationStates = snapshot.systemAuthorizationStates
        systemBlockedPermissionTypes = snapshot.systemBlockedPermissionTypes
        rebuild()
    }

    public func refresh(with snapshot: SitePermissionsManagementSnapshot) {
        guard snapshot.site == site else { return }
        storedPermissions = snapshot.storedPermissions
        ephemeralPermissionTypes = snapshot.ephemeralPermissionTypes
        siteAllowedPermissionTypesThisVisit = snapshot.siteAllowedPermissionTypesThisVisit
        requestedPermissionTypesThisVisit = snapshot.requestedPermissionTypesThisVisit
        captureStates = snapshot.captureStates
        systemAuthorizationStates = snapshot.systemAuthorizationStates
        systemBlockedPermissionTypes = snapshot.systemBlockedPermissionTypes
        rebuild()
    }

    public func beginEditing() {
        isEditing = true
    }

    public func select(_ option: SitePermissionPickerOption, for permissionType: SitePermissionType) {
        guard let row = rows.first(where: { $0.permissionType == permissionType }),
              row.options.contains(option) else {
            return
        }

        isEditing = false
        guard option != row.selectedOption else { return }

        let change = SitePermissionDecisionChange(permissionType: permissionType,
                                                  from: row.decision,
                                                  to: option.decision)
        if !isFireMode {
            switch option {
            case .askEachTime:
                store.resetDecision(for: permissionType, at: site)
            case .alwaysAllow:
                store.setPersistentDecision(.allow, for: permissionType, at: site)
            case .neverAllow:
                store.setPersistentDecision(.deny, for: permissionType, at: site)
            }
        }

        storedPermissions[permissionType] = option.decision
        ephemeralPermissionTypes.remove(permissionType)
        if option == .alwaysAllow {
            siteAllowedPermissionTypesThisVisit.insert(permissionType)
        } else {
            siteAllowedPermissionTypesThisVisit.remove(permissionType)
        }
        updateSystemBlock(for: permissionType)
        rebuild()
        hasCommittedChanges = true

        onDecisionChanged(change)
        if option == .neverAllow {
            revokePermissions([permissionType])
        }
    }

    public func removePermissions() {
        let permissionTypes = relevantPermissionTypes
        let snapshot = isFireMode ? SitePermissionsSnapshot.empty : store.removePermissions(for: site)

        onRemovePermissions(SitePermissionsRemoval(snapshot: snapshot,
                                                    permissionTypes: permissionTypes))
        revokePermissions(SitePermissionsManagementSnapshot.managedPermissionTypes)
        dismiss()
    }

    public func openSystemSettings() {
        guard !systemBlockedPermissionTypes.isEmpty else { return }
        onOpenSystemSettings(systemBlockedPermissionTypes)
    }

    public func dismiss() {
        guard !hasDismissed else { return }
        hasDismissed = true
        hasCommittedChanges = false
        onDismiss(dismissalState)
    }

    private var relevantPermissionTypes: Set<SitePermissionType> {
        let activeCaptureTypes = Set(captureStates.compactMap { entry in
            entry.value == .inactive ? nil : entry.key
        })
        return Set(storedPermissions.keys)
            .union(ephemeralPermissionTypes)
            .union(siteAllowedPermissionTypesThisVisit)
            .union(requestedPermissionTypesThisVisit)
            .union(activeCaptureTypes)
            .intersection(SitePermissionsManagementSnapshot.managedPermissionTypes)
    }

    private func rebuild() {
        rows = SitePermissionsManagementSnapshot.managedPermissionTypes
            .filter(relevantPermissionTypes.contains)
            .sorted { $0.managementOrder < $1.managementOrder }
            .map(makeRow)

        if rows.isEmpty, !systemBlockedPermissionTypes.isEmpty {
            state = .reminderOnly
        } else if !systemBlockedPermissionTypes.isEmpty {
            state = .permissionsAndReminder
        } else {
            state = .permissionsOnly
        }
    }

    private func makeRow(for permissionType: SitePermissionType) -> Row {
        let decision = storedPermissions[permissionType] ?? .ask
        let captureState = captureStates[permissionType] ?? .inactive
        let options: [SitePermissionPickerOption] = [.askEachTime, .alwaysAllow, .neverAllow]
        let selectedOption = decision.pickerOption
        let stateText = UserText.PermissionManagement.title(for: selectedOption)
        let accessibilityValue: String
        switch captureState {
        case .active:
            accessibilityValue = UserText.PermissionManagement.inUseAccessibilityValue(state: stateText)
        case .paused:
            accessibilityValue = UserText.PermissionManagement.pausedAccessibilityValue(state: stateText)
        case .inactive:
            accessibilityValue = stateText
        }

        return Row(permissionType: permissionType,
                   decision: decision,
                   captureState: captureState,
                   options: options,
                   selectedOption: selectedOption,
                   iconState: iconState(decision: decision, captureState: captureState),
                   title: UserText.PermissionManagement.title(for: permissionType),
                   stateText: stateText,
                   accessibilityValue: accessibilityValue)
    }

    private func iconState(decision: SitePermissionDecision, captureState: SitePermissionCaptureState) -> Row.IconState {
        switch captureState {
        case .active:
            return .inUse
        case .paused:
            return .solid
        case .inactive:
            switch decision {
            case .ask:
                return .outline
            case .allow:
                return .solid
            case .deny:
                return .blocked
            }
        }
    }

    private func updateSystemBlock(for permissionType: SitePermissionType) {
        guard storedPermissions[permissionType] == .allow else {
            systemBlockedPermissionTypes.remove(permissionType)
            return
        }
        switch systemAuthorizationStates[permissionType] {
        case .denied, .restricted, .unavailable:
            systemBlockedPermissionTypes.insert(permissionType)
        case .notDetermined, .authorized, nil:
            systemBlockedPermissionTypes.remove(permissionType)
        }
    }
}

private extension SitePermissionDecision {
    var pickerOption: SitePermissionPickerOption {
        switch self {
        case .ask:
            return .askEachTime
        case .allow:
            return .alwaysAllow
        case .deny:
            return .neverAllow
        }
    }
}

private extension SitePermissionType {
    var managementOrder: Int {
        switch self {
        case .location:
            return 0
        case .camera:
            return 1
        case .microphone:
            return 2
        }
    }
}

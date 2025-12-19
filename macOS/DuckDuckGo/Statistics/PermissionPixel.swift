//
//  PermissionPixel.swift
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

import PixelKit

/**
 * This enum keeps pixels related to permissions management.
 *
 * These pixels are only fired when the newPermissionView feature flag is enabled.
 */
enum PermissionPixel: PixelKitEvent {

    // MARK: - Authorization Flow

    /**
     * Event Trigger: User selects an option in the permission authorization dialog.
     *
     * Parameters:
     * - permissionType: The type of permission (camera, microphone, geolocation, etc.)
     * - decision: The user's decision (allow, deny)
     */
    case authorizationDecision(permissionType: PermissionType, decision: AuthorizationDecision)

    // MARK: - Permission Center

    /**
     * Event Trigger: User changes a permission decision in the Permission Center dropdown.
     *
     * Parameters:
     * - permissionType: The type of permission being changed
     * - from: The previous decision
     * - to: The new decision
     */
    case permissionCenterChanged(permissionType: PermissionType, from: PersistedPermissionDecision, to: PersistedPermissionDecision)

    /**
     * Event Trigger: User clicks the remove (X) button to reset a permission in the Permission Center.
     *
     * Parameters:
     * - permissionType: The type of permission being reset
     */
    case permissionCenterReset(permissionType: PermissionType)

    // MARK: - System Preferences

    /**
     * Event Trigger: User clicks the link to open System Preferences for a permission.
     *
     * Parameters:
     * - permissionType: The type of permission for which System Preferences is opened
     */
    case systemPreferencesOpened(permissionType: PermissionType)

    // MARK: - PixelKitEvent

    var name: String {
        switch self {
        case .authorizationDecision(let permissionType, let decision):
            return "m_mac_permission_authorization_\(permissionType.pixelName)_\(decision.pixelName)"

        case .permissionCenterChanged(let permissionType, _, let to):
            return "m_mac_permission_center_changed_\(permissionType.pixelName)_to_\(to.pixelName)"

        case .permissionCenterReset(let permissionType):
            return "m_mac_permission_center_reset_\(permissionType.pixelName)"

        case .systemPreferencesOpened(let permissionType):
            return "m_mac_permission_system_preferences_\(permissionType.pixelName)"
        }
    }

    var parameters: [String: String]? {
        switch self {
        case .permissionCenterChanged(_, let from, _):
            // Include the "from" decision as a parameter for additional context
            return ["from": from.pixelName]
        default:
            return nil
        }
    }

    var standardParameters: [PixelKitStandardParameter]? {
        return [.pixelSource]
    }
}

// MARK: - Authorization Decision

extension PermissionPixel {

    /// Represents a user's decision in the authorization dialog
    enum AuthorizationDecision: String {
        case allow
        case deny

        var pixelName: String {
            return rawValue
        }
    }
}

// MARK: - Pixel Name Extensions

extension PermissionType {

    /// Returns a lowercase string suitable for use in pixel names
    var pixelName: String {
        switch self {
        case .camera:
            return "camera"
        case .microphone:
            return "microphone"
        case .geolocation:
            return "geolocation"
        case .popups:
            return "popups"
        case .notification:
            return "notification"
        case .externalScheme:
            return "external_scheme"
        }
    }
}

extension PersistedPermissionDecision {

    /// Returns a lowercase string suitable for use in pixel names
    var pixelName: String {
        switch self {
        case .ask:
            return "ask"
        case .allow:
            return "allow"
        case .deny:
            return "deny"
        }
    }
}

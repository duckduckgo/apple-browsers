//
//  PermissionAuthorizationSwiftUIView.swift
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

import AppKit
import Combine
import SwiftUI

// MARK: - PermissionAuthorizationType

/// UI-only permission type for the authorization SwiftUI view.
/// This handles the combined camera+microphone case without modifying the model layer.
enum PermissionAuthorizationType {
    case camera
    case microphone
    case cameraAndMicrophone
    case geolocation
    case popups
    case externalScheme(scheme: String)

    /// Creates the appropriate type from an array of PermissionType
    init(from permissions: [PermissionType]) {
        if Set(permissions) == Set([.camera, .microphone]) {
            self = .cameraAndMicrophone
        } else if let first = permissions.first {
            switch first {
            case .camera: self = .camera
            case .microphone: self = .microphone
            case .geolocation: self = .geolocation
            case .popups: self = .popups
            case .externalScheme(let scheme): self = .externalScheme(scheme: scheme)
            }
        } else {
            assertionFailure("Unexpected permission types combination")
            self = .camera // fallback, shouldn't happen
        }
    }

    var localizedDescription: String {
        switch self {
        case .camera:
            return UserText.permissionCamera
        case .microphone:
            return UserText.permissionMicrophone
        case .cameraAndMicrophone:
            return UserText.permissionCameraAndMicrophone
        case .geolocation:
            return UserText.permissionGeolocation
        case .popups:
            return UserText.permissionPopups
        case .externalScheme(scheme: let scheme):
            guard let url = URL(string: scheme + URL.NavigationalScheme.separator),
                  let app = NSWorkspace.shared.application(toOpen: url)
            else { return scheme }
            return app
        }
    }

    /// Whether this permission type requires a two-step authorization flow (system permission first, then website permission)
    var requiresSystemPermission: Bool {
        switch self {
        case .geolocation:
            return true
        case .camera, .microphone, .cameraAndMicrophone, .popups, .externalScheme:
            return false
        }
    }

    /// Whether this permission uses permanent decisions ("Always Allow" / "Never Allow") vs one-time decisions ("Allow" / "Deny")
    var usesPermanentDecisions: Bool {
        switch self {
        case .camera, .microphone, .cameraAndMicrophone, .popups, .externalScheme, .geolocation:
            return true
        }
    }

    // MARK: - Two-Step UI Localized Strings

    /// Button text for enabling system permission (Step 1)
    var systemPermissionEnableText: String {
        switch self {
        case .geolocation:
            return UserText.permissionSystemLocationEnable
        case .camera, .microphone, .cameraAndMicrophone, .popups, .externalScheme:
            return "" // Not used for these types
        }
    }

    /// Text shown while waiting for system permission response
    var systemPermissionWaitingText: String {
        switch self {
        case .geolocation:
            return UserText.permissionSystemLocationWaiting
        case .camera, .microphone, .cameraAndMicrophone, .popups, .externalScheme:
            return ""
        }
    }

    /// Text shown when system permission is granted
    var systemPermissionEnabledText: String {
        switch self {
        case .geolocation:
            return UserText.permissionSystemLocationEnabled
        case .camera, .microphone, .cameraAndMicrophone, .popups, .externalScheme:
            return ""
        }
    }

    /// Text shown when system permission was previously disabled (prefix before link)
    var systemPermissionDisabledText: String {
        switch self {
        case .geolocation:
            return UserText.permissionSystemLocationDisabled
        case .camera, .microphone, .cameraAndMicrophone, .popups, .externalScheme:
            return ""
        }
    }

    /// Link text for opening System Settings
    var systemSettingsLinkText: String {
        switch self {
        case .geolocation:
            return UserText.permissionSystemSettingsLocation
        case .camera, .microphone, .cameraAndMicrophone, .popups, .externalScheme:
            return ""
        }
    }

    /// URL to open the relevant System Settings pane
    var systemSettingsURL: URL? {
        switch self {
        case .geolocation:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")
        case .camera, .microphone, .cameraAndMicrophone, .popups, .externalScheme:
            return nil
        }
    }

    /// Converts back to a single PermissionType for system permission checks.
    /// For cameraAndMicrophone, returns .camera as both require the same system permission flow.
    var asPermissionType: PermissionType {
        switch self {
        case .camera: return .camera
        case .microphone: return .microphone
        case .cameraAndMicrophone: return .camera // Use camera for system permission checks
        case .geolocation: return .geolocation
        case .popups: return .popups
        case .externalScheme(let scheme): return .externalScheme(scheme: scheme)
        }
    }
}

// MARK: - PermissionAuthorizationSwiftUIView

struct PermissionAuthorizationSwiftUIView: View {
    let domain: String
    let permissionType: PermissionAuthorizationType
    let onDeny: () -> Void
    let onAlwaysDeny: () -> Void
    let onAllow: () -> Void
    let onAlwaysAllow: () -> Void
    let systemPermissionManager: SystemPermissionManagerProtocol

    /// State for the system permission step in two-step flow
    enum SystemPermissionState {
        case initial
        case waiting
        case authorized
        case denied
        /// Permission was already denied/restricted/disabled before showing the UI
        case alreadyDenied
    }

    @State private var systemPermissionState: SystemPermissionState = .initial
    @State private var authorizationCancellable: AnyCancellable?

    // MARK: - Computed Properties

    /// Whether to show the two-step UI
    private var showsTwoStepUI: Bool {
        guard permissionType.requiresSystemPermission else { return false }
        return systemPermissionManager.isAuthorizationRequired(for: permissionType.asPermissionType) || systemPermissionState != .initial
    }

    private var promptText: String {
        switch permissionType {
        case .geolocation:
            return String(format: UserText.permissionGeolocationPromptFormat, domain)
        case .camera, .microphone, .cameraAndMicrophone:
            return String(format: UserText.devicePermissionAuthorizationFormat, domain, permissionType.localizedDescription.lowercased())
        case .popups:
            return String(format: UserText.popupWindowsPermissionAuthorizationFormat, domain, permissionType.localizedDescription.lowercased())
        case .externalScheme:
            if domain.isEmpty {
                return String(format: UserText.externalSchemePermissionAuthorizationNoDomainFormat, permissionType.localizedDescription)
            } else {
                return String(format: UserText.externalSchemePermissionAuthorizationFormat, domain, permissionType.localizedDescription)
            }
        }
    }

    // MARK: - Button Titles & Actions

    private var denyButtonTitle: String {
        permissionType.usesPermanentDecisions ? UserText.permissionPopupAlwaysDenyButton : UserText.permissionPopupDenyButton
    }

    private var allowButtonTitle: String {
        permissionType.usesPermanentDecisions ? UserText.permissionPopupAlwaysAllowButton : UserText.permissionPopupAllowButton
    }

    private var denyAction: () -> Void {
        permissionType.usesPermanentDecisions ? onAlwaysDeny : onDeny
    }

    private var allowAction: () -> Void {
        permissionType.usesPermanentDecisions ? onAlwaysAllow : onAllow
    }

    // MARK: - Body

    var body: some View {
        if showsTwoStepUI {
            twoStepPermissionView
        } else {
            standardPermissionView
        }
    }

    // MARK: - Two-Step Permission View

    private var twoStepPermissionView: some View {
        VStack(spacing: 16) {
            // Prompt text
            Text(promptText)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.top, 16)

            // Step 1: System permission
            stepOneView
                .padding(.horizontal, 16)

            // Step 2: Website permission
            stepTwoView
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
        .frame(width: 360)
        .background(Color(designSystemColor: .containerFillPrimary))
        .onAppear {
            initializeSystemPermissionState()
        }
    }

    /// Check if system permission was already denied before showing the UI
    private func initializeSystemPermissionState() {
        guard systemPermissionState == .initial else { return }

        let authState = systemPermissionManager.authorizationState(for: permissionType.asPermissionType)
        switch authState {
        case .denied, .restricted, .systemDisabled:
            systemPermissionState = .alreadyDenied
        case .authorized:
            systemPermissionState = .authorized
        case .notDetermined:
            break // Keep initial state
        }
    }

    @ViewBuilder
    private var stepOneView: some View {
        HStack(spacing: 12) {
            stepIndicator(step: 1, isActive: systemPermissionState != .authorized)

            switch systemPermissionState {
            case .initial:
                Button(action: requestSystemPermission) {
                    Text(permissionType.systemPermissionEnableText)
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(Color.accentColor)
                        .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityIdentifier("PermissionAuthorizationSwiftUIView.enableSystemPermissionButton")

            case .waiting:
                Text(permissionType.systemPermissionWaitingText)
                    .font(.system(size: 13))
                    .foregroundColor(Color(designSystemColor: .textSecondary))
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(Color(designSystemColor: .controlsFillSecondary))
                    .cornerRadius(8)

            case .authorized:
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Color(NSColor.systemGreen))
                        .font(.system(size: 20))

                    Text(permissionType.systemPermissionEnabledText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(NSColor.systemGreen))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 36)

            case .alreadyDenied, .denied:
                systemPermissionDisabledView
            }
        }
    }

    /// View shown when system permission was already denied - displays link to System Settings
    private var systemPermissionDisabledView: some View {
        (Text(permissionType.systemPermissionDisabledText)
            .font(.system(size: 13))
            .foregroundColor(Color(designSystemColor: .textPrimary))
        + Text(permissionType.systemSettingsLinkText)
            .font(.system(size: 13))
            .foregroundColor(.accentColor))
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .onTapGesture {
                openSystemSettings()
            }
    }

    private func openSystemSettings() {
        guard let url = permissionType.systemSettingsURL else { return }
        NSWorkspace.shared.open(url)
    }

    @ViewBuilder
    private var stepTwoView: some View {
        let isEnabled = systemPermissionState == .authorized
        let requiresRestart = systemPermissionState == .alreadyDenied || systemPermissionState == .denied

        HStack(spacing: 12) {
            stepIndicator(step: 2, isActive: isEnabled)

            if requiresRestart {
                Text(UserText.permissionRestartApp)
                    .font(.system(size: 13))
                    .foregroundColor(Color(designSystemColor: .textSecondary))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 36)
            } else {
                HStack(spacing: 8) {
                    Button(action: onAlwaysDeny) {
                        Text(UserText.permissionPopupNeverAllowButton)
                            .font(.system(size: 13))
                            .foregroundColor(isEnabled ? Color(designSystemColor: .textPrimary) : Color(designSystemColor: .textSecondary))
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(isEnabled ? Color(designSystemColor: .controlsFillPrimary) : Color(designSystemColor: .controlsFillSecondary))
                            .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(!isEnabled)
                    .accessibilityIdentifier("PermissionAuthorizationSwiftUIView.neverAllowButton")

                    Button(action: onAlwaysAllow) {
                        Text(UserText.permissionPopupAlwaysAllowButton)
                            .font(.system(size: 13))
                            .foregroundColor(isEnabled ? Color(designSystemColor: .textPrimary) : Color(designSystemColor: .textSecondary))
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(isEnabled ? Color(designSystemColor: .controlsFillPrimary) : Color(designSystemColor: .controlsFillSecondary))
                            .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(!isEnabled)
                    .accessibilityIdentifier("PermissionAuthorizationSwiftUIView.alwaysAllowButton")
                }
            }
        }
    }

    private func stepIndicator(step: Int, isActive: Bool) -> some View {
        ZStack {
            if isActive {
                Circle()
                    .fill(Color.primary)
                    .frame(width: 28, height: 28)
            } else {
                Circle()
                    .stroke(Color.secondary.opacity(0.4), lineWidth: 1)
                    .frame(width: 28, height: 28)
            }

            Text("\(step)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(isActive ? Color(NSColor.windowBackgroundColor) : Color.secondary.opacity(0.6))
        }
    }

    private func requestSystemPermission() {
        systemPermissionState = .waiting

        authorizationCancellable = systemPermissionManager.requestAuthorization(for: permissionType.asPermissionType) { state in
            DispatchQueue.main.async {
                switch state {
                case .authorized:
                    systemPermissionState = .authorized
                case .denied, .restricted, .systemDisabled:
                    systemPermissionState = .denied
                case .notDetermined:
                    systemPermissionState = .initial
                }
            }
        }
    }

    // MARK: - Standard Permission View

    private var standardPermissionView: some View {
        VStack(spacing: 20) {
            Text(promptText)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.top, 16)

            HStack(spacing: 12) {
                Button(action: denyAction) {
                    Text(denyButtonTitle)
                        .font(.system(size: 13))
                        .foregroundColor(Color(designSystemColor: .textPrimary))
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(Color(designSystemColor: .controlsFillPrimary))
                        .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityIdentifier("PermissionAuthorizationSwiftUIView.denyButton")

                Button(action: allowAction) {
                    Text(allowButtonTitle)
                        .font(.system(size: 13))
                        .foregroundColor(Color(designSystemColor: .textPrimary))
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(Color(designSystemColor: .controlsFillPrimary))
                        .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityIdentifier("PermissionAuthorizationSwiftUIView.allowButton")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .frame(width: 360)
        .background(Color(designSystemColor: .containerFillPrimary))
    }
}

// MARK: - Convenience Initializer

extension PermissionAuthorizationSwiftUIView {
    init(
        domain: String,
        permissionType: PermissionAuthorizationType,
        onDeny: @escaping () -> Void,
        onAlwaysDeny: @escaping () -> Void,
        onAllow: @escaping () -> Void,
        onAlwaysAllow: @escaping () -> Void
    ) {
        self.domain = domain
        self.permissionType = permissionType
        self.onDeny = onDeny
        self.onAlwaysDeny = onAlwaysDeny
        self.onAllow = onAllow
        self.onAlwaysAllow = onAlwaysAllow
        self.systemPermissionManager = SystemPermissionManager()
    }
}

// MARK: - PermissionType UI Extensions

extension PermissionType {

    /// Whether this permission type requires a two-step authorization flow (system permission first, then website permission)
    var requiresSystemPermission: Bool {
        switch self {
        case .geolocation:
            return true
        case .camera, .microphone, .popups, .externalScheme:
            return false
        }
    }

    /// Text shown when system permission was previously disabled (prefix before link)
    var systemPermissionDisabledText: String {
        switch self {
        case .geolocation:
            return UserText.permissionSystemLocationDisabled
        case .camera, .microphone, .popups, .externalScheme:
            return ""
        }
    }

    /// Link text for opening System Settings
    var systemSettingsLinkText: String {
        switch self {
        case .geolocation:
            return UserText.permissionSystemSettingsLocation
        case .camera, .microphone, .popups, .externalScheme:
            return ""
        }
    }

    /// URL to open the relevant System Settings pane
    var systemSettingsURL: URL? {
        switch self {
        case .geolocation:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")
        case .camera, .microphone, .popups, .externalScheme:
            return nil
        }
    }
}

#if DEBUG
struct PermissionAuthorizationSwiftUIView_Previews: PreviewProvider {
    static var previews: some View {
        PermissionAuthorizationSwiftUIView(
            domain: "apple.com",
            permissionType: .geolocation,
            onDeny: {},
            onAlwaysDeny: {},
            onAllow: {},
            onAlwaysAllow: {}
        )
        .previewDisplayName("Geolocation - Two Step")

        PermissionAuthorizationSwiftUIView(
            domain: "apple.com",
            permissionType: .camera,
            onDeny: {},
            onAlwaysDeny: {},
            onAllow: {},
            onAlwaysAllow: {}
        )
        .previewDisplayName("Camera")

        PermissionAuthorizationSwiftUIView(
            domain: "apple.com",
            permissionType: .cameraAndMicrophone,
            onDeny: {},
            onAlwaysDeny: {},
            onAllow: {},
            onAlwaysAllow: {}
        )
        .previewDisplayName("Camera and Microphone")
    }
}
#endif

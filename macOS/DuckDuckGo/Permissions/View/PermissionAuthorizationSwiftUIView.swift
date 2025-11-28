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

import SwiftUI
import Combine

struct PermissionAuthorizationSwiftUIView: View {
    let domain: String
    let permissionType: PermissionType
    let onDeny: () -> Void
    let onAlwaysDeny: () -> Void
    let onAllow: () -> Void
    let onAlwaysAllow: () -> Void
    let systemPermissionManager: SystemPermissionManagerProtocol

    /// State for the system permission step in two-step geolocation flow
    enum SystemPermissionState {
        case initial
        case waiting
        case authorized
        case denied
    }

    @State private var systemPermissionState: SystemPermissionState = .initial
    @State private var authorizationCancellable: AnyCancellable?

    /// Whether to show the two-step UI (only for geolocation when system permission not granted)
    private var showsTwoStepUI: Bool {
        guard case .geolocation = permissionType else { return false }
        return systemPermissionManager.isGeolocationAuthorizationRequired || systemPermissionState != .initial
    }

    private var promptText: String {
        switch permissionType {
        case .geolocation:
            return String(format: UserText.permissionGeolocationPromptFormat, domain)
        case .camera, .microphone:
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

    var body: some View {
        if showsTwoStepUI {
            twoStepGeolocationView
        } else {
            standardPermissionView
        }
    }

    // MARK: - Two-Step Geolocation View

    private var twoStepGeolocationView: some View {
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
    }

    @ViewBuilder
    private var stepOneView: some View {
        HStack(spacing: 12) {
            stepIndicator(step: 1, isActive: systemPermissionState != .authorized)

            switch systemPermissionState {
            case .initial:
                Button(action: requestSystemPermission) {
                    Text(UserText.permissionSystemLocationEnable)
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(Color.accentColor)
                        .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityIdentifier("PermissionAuthorizationSwiftUIView.enableSystemLocationButton")

            case .waiting:
                Text(UserText.permissionSystemLocationWaiting)
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

                    Text(UserText.permissionSystemLocationEnabled)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(NSColor.systemGreen))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 36)

            case .denied:
                HStack(spacing: 8) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Color(NSColor.systemRed))
                        .font(.system(size: 20))

                    Text(UserText.permissionSystemLocationDenied)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(NSColor.systemRed))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 36)
            }
        }
    }

    @ViewBuilder
    private var stepTwoView: some View {
        let isEnabled = systemPermissionState == .authorized

        HStack(spacing: 12) {
            stepIndicator(step: 2, isActive: isEnabled)

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

        authorizationCancellable = systemPermissionManager.requestGeolocationAuthorization { state in
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
                Button(action: standardDenyAction) {
                    Text(standardDenyButtonTitle)
                        .font(.system(size: 13))
                        .foregroundColor(Color(designSystemColor: .textPrimary))
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(Color(designSystemColor: .controlsFillPrimary))
                        .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityIdentifier("PermissionAuthorizationSwiftUIView.denyButton")

                Button(action: standardAllowAction) {
                    Text(standardAllowButtonTitle)
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

    private var standardDenyButtonTitle: String {
        permissionType == .geolocation ? UserText.permissionPopupDenyButton : UserText.permissionPopupAlwaysDenyButton
    }

    private var standardAllowButtonTitle: String {
        permissionType == .geolocation ? UserText.permissionPopupAllowButton : UserText.permissionPopupAlwaysAllowButton
    }

    private var standardDenyAction: () -> Void {
        permissionType == .geolocation ? onDeny : onAlwaysDeny
    }

    private var standardAllowAction: () -> Void {
        permissionType == .geolocation ? onAllow : onAlwaysAllow
    }
}

// MARK: - Convenience Initializer

extension PermissionAuthorizationSwiftUIView {
    init(
        domain: String,
        permissionType: PermissionType,
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
        .previewDisplayName("Camera (Always Deny / Always Allow)")
    }
}
#endif

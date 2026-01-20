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
import DesignResourcesKitIcons
import PixelKit
import SwiftUI
import UserNotifications

// MARK: - PermissionAuthorizationType

/// UI-only permission type for the authorization SwiftUI view.
/// This handles the combined camera+microphone case without modifying the model layer.
enum PermissionAuthorizationType {
    case camera
    case microphone
    case cameraAndMicrophone
    case geolocation
    case popups
    case notification
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
            case .notification: self = .notification
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
        case .notification:
            return UserText.permissionNotification
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
        case .geolocation, .notification:
            return true
        case .camera, .microphone, .cameraAndMicrophone, .popups, .externalScheme:
            return false
        }
    }

    // MARK: - Two-Step UI Localized Strings

    /// Button text for enabling system permission (Step 1)
    var systemPermissionEnableText: String {
        switch self {
        case .geolocation:
            return UserText.permissionSystemLocationEnable
        case .notification:
            return UserText.permissionSystemNotificationEnable
        case .camera, .microphone, .cameraAndMicrophone, .popups, .externalScheme:
            return "" // Not used for these types
        }
    }

    /// Text shown while waiting for system permission response
    var systemPermissionWaitingText: String {
        switch self {
        case .geolocation:
            return UserText.permissionSystemLocationWaiting
        case .notification:
            return UserText.permissionSystemNotificationWaiting
        case .camera, .microphone, .cameraAndMicrophone, .popups, .externalScheme:
            return ""
        }
    }

    /// Text shown when system permission is granted
    var systemPermissionEnabledText: String {
        switch self {
        case .geolocation:
            return UserText.permissionSystemLocationEnabled
        case .notification:
            return UserText.permissionSystemNotificationEnabled
        case .camera, .microphone, .cameraAndMicrophone, .popups, .externalScheme:
            return ""
        }
    }

    /// Text shown when system permission was previously disabled (prefix before link)
    var systemPermissionDisabledText: String {
        switch self {
        case .geolocation:
            return UserText.permissionSystemLocationDisabled
        case .notification:
            return UserText.permissionPopoverSystemNotificationDisabled
        case .camera, .microphone, .cameraAndMicrophone, .popups, .externalScheme:
            return ""
        }
    }

    /// Text for standalone system-disabled view (includes newline after first sentence)
    var systemPermissionDisabledTextStandalone: String {
        switch self {
        case .geolocation:
            return systemPermissionDisabledText
        case .notification:
            return UserText.permissionPopoverSystemNotificationDisabledStandalone
        case .camera, .microphone, .cameraAndMicrophone, .popups, .externalScheme:
            return ""
        }
    }

    /// Link text for opening System Settings
    var systemSettingsLinkText: String {
        switch self {
        case .geolocation:
            return UserText.permissionSystemSettingsLocation
        case .notification:
            return UserText.permissionCenterSystemSettingsNotifications
        case .camera, .microphone, .cameraAndMicrophone, .popups, .externalScheme:
            return ""
        }
    }

    /// URL to open the relevant System Settings pane
    var systemSettingsURL: URL? {
        switch self {
        case .geolocation:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")
        case .notification:
            return URL(string: "x-apple.systempreferences:com.apple.preference.notifications")
        case .camera, .microphone, .cameraAndMicrophone, .popups, .externalScheme:
            return nil
        }
    }

    /// URL to learn more about this permission type (for help pages)
    var learnMoreURL: URL? {
        switch self {
        case .geolocation:
            return URL(string: "https://help.duckduckgo.com/privacy/device-location-services")
        case .camera, .microphone, .cameraAndMicrophone, .popups, .notification, .externalScheme:
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
        case .notification: return .notification
        case .externalScheme(let scheme): return .externalScheme(scheme: scheme)
        }
    }
}

// MARK: - PermissionAuthorizationSwiftUIView

struct PermissionAuthorizationSwiftUIView: View {
    let domain: String
    let permissionType: PermissionAuthorizationType
    let showsTwoStepUI: Bool
    let isSystemPermissionDisabled: Bool
    let onDeny: () -> Void
    let onAllow: () -> Void
    let onDismiss: () -> Void
    let onLearnMore: (() -> Void)?
    let systemPermissionManager: SystemPermissionManagerProtocol

    /// State for the system permission step in two-step flow
    enum SystemPermissionState {
        case initial
        case waiting
        case authorized
        case denied
        /// Permission was already denied/restricted/disabled before showing the UI
        case alreadyDenied

        /// Whether the system permission request has completed with a result.
        /// Mirrors Apple's `UNAuthorizationStatus.notDetermined` terminology.
        var isDetermined: Bool {
            switch self {
            case .authorized, .denied, .alreadyDenied: return true
            case .initial, .waiting: return false
            }
        }
    }

    @State private var systemPermissionState: SystemPermissionState = .initial
    @State private var authorizationCancellable: AnyCancellable?
    @State private var appActiveCancellable: AnyCancellable?

    private let stepIndicatorSize: CGFloat = 32

    private var promptText: String {
        switch permissionType {
        case .geolocation:
            return String(format: UserText.permissionGeolocationPromptFormat, domain)
        case .camera, .microphone, .cameraAndMicrophone:
            return String(format: UserText.devicePermissionAuthorizationFormat, domain, permissionType.localizedDescription.lowercased())
        case .popups:
            return String(format: UserText.popupWindowsPermissionAuthorizationFormat, domain, permissionType.localizedDescription.lowercased())
        case .notification:
            return String(format: UserText.notificationPermissionAuthorizationFormat, domain)
        case .externalScheme:
            if domain.isEmpty {
                return String(format: UserText.externalSchemePermissionAuthorizationNoDomainFormat, permissionType.localizedDescription)
            } else {
                return String(format: UserText.externalSchemePermissionAuthorizationFormat, domain, permissionType.localizedDescription)
            }
        }
    }

    // MARK: - Body

    var body: some View {
        if isSystemPermissionDisabled {
            systemDisabledPermissionView
        } else if showsTwoStepUI {
            twoStepPermissionView
        } else {
            standardPermissionView
        }
    }

    // MARK: - Two-Step Permission View

    private var twoStepPermissionView: some View {
        VStack(spacing: 20) {
            // Prompt text
            Text(promptText)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            // Steps group
            VStack(spacing: 16) {
                // Step 1: System permission
                stepOneView

                // Divider between steps
                Rectangle()
                    .fill(Color(designSystemColor: .surfaceDecorationPrimary))
                    .frame(height: 1)
                    .cornerRadius(100)

                // Step 2: Website permission
                stepTwoView

                // Learn more link (for geolocation)
                if permissionType.learnMoreURL != nil {
                    learnMoreView
                }
            }
        }
        .padding(.top, 20)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .frame(width: 360)
        .background(Color(designSystemColor: .surfaceSecondary))
        .onAppear {
            initializeSystemPermissionState()
            subscribeToAppActiveNotification()
        }
        .onDisappear {
            appActiveCancellable?.cancel()
            appActiveCancellable = nil
        }
    }

    /// Check if system permission was already denied before showing the UI
    private func initializeSystemPermissionState() {
        guard systemPermissionState == .initial else { return }

        Task { @MainActor in
            let authState = await systemPermissionManager.authorizationState(for: permissionType.asPermissionType)
            switch authState {
            case .denied, .restricted, .systemDisabled:
                systemPermissionState = .alreadyDenied
            case .authorized:
                systemPermissionState = .authorized
            case .notDetermined:
                break // Keep initial state - will show "Enable" button
            }
        }
    }

    /// Subscribe to app becoming active to re-check system permission state
    /// This allows the UI to update when user returns from System Settings
    private func subscribeToAppActiveNotification() {
        appActiveCancellable = NotificationCenter.default
            .publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [systemPermissionManager, permissionType] _ in
                recheckSystemPermissionState(
                    manager: systemPermissionManager,
                    permissionType: permissionType
                )
            }
    }

    /// Re-check system permission state when app becomes active
    /// Updates UI if user enabled permission in System Settings
    private func recheckSystemPermissionState(
        manager: SystemPermissionManagerProtocol,
        permissionType: PermissionAuthorizationType
    ) {
        // Only re-check if we were in a denied state
        guard systemPermissionState == .alreadyDenied || systemPermissionState == .denied else { return }

        Task { @MainActor in
            let authState = await manager.authorizationState(for: permissionType.asPermissionType)
            switch authState {
            case .authorized:
                // User granted permission in System Settings
                systemPermissionState = .authorized
            case .notDetermined:
                // Location Services was re-enabled but app permission not yet requested
                // Transition to initial state to show "Enable Location" button
                systemPermissionState = .initial
            case .denied, .restricted, .systemDisabled:
                // Still in a denied state, no change needed
                break
            }
        }
    }

    /// Subscribe to app becoming active to dismiss when system permission is granted
    /// Used by systemDisabledPermissionView when app permission is "always allow" but system is disabled
    private func subscribeToAppActiveNotificationForDismissal() {
        appActiveCancellable = NotificationCenter.default
            .publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [systemPermissionManager, permissionType, onAllow, onDismiss] _ in
                Task { @MainActor in
                    let authState = await systemPermissionManager.authorizationState(for: permissionType.asPermissionType)
                    switch authState {
                    case .denied, .restricted, .systemDisabled:
                        break
                    case .authorized:
                        onAllow()
                    case .notDetermined:
                        onDismiss()
                    }
                }
            }
    }

    @ViewBuilder
    private var stepOneView: some View {
        HStack(spacing: 12) {
            stepIndicator(step: 1, isActive: !systemPermissionState.isDetermined, isCompleted: systemPermissionState == .authorized)

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
                Text(permissionType.systemPermissionEnabledText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color(designSystemColor: .textSuccess))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 36)

            case .alreadyDenied, .denied:
                systemPermissionDisabledView
            }
        }
    }

    /// View shown when system permission was already denied - displays link to System Settings
    private var systemPermissionDisabledView: some View {
        SystemPermissionWarningView(
            prefixText: permissionType.systemPermissionDisabledText,
            linkText: permissionType.systemSettingsLinkText
        ) {
            openSystemSettings()
        }
    }

    private func openSystemSettings() {
        guard let url = permissionType.systemSettingsURL else { return }
        PixelKit.fire(PermissionPixel.systemPreferencesOpened(permissionType: permissionType.asPermissionType))
        NSWorkspace.shared.open(url)
    }

    @ViewBuilder
    private var stepTwoView: some View {
        let isEnabled = systemPermissionState.isDetermined

        HStack(spacing: 12) {
            stepIndicator(step: 2, isActive: isEnabled)

            HStack(spacing: 8) {
                Button(action: onDeny) {
                    Text(UserText.permissionPopupDenyButton)
                        .font(.system(size: 13))
                        .foregroundColor(isEnabled ? Color(designSystemColor: .textPrimary) : Color(designSystemColor: .textSecondary))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(isEnabled ? Color(designSystemColor: .controlsFillPrimary) : Color(designSystemColor: .controlsFillSecondary))
                        .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(!isEnabled)
                .accessibilityIdentifier("PermissionAuthorizationSwiftUIView.denyButton")

                Button(action: onAllow) {
                    Text(UserText.permissionPopupAllowButton)
                        .font(.system(size: 13))
                        .foregroundColor(isEnabled ? Color(designSystemColor: .textPrimary) : Color(designSystemColor: .textSecondary))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(isEnabled ? Color(designSystemColor: .controlsFillPrimary) : Color(designSystemColor: .controlsFillSecondary))
                        .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(!isEnabled)
                .accessibilityIdentifier("PermissionAuthorizationSwiftUIView.allowButton")
            }
        }
    }

    private func stepIndicator(step: Int, isActive: Bool, isCompleted: Bool = false) -> some View {
        ZStack {
            if isCompleted {
                // Completed state: green checkmark
                ZStack {
                    Circle()
                        .fill(Color(designSystemColor: .textSuccess))
                        .frame(width: stepIndicatorSize, height: stepIndicatorSize)

                    Image(nsImage: DesignSystemImages.Glyphs.Size12.check)
                        .foregroundColor(.white)
                }
            } else if isActive {
                // Active state: filled circle with number
                Circle()
                    .fill(Color.primary)
                    .frame(width: stepIndicatorSize, height: stepIndicatorSize)
                Text("\(step)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(NSColor.windowBackgroundColor))
            } else {
                // Inactive state: outlined circle with number
                Circle()
                    .stroke(Color.secondary.opacity(0.4), lineWidth: 1)
                    .frame(width: stepIndicatorSize, height: stepIndicatorSize)
                Text("\(step)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color.secondary.opacity(0.6))
            }
        }
    }

    // MARK: - Learn More Link View

    @ViewBuilder
    private var learnMoreView: some View {
        Button(action: {
            onLearnMore?()
        }) {
            Text(UserText.permissionPopupLearnMoreLink)
                .font(.system(size: 13))
                .foregroundColor(Color(designSystemColor: .textLink))
        }
        .buttonStyle(PlainButtonStyle())
        .cursor(.pointingHand)
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

    // MARK: - System Disabled Permission View

    private var systemDisabledPermissionView: some View {
        VStack(spacing: 20) {
            Text(promptText)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

        (Text(permissionType.systemPermissionDisabledTextStandalone)
            .font(.system(size: 12))
            .foregroundColor(Color(designSystemColor: .textSecondary))
        + Text(" ")
        + Text(permissionType.systemSettingsLinkText)
            .font(.system(size: 12))
            .foregroundColor(Color(designSystemColor: .textLink)))
            .lineSpacing(6)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .cursor(.pointingHand)
            .onTapGesture {
                openSystemSettings()
            }
        }
        .padding(16)
        .frame(width: 360)
        .background(Color(designSystemColor: .surfaceSecondary))
        .onAppear {
            subscribeToAppActiveNotificationForDismissal()
        }
        .onDisappear {
            appActiveCancellable?.cancel()
            appActiveCancellable = nil
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

            HStack(spacing: 8) {
                Button(action: onDeny) {
                    Text(UserText.permissionPopupDenyButton)
                        .font(.system(size: 13))
                        .foregroundColor(Color(designSystemColor: .textPrimary))
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(Color(designSystemColor: .controlsFillPrimary))
                        .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityIdentifier("PermissionAuthorizationSwiftUIView.denyButton")

                Button(action: onAllow) {
                    Text(UserText.permissionPopupAllowButton)
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
            .padding(.bottom, permissionType.learnMoreURL != nil ? 0 : 16)

            // Learn more link (for geolocation)
            if permissionType.learnMoreURL != nil {
                learnMoreView
                    .padding(.bottom, 16)
            }
        }
        .frame(width: 360)
        .background(Color(designSystemColor: .surfaceSecondary))
    }
}

// MARK: - Convenience Initializer

extension PermissionAuthorizationSwiftUIView {
    init(
        domain: String,
        permissionType: PermissionAuthorizationType,
        showsTwoStepUI: Bool = false,
        isSystemPermissionDisabled: Bool = false,
        onDeny: @escaping () -> Void,
        onAllow: @escaping () -> Void,
        onDismiss: @escaping () -> Void,
        onLearnMore: (() -> Void)? = nil
    ) {
        self.domain = domain
        self.permissionType = permissionType
        self.showsTwoStepUI = showsTwoStepUI
        self.isSystemPermissionDisabled = isSystemPermissionDisabled
        self.onDeny = onDeny
        self.onAllow = onAllow
        self.onDismiss = onDismiss
        self.onLearnMore = onLearnMore
        self.systemPermissionManager = SystemPermissionManager()
    }
}

// MARK: - PermissionType UI Extensions

extension PermissionType {

    /// Text shown when system permission was previously disabled (prefix before link)
    var systemPermissionDisabledText: String {
        switch self {
        case .geolocation:
            return UserText.permissionSystemLocationDisabled
        case .notification:
            return UserText.permissionCenterSystemNotificationDisabled
        case .camera, .microphone, .popups, .externalScheme:
            return ""
        }
    }

    /// Link text for opening System Settings
    var systemSettingsLinkText: String {
        switch self {
        case .geolocation:
            return UserText.permissionSystemSettingsLocation
        case .notification:
            return UserText.permissionCenterSystemSettingsNotifications
        case .camera, .microphone, .popups, .externalScheme:
            return ""
        }
    }

    /// URL to open the relevant System Settings pane
    var systemSettingsURL: URL? {
        switch self {
        case .geolocation:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")
        case .notification:
            return URL(string: "x-apple.systempreferences:com.apple.preference.notifications")
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
            showsTwoStepUI: true,
            onDeny: {},
            onAllow: {},
            onDismiss: {}
        )
        .previewDisplayName("Geolocation - Two Step")

        PermissionAuthorizationSwiftUIView(
            domain: "apple.com",
            permissionType: .camera,
            onDeny: {},
            onAllow: {},
            onDismiss: {}
        )
        .previewDisplayName("Camera")

        PermissionAuthorizationSwiftUIView(
            domain: "apple.com",
            permissionType: .cameraAndMicrophone,
            onDeny: {},
            onAllow: {},
            onDismiss: {}
        )
        .previewDisplayName("Camera and Microphone")
    }
}
#endif

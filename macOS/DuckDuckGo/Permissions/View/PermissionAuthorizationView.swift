//
//  PermissionAuthorizationView.swift
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

import DesignResourcesKitIcons
import SwiftUI

struct PermissionAuthorizationView: View {
    private enum Constants {
        static let width: CGFloat = 252
        static let buttonHeight: CGFloat = 32
        static let closeButtonSize: CGFloat = 20
        static let systemPermissionIconSize: CGFloat = 24
        static let systemPermissionButtonHeight: CGFloat = 28
        static let systemPermissionCornerRadius: CGFloat = 16
        static let systemPermissionBackground = Color(red: 1, green: 230 / 255, blue: 153 / 255).opacity(0.32)
    }

    @ObservedObject
    var viewModel: PermissionAuthorizationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 20) {
                Text(viewModel.viewState.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: { viewModel.send(action: .dismiss) }) {
                    Image(nsImage: DesignSystemImages.Glyphs.Size16.close)
                        .frame(width: Constants.closeButtonSize, height: Constants.closeButtonSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(HoverHighlightButtonStyle(cornerRadius: 4))
                .padding(2)
                .accessibilityLabel(UserText.close)
                .accessibilityIdentifier(viewModel.viewState.closeButtonAccessibilityIdentifier)
            }

            if let step = viewModel.viewState.systemPermissionStep {
                systemPermissionStep(step)
            } else {
                VStack(spacing: 8) {
                    ForEach(viewModel.viewState.decisionButtons) { button in
                        decisionButton(button)
                    }
                }

                if let learnMore = viewModel.viewState.learnMore {
                    Button(action: { viewModel.send(action: .learnMore) }) {
                        Text(learnMore.title)
                            .font(.system(size: 13))
                            .foregroundColor(Color(designSystemColor: .accentTextPrimary))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .cursor(.pointingHand)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(20)
        .frame(width: Constants.width)
        .background(Color(designSystemColor: .surfaceSecondary))
        .onAppear {
            viewModel.send(action: .onAppear)
        }
    }

    private func decisionButton(_ button: PermissionAuthorizationViewState.DecisionButton) -> some View {
        Button(action: { viewModel.send(action: button.action) }) {
            Text(button.title)
                .font(.system(size: 13))
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .frame(maxWidth: .infinity)
                .frame(height: Constants.buttonHeight)
                .background(Color(designSystemColor: .controlsFillPrimary))
                .clipShape(Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityIdentifier(button.accessibilityIdentifier)
    }

    private func systemPermissionStep(_ step: PermissionAuthorizationViewState.SystemPermissionStep) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(nsImage: DesignSystemImages.Glyphs.Size24.exclamationRecolorableInvert)
                .resizable()
                .frame(width: Constants.systemPermissionIconSize, height: Constants.systemPermissionIconSize)

            VStack(alignment: .leading, spacing: 16) {
                Text(step.message)
                    .font(.system(size: 12))
                    .foregroundColor(Color(designSystemColor: .textSecondary))
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                systemPermissionButton(step)
            }
            .padding(.top, 4)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: Constants.systemPermissionCornerRadius)
                .fill(Constants.systemPermissionBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: Constants.systemPermissionCornerRadius)
                        .strokeBorder(Constants.systemPermissionBackground, lineWidth: 1)
                )
        )
    }

    private func systemPermissionButton(_ step: PermissionAuthorizationViewState.SystemPermissionStep) -> some View {
        let isEnabled = step.buttonAction != nil

        return Button(action: {
            guard let action = step.buttonAction else { return }
            viewModel.send(action: action)
        }) {
            Text(step.buttonTitle)
                .font(.system(size: 13))
                .foregroundColor(isEnabled ? Color(designSystemColor: .accentContentPrimary) : Color(designSystemColor: .textPrimary))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: Constants.systemPermissionButtonHeight)
                .background(systemPermissionButtonBackground(isEnabled: isEnabled))
                .contentShape(Capsule())
                .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!isEnabled)
        .accessibilityIdentifier(step.buttonAccessibilityIdentifier)
    }

    /// Accent capsule when enabled; a standard macOS button (raised fill, hairline border, soft shadow) while waiting.
    @ViewBuilder
    private func systemPermissionButtonBackground(isEnabled: Bool) -> some View {
        if isEnabled {
            Capsule()
                .fill(Color(designSystemColor: .accentPrimary))
        } else {
            Capsule()
                .fill(Color(designSystemColor: .controlsRaisedFillPrimary))
                .overlay(Capsule().strokeBorder(Color.black.opacity(0.1), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.2), radius: 0.5, y: 1)
        }
    }
}

#if DEBUG
@MainActor
private func previewViewModel(
    domain: String,
    permissions: [PermissionType],
    initialState: PermissionAuthorizationViewState = .init()
) -> PermissionAuthorizationViewModel {
    let query = PermissionAuthorizationQuery(domain: domain, url: URL(string: "https://\(domain)"), permissions: permissions) { _ in }
    return PermissionAuthorizationViewModel(
        initialState: initialState,
        query: query,
        systemPermissionManager: SystemPermissionManager(notificationService: UserNotificationAuthorizationService()),
        pixelFiring: nil,
        openURL: { _ in },
        finish: {}
    )
}

#Preview("Notifications - Light") {
    PermissionAuthorizationView(viewModel: previewViewModel(domain: "microsoft.ai", permissions: [.notification]))
        .preferredColorScheme(.light)
}

#Preview("Location - Dark") {
    PermissionAuthorizationView(viewModel: previewViewModel(domain: "maps.example.com", permissions: [.geolocation]))
        .preferredColorScheme(.dark)
}

#Preview("Camera and Microphone") {
    PermissionAuthorizationView(viewModel: previewViewModel(domain: "meet.example.com", permissions: [.camera, .microphone]))
}

#Preview("Notifications - Request system permission") {
    PermissionAuthorizationView(viewModel: previewViewModel(
        domain: "microsoft.ai",
        permissions: [.notification],
        initialState: .init(systemPermissionStep: .init(
            phase: .request,
            message: UserText.websitePermissionsPromptSystemNotificationsRequired,
            buttonTitle: UserText.websitePermissionsPromptRequestSystemPermission
        ))
    ))
}

#Preview("Notifications - Waiting for system permission") {
    PermissionAuthorizationView(viewModel: previewViewModel(
        domain: "microsoft.ai",
        permissions: [.notification],
        initialState: .init(systemPermissionStep: .init(
            phase: .waiting,
            message: UserText.websitePermissionsPromptSystemNotificationsRequired,
            buttonTitle: UserText.websitePermissionsPromptWaitingForSystemPermission
        ))
    ))
}

#Preview("Notifications - Open System Settings") {
    PermissionAuthorizationView(viewModel: previewViewModel(
        domain: "microsoft.ai",
        permissions: [.notification],
        initialState: .init(systemPermissionStep: .init(
            phase: .openSettings,
            message: UserText.websitePermissionsPromptSystemNotificationsOff,
            buttonTitle: UserText.websitePermissionsPromptOpenSystemSettings
        ))
    ))
}

#Preview("Location - Request system permission") {
    PermissionAuthorizationView(viewModel: previewViewModel(
        domain: "maps.example.com",
        permissions: [.geolocation],
        initialState: .init(systemPermissionStep: .init(
            phase: .request,
            message: UserText.websitePermissionsPromptSystemLocationRequired,
            buttonTitle: UserText.websitePermissionsPromptRequestSystemPermission
        ))
    ))
}

#Preview("Location - Open System Settings - Dark") {
    PermissionAuthorizationView(viewModel: previewViewModel(
        domain: "maps.example.com",
        permissions: [.geolocation],
        initialState: .init(systemPermissionStep: .init(
            phase: .openSettings,
            message: UserText.websitePermissionsPromptSystemLocationOff,
            buttonTitle: UserText.websitePermissionsPromptOpenSystemSettings
        ))
    ))
    .preferredColorScheme(.dark)
}
#endif

//
//  PermissionCenterView.swift
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
import SwiftUI

// MARK: - PermissionCenterView

struct PermissionCenterView: View {

    @ObservedObject var viewModel: PermissionCenterViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Text(String(format: UserText.permissionCenterTitle, viewModel.domain))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

            // Permission rows
            VStack(spacing: 0) {
                ForEach(viewModel.permissionItems) { item in
                    PermissionRowView(
                        item: item,
                        onDecisionChanged: { decision in
                            viewModel.setDecision(decision, for: item.permissionType)
                        },
                        onRemove: {
                            viewModel.removePermission(item.permissionType)
                        }
                    )

                    if item.id != viewModel.permissionItems.last?.id {
                        Divider()
                            .padding(.leading, 52)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .frame(width: 360)
        .background(Color(designSystemColor: .containerFillPrimary))
    }
}

// MARK: - PermissionRowView

struct PermissionRowView: View {

    let item: PermissionCenterItem
    let onDecisionChanged: (PersistedPermissionDecision) -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main row
            HStack(spacing: 12) {
                // Icon
                permissionIcon
                    .frame(width: 24, height: 24)

                // Permission name
                Text(item.displayName)
                    .font(.system(size: 13))
                    .foregroundColor(Color(designSystemColor: .textPrimary))

                Spacer()

                // Decision dropdown
                decisionPicker

                // Remove button
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color(designSystemColor: .textSecondary))
                }
                .buttonStyle(PlainButtonStyle())
                .frame(width: 20, height: 20)
            }
            .padding(.vertical, 12)

            // System disabled warning (if applicable)
            if item.isSystemDisabled {
                systemDisabledWarning
                    .padding(.leading, 36)
                    .padding(.bottom, 8)
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var permissionIcon: some View {
        switch item.permissionType {
        case .camera:
            Image(systemName: "video.fill")
                .foregroundColor(Color(NSColor.systemRed))
        case .microphone:
            Image(systemName: "mic.fill")
                .foregroundColor(Color(designSystemColor: .textSecondary))
        case .geolocation:
            Image(systemName: "location.fill")
                .foregroundColor(Color(designSystemColor: .textSecondary))
        case .popups:
            Image(systemName: "rectangle.on.rectangle")
                .foregroundColor(Color(designSystemColor: .textSecondary))
        case .externalScheme:
            Image(systemName: "arrow.up.forward.app")
                .foregroundColor(Color(designSystemColor: .textSecondary))
        }
    }

    private var decisionPicker: some View {
        Menu {
            Button(UserText.permissionCenterAlwaysAsk) {
                onDecisionChanged(.ask)
            }
            Button(UserText.permissionCenterAlwaysAllow) {
                onDecisionChanged(.allow)
            }
            Button(UserText.permissionCenterNeverAllow) {
                onDecisionChanged(.deny)
            }
        } label: {
            HStack(spacing: 4) {
                Text(decisionDisplayText)
                    .font(.system(size: 12))
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(Color(designSystemColor: .textSecondary))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(designSystemColor: .controlsFillSecondary))
            .cornerRadius(6)
        }
        .menuStyle(BorderlessButtonMenuStyle())
        .fixedSize()
    }

    private var decisionDisplayText: String {
        switch item.decision {
        case .ask:
            return UserText.permissionCenterAlwaysAsk
        case .allow:
            return UserText.permissionCenterAlwaysAllow
        case .deny:
            return UserText.permissionCenterNeverAllow
        }
    }

    private var systemDisabledWarning: some View {
        HStack(spacing: 0) {
            Text(item.permissionType.systemPermissionDisabledText)
                .font(.system(size: 11))
                .foregroundColor(Color(designSystemColor: .textPrimary))

            Button(action: openSystemSettings) {
                Text(item.permissionType.systemSettingsLinkText)
                    .font(.system(size: 11))
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.2))
        .cornerRadius(6)
    }

    private func openSystemSettings() {
        guard let url = item.permissionType.systemSettingsURL else { return }
        NSWorkspace.shared.open(url)
    }
}


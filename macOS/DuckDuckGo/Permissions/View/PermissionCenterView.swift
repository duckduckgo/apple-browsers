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
                .padding(.leading, 20)
                .padding(.trailing, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

            // Permission rows in a rounded container
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
                    }
                }
            }
            .background(Color(designSystemColor: .containerFillTertiary))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
            )
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

    @State private var isRemoveButtonHovered = false
    @State private var currentDecision: PersistedPermissionDecision

    init(item: PermissionCenterItem, onDecisionChanged: @escaping (PersistedPermissionDecision) -> Void, onRemove: @escaping () -> Void) {
        self.item = item
        self.onDecisionChanged = onDecisionChanged
        self.onRemove = onRemove
        self._currentDecision = State(initialValue: item.decision)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main row
            HStack(spacing: 8) {
                // Icon
                permissionIcon
                    .frame(width: 24, height: 24)

                // Permission name
                Text(item.displayName)
                    .font(.system(size: 13))
                    .foregroundColor(Color(designSystemColor: .textPrimary))

                Spacer()

                // Decision dropdown
                decisionPopUpButton

                // Remove button with hover effect
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color(designSystemColor: .textSecondary))
                }
                .buttonStyle(PlainButtonStyle())
                .frame(width: 16, height: 16)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(isRemoveButtonHovered ? Color(.buttonMouseOver) : Color.clear)
                )
                .onHover { hovering in
                    isRemoveButtonHovered = hovering
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, 12)
            .padding(.vertical, 12)

            // External scheme description (if applicable)
            if let description = item.externalSchemeDescription {
                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(Color(designSystemColor: .textSecondary))
                    .padding(.leading, 44)
                    .padding(.trailing, 12)
                    .padding(.bottom, 12)
            }

            // System disabled warning (if applicable)
            if item.isSystemDisabled {
                systemDisabledWarning
                    .padding(.leading, 44)
                    .padding(.trailing, 12)
                    .padding(.bottom, 12)
            }
        }
        .background(item.isSystemDisabled ? Color(.permissionWarningBackground) : Color.clear)
        .onChange(of: currentDecision) { newValue in
            onDecisionChanged(newValue)
        }
        .onChange(of: item.decision) { newValue in
            // Sync local state when the item's decision changes from external source
            if currentDecision != newValue {
                currentDecision = newValue
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

    private var decisionPopUpButton: some View {
        NSPopUpButtonView(selection: $currentDecision) {
            let button = NSPopUpButton()
            button.bezelStyle = .accessoryBarAction
            button.isBordered = true
            button.setContentHuggingPriority(.defaultHigh, for: .horizontal)

            for decision in [PersistedPermissionDecision.ask, .allow, .deny] {
                let item = button.menu?.addItem(withTitle: decisionDisplayText(for: decision), action: nil, keyEquivalent: "")
                item?.representedObject = decision
            }

            return button
        }
        .fixedSize()
    }

    private func decisionDisplayText(for decision: PersistedPermissionDecision) -> String {
        switch decision {
        case .ask:
            return UserText.permissionCenterAlwaysAsk
        case .allow:
            return UserText.permissionCenterAlwaysAllow
        case .deny:
            return UserText.permissionCenterNeverAllow
        }
    }

    private var systemDisabledWarning: some View {
        (Text(item.permissionType.systemPermissionDisabledText)
            .font(.system(size: 12))
            .foregroundColor(Color(designSystemColor: .textSecondary))
        + Text(item.permissionType.systemSettingsLinkText)
            .font(.system(size: 12))
            .foregroundColor(.accentColor))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onTapGesture {
                openSystemSettings()
            }
    }

    private func openSystemSettings() {
        guard let url = item.permissionType.systemSettingsURL else { return }
        NSWorkspace.shared.open(url)
    }
}

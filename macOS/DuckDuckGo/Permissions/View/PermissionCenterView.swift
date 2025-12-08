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
import DesignResourcesKitIcons
import SwiftUI

// MARK: - PermissionCenterView

struct PermissionCenterView: View {

    @ObservedObject var viewModel: PermissionCenterViewModel

    /// Use a wider popover when popup or external app permissions are present due to longer content
    private var popoverWidth: CGFloat {
        let hasPopups = viewModel.permissionItems.contains { $0.permissionType == .popups }
        let hasExternalApps = viewModel.permissionItems.contains { $0.isGroupedExternalApps }
        if hasPopups {
            return 450
        } else if hasExternalApps {
            return 380
        }
        return 360
    }

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
                    switch item.permissionType {
                    case .popups:
                        PopupPermissionRowView(
                            item: item,
                            currentDecision: viewModel.currentPopupDecision(),
                            showAllowForThisVisitOption: viewModel.showAllowPopupsForThisVisitOption,
                            onDecisionChanged: { decision in
                                viewModel.setPopupDecision(decision)
                            },
                            onOpenPopup: { popup in
                                viewModel.openBlockedPopup(popup)
                            },
                            onRemove: {
                                viewModel.removePermission(item.permissionType)
                            }
                        )
                    case .externalScheme:
                        ExternalAppsPermissionRowView(
                            item: item,
                            onDecisionChanged: { scheme, decision in
                                viewModel.setExternalSchemeDecision(decision, for: scheme)
                            },
                            onRemoveScheme: { scheme in
                                viewModel.removeExternalScheme(scheme)
                            }
                        )
                    default:
                        PermissionRowView(
                            item: item,
                            onDecisionChanged: { decision in
                                viewModel.setDecision(decision, for: item.permissionType)
                            },
                            onRemove: {
                                viewModel.removePermission(item.permissionType)
                            }
                        )
                    }

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
        .frame(width: popoverWidth)
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
        let iconColor: Color = item.isInUse ? Color(NSColor.systemRed) : Color(designSystemColor: .textSecondary)

        switch item.permissionType {
        case .camera:
            // Use filled icon if allowed or in use, outline otherwise
            if item.isAllowed {
                Image(nsImage: DesignSystemImages.Glyphs.Size16.permissionCameraSolid)
                    .foregroundColor(iconColor)
            } else {
                Image(nsImage: DesignSystemImages.Glyphs.Size16.permissionCamera)
                    .foregroundColor(iconColor)
            }
        case .microphone:
            if item.isAllowed {
                Image(nsImage: DesignSystemImages.Glyphs.Size16.permissionMicrophoneSolid)
                    .foregroundColor(iconColor)
            } else {
                Image(nsImage: DesignSystemImages.Glyphs.Size16.permissionMicrophone)
                    .foregroundColor(iconColor)
            }
        case .geolocation:
            if item.isAllowed {
                Image(nsImage: DesignSystemImages.Glyphs.Size16.permissionsLocationSolid)
                    .foregroundColor(iconColor)
            } else {
                Image(nsImage: DesignSystemImages.Glyphs.Size16.permissionsLocation)
                    .foregroundColor(iconColor)
            }
        case .popups:
            // Popups only have outline icon
            Image(nsImage: DesignSystemImages.Glyphs.Size16.popupBlocked)
                .foregroundColor(iconColor)
        case .externalScheme:
            // External apps only have outline icon
            Image(nsImage: DesignSystemImages.Glyphs.Size16.openIn)
                .foregroundColor(iconColor)
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
            .cursor(.pointingHand)
            .onTapGesture {
                openSystemSettings()
            }
    }

    private func openSystemSettings() {
        guard let url = item.permissionType.systemSettingsURL else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - PopupPermissionRowView

struct PopupPermissionRowView: View {

    let item: PermissionCenterItem
    let currentDecision: PopupDecision
    let showAllowForThisVisitOption: Bool
    let onDecisionChanged: (PopupDecision) -> Void
    let onOpenPopup: (BlockedPopup) -> Void
    let onRemove: () -> Void

    @State private var isRemoveButtonHovered = false
    @State private var selectedDecision: PopupDecision

    init(
        item: PermissionCenterItem,
        currentDecision: PopupDecision,
        showAllowForThisVisitOption: Bool,
        onDecisionChanged: @escaping (PopupDecision) -> Void,
        onOpenPopup: @escaping (BlockedPopup) -> Void,
        onRemove: @escaping () -> Void
    ) {
        self.item = item
        self.currentDecision = currentDecision
        self.showAllowForThisVisitOption = showAllowForThisVisitOption
        self.onDecisionChanged = onDecisionChanged
        self.onOpenPopup = onOpenPopup
        self.onRemove = onRemove
        // If "allow for this visit" option is not available and that was the current decision, fall back to notify
        let effectiveDecision = (!showAllowForThisVisitOption && currentDecision == .allowForThisVisit) ? .notify : currentDecision
        self._selectedDecision = State(initialValue: effectiveDecision)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main row with icon, name, dropdown, and remove button
            HStack(spacing: 8) {
                // Icon
                Image(nsImage: DesignSystemImages.Glyphs.Size16.popupBlocked)
                    .foregroundColor(Color(designSystemColor: .textSecondary))
                    .frame(width: 24, height: 24)

                // Permission name
                Text(item.displayName)
                    .font(.system(size: 13))
                    .foregroundColor(Color(designSystemColor: .textPrimary))

                Spacer()

                // Decision dropdown
                popupDecisionPopUpButton

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

            // Blocked popups section (if any)
            if !item.blockedPopups.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    // Header: "Blocked X pop-ups"
                    if let headerText = item.blockedPopupsHeaderText {
                        Text(headerText)
                            .font(.system(size: 11))
                            .foregroundColor(Color(designSystemColor: .textSecondary))
                            .padding(.bottom, 4)
                    }

                    // Links to open each blocked popup (only show non-empty URLs)
                    // Empty/about: URLs are grouped and handled via "Only allow for this visit"
                    ForEach(item.visibleBlockedPopups) { popup in
                        Button(action: { onOpenPopup(popup) }) {
                            Text(popupLinkText(for: popup))
                                .font(.system(size: 12))
                                .foregroundColor(.accentColor)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .cursor(.pointingHand)
                    }
                }
                .padding(.leading, 44)
                .padding(.trailing, 12)
                .padding(.bottom, 12)
            }
        }
        .onChange(of: selectedDecision) { newValue in
            onDecisionChanged(newValue)
        }
    }

    private func popupLinkText(for popup: BlockedPopup) -> String {
        let urlString = popup.displayURL.isEmpty ? "" : popup.displayURL
        return String(format: UserText.permissionPopupOpenFormat, urlString)
    }

    private var popupDecisionPopUpButton: some View {
        NSPopUpButtonView(selection: $selectedDecision) {
            let button = NSPopUpButton()
            button.bezelStyle = .accessoryBarAction
            button.isBordered = true
            button.setContentHuggingPriority(.defaultHigh, for: .horizontal)

            var decisions: [(PopupDecision, String)] = []

            // Only show "allow for this visit" when feature flags are enabled
            if showAllowForThisVisitOption {
                decisions.append((.allowForThisVisit, UserText.permissionPopupAllowPopupsForPage))
            }

            decisions.append((.notify, UserText.privacyDashboardPopupsAlwaysAsk))
            decisions.append((.alwaysAllow, UserText.privacyDashboardPermissionAlwaysAllow))

            for (decision, title) in decisions {
                let menuItem = button.menu?.addItem(withTitle: title, action: nil, keyEquivalent: "")
                menuItem?.representedObject = decision
            }

            return button
        }
        .fixedSize()
    }
}

// MARK: - ExternalAppsPermissionRowView

struct ExternalAppsPermissionRowView: View {

    let item: PermissionCenterItem
    let onDecisionChanged: (String, PersistedPermissionDecision) -> Void
    let onRemoveScheme: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row with icon and "External apps" title
            HStack(spacing: 8) {
                // Icon
                Image(nsImage: DesignSystemImages.Glyphs.Size16.openIn)
                    .foregroundColor(Color(designSystemColor: .textSecondary))
                    .frame(width: 24, height: 24)

                // Permission name
                Text(item.displayName)
                    .font(.system(size: 13))
                    .foregroundColor(Color(designSystemColor: .textPrimary))

                Spacer()
            }
            .padding(.leading, 12)
            .padding(.trailing, 12)
            .padding(.vertical, 12)

            // Individual scheme rows
            ForEach(item.externalSchemes) { schemeInfo in
                ExternalSchemeRowView(
                    schemeInfo: schemeInfo,
                    onDecisionChanged: { decision in
                        onDecisionChanged(schemeInfo.scheme, decision)
                    },
                    onRemove: {
                        onRemoveScheme(schemeInfo.scheme)
                    }
                )
            }
            .padding(.bottom, 6)
        }
    }
}

// MARK: - ExternalSchemeRowView

struct ExternalSchemeRowView: View {

    let schemeInfo: ExternalSchemeInfo
    let onDecisionChanged: (PersistedPermissionDecision) -> Void
    let onRemove: () -> Void

    @State private var isRemoveButtonHovered = false
    @State private var currentDecision: PersistedPermissionDecision

    init(
        schemeInfo: ExternalSchemeInfo,
        onDecisionChanged: @escaping (PersistedPermissionDecision) -> Void,
        onRemove: @escaping () -> Void
    ) {
        self.schemeInfo = schemeInfo
        self.onDecisionChanged = onDecisionChanged
        self.onRemove = onRemove
        self._currentDecision = State(initialValue: schemeInfo.decision)
    }

    var body: some View {
        HStack(spacing: 8) {
            // Description text
            Text(schemeInfo.displayText)
                .font(.system(size: 12))
                .foregroundColor(Color(designSystemColor: .textSecondary))

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
        .padding(.leading, 44)
        .padding(.trailing, 12)
        .padding(.bottom, 6)
        .onChange(of: currentDecision) { newValue in
            onDecisionChanged(newValue)
        }
        .onChange(of: schemeInfo.decision) { newValue in
            if currentDecision != newValue {
                currentDecision = newValue
            }
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
}

//
//  PermissionReminderDialogView.swift
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

import DesignResourcesKit
import DuckUI
import SwiftUI

public struct PermissionReminderDialogView: View {

    private enum Constants {
        static let cardWidth: CGFloat = 288
        static let contentHorizontalPadding: CGFloat = 8
        static let contentTopPadding: CGFloat = 8
        static let contentSpacing: CGFloat = 10
        static let copySpacing: CGFloat = 8
        static let actionsTopPadding: CGFloat = 24
        static let buttonSpacing: CGFloat = 10
    }

    private let viewModel: PermissionReminderDialogViewModel
    let onAction: (PermissionReminderDialogAction) -> Void

    @AccessibilityFocusState private var isTitleFocused: Bool

    public init(viewModel: PermissionReminderDialogViewModel,
                onAction: @escaping (PermissionReminderDialogAction) -> Void) {
        self.viewModel = viewModel
        self.onAction = onAction
    }

    public var body: some View {
        PermissionDialogCard(width: Constants.cardWidth,
                             accessibilityIdentifier: "SitePermissions.Reminder",
                             onDismiss: { onAction(.cancel) }) {
            VStack(spacing: Constants.contentSpacing) {
                VStack(alignment: .leading, spacing: Constants.copySpacing) {
                    Text(viewModel.title)
                        .font(.headline)
                        .foregroundColor(Color(designSystemColor: .textPrimary))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityFocused($isTitleFocused)
                        .accessibilityIdentifier("SitePermissions.Reminder.Title")

                    Text(viewModel.body)
                        .font(.body)
                        .foregroundColor(Color(designSystemColor: .textPrimary))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Constants.contentHorizontalPadding)
                .padding(.top, Constants.contentTopPadding)

                VStack(spacing: Constants.buttonSpacing) {
                    ForEach(viewModel.actions) { item in
                        actionButton(for: item)
                    }
                }
                .padding(.top, Constants.actionsTopPadding)
            }
        }
        .onAppear {
            isTitleFocused = true
        }
    }

    @ViewBuilder
    private func actionButton(for item: PermissionReminderDialogViewModel.ActionItem) -> some View {
        switch item.style {
        case .primary:
            Button {
                onAction(item.action)
            } label: {
                PermissionDialogButtonLabel(title: item.title)
            }
            .buttonStyle(PrimaryButtonStyle(isFreeform: true))
            .accessibilityIdentifier(accessibilityIdentifier(for: item.action))
        case .secondary:
            Button {
                onAction(item.action)
            } label: {
                PermissionDialogButtonLabel(title: item.title)
            }
            .buttonStyle(SecondaryFillButtonStyle(isFreeform: true))
            .accessibilityIdentifier(accessibilityIdentifier(for: item.action))
        }
    }

    private func accessibilityIdentifier(for action: PermissionReminderDialogAction) -> String {
        switch action {
        case .changePermissions:
            return "SitePermissions.Reminder.ChangePermissions"
        case .hideVoiceSearch:
            return "SitePermissions.Reminder.HideVoiceSearch"
        case .cancel:
            return "SitePermissions.Reminder.Cancel"
        }
    }

}

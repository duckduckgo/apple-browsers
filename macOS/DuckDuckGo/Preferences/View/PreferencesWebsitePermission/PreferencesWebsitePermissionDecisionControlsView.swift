//
//  PreferencesWebsitePermissionDecisionControlsView.swift
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
import DesignResourcesKitIcons
import SwiftUI

struct PreferencesWebsitePermissionDecisionControlsView: View {
    private enum Constants {
        static let minimumDropdownWidth: CGFloat = 124
        static let removeButtonSize: CGFloat = 16
        static let controlSpacing: CGFloat = 12
    }

    let decision: PersistedPermissionDecision
    let availableDecisions: [PersistedPermissionDecision]
    let accessibilityIdentifier: String
    let domain: String
    let permissionType: PermissionType
    let permissionTitle: String?
    let onDecisionChanged: (PersistedPermissionDecision) -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: Constants.controlSpacing) {
            picker
            removeButton
        }
    }

    private var picker: some View {
        Picker(selection: Binding(
            get: { decision },
            set: onDecisionChanged
        ), label: EmptyView()) {
            ForEach(availableDecisions, id: \.self) { decision in
                Text(decision.websitePermissionsTitle).tag(decision)
            }
        }
        .labelsHidden()
        .fixedSize()
        .frame(minWidth: Constants.minimumDropdownWidth)
        .accessibilityLabel(
            String(format: UserText.websitePermissionsDecisionAccessibilityLabel, domain) + ", " + permissionAccessibilityDescription)
        .accessibilityIdentifier("\(accessibilityIdentifier).Decision")
    }

    private var removeButton: some View {
        Button(action: onRemove) {
            Image(nsImage: DesignSystemImages.Glyphs.Size16.closeSmall)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: Constants.removeButtonSize, height: Constants.removeButtonSize)
                .foregroundColor(Color(designSystemColor: .iconsTertiary))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            String(format: UserText.websitePermissionsRemovePermissionAccessibilityLabel, domain) + ", " + permissionAccessibilityDescription)
        .accessibilityIdentifier("\(accessibilityIdentifier).Remove")
    }

    private var permissionAccessibilityDescription: String {
        if case .externalScheme(let scheme) = permissionType {
            return [permissionTitle, "\(scheme)://"].compactMap { $0 }.joined(separator: ", ")
        }
        return permissionTitle ?? permissionType.localizedDescription
    }
}

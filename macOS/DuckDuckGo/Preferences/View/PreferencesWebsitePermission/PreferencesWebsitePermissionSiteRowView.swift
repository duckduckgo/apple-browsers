//
//  PreferencesWebsitePermissionSiteRowView.swift
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

import Foundation
import DesignResourcesKit
import DesignResourcesKitIcons
import SwiftUI

struct PreferencesWebsitePermissionSiteRowView: View {
    private enum Constants {
        static let rowHeight: CGFloat = 56
        static let rowPadding: CGFloat = 16
        static let faviconSize: CGFloat = 16
    }

    let domain: String
    let faviconURL: URL?
    let permissionTitle: String?
    let decision: PersistedPermissionDecision
    let availableDecisions: [PersistedPermissionDecision]
    let accessibilityIdentifier: String
    let onDecisionChanged: (PersistedPermissionDecision) -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            FaviconView(url: faviconURL, size: Constants.faviconSize)

            Text(domain)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 10)

            if let permissionTitle {
                Text(permissionTitle)
                    .font(.system(size: 13))
                    .foregroundColor(Color(designSystemColor: .textSecondary))
                    .lineLimit(1)
            }

            PreferencesWebsitePermissionDecisionControlsView(
                decision: decision,
                availableDecisions: availableDecisions,
                accessibilityIdentifier: accessibilityIdentifier,
                domain: domain,
                onDecisionChanged: onDecisionChanged,
                onRemove: onRemove
            )
        }
        .padding(Constants.rowPadding)
        .frame(height: Constants.rowHeight)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

struct WebsitePermissionListSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Color(designSystemColor: .containerBorderPrimary))
            .frame(height: 1)
    }
}

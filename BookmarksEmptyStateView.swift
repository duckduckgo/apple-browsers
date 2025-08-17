//
//  BookmarksEmptyStateView.swift
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

import SwiftUIExtensions

struct BookmarksEmptyStateView: View {
    let content: BookmarksEmptyStateContent
    let onImportClicked: () -> Void
    let onSyncClicked: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Spacer()

            if let image = content.image {
                Image(nsImage: image)
                    .frame(width: 128, height: 96)
                    .accessibilityIdentifier(BookmarksEmptyStateContent.imageAccessibilityIdentifier)
            }

            VStack(spacing: 8) {
                Text(content.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color(.labelColor))
                    .multilineTextAlignment(.center)
                    .frame(width: 300)
                    .accessibilityIdentifier(BookmarksEmptyStateContent.titleAccessibilityIdentifier)

                Text(content.description)
                    .font(.system(size: 13))
                    .foregroundColor(Color(.labelColor))
                    .multilineTextAlignment(.center)
                    .frame(width: 300)
                    .accessibilityIdentifier(BookmarksEmptyStateContent.descriptionAccessibilityIdentifier)
            }

            VStack(spacing: 10) {
                if !content.shouldHideImportButton {
                    Button("Import Bookmarks") {
                        onImportClicked()
                    }
                    .buttonStyle(DefaultActionButtonStyle(enabled: true))
                }
                if !content.shouldHideSyncButton {
                    Button("Sync Bookmarks") {
                        onSyncClicked()
                    }
                    .buttonStyle(StandardButtonStyle())
                }
            }

            Spacer()
        }
        .frame(width: 300, height: 383)
    }
}

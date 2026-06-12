//
//  SuggestionRowView.swift
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
import DesignResourcesKitIcons
import SwiftUI

/// Renders one unified suggestion row. Layout/typography mirror the legacy
/// `SuggestionListItem` so output matches the shipped autocomplete row.
struct SuggestionRowView: View {

    let row: SuggestionRow
    let isAddressBarAtBottom: Bool
    let onTapAhead: () -> Void
    let onDelete: () -> Void
    let onFire: () -> Void

    private enum Metrics {
        static let iconSize: CGFloat = 24
        static let iconTextSpacing: CGFloat = 10
        static let trailingPadding: CGFloat = 20
        static let accessoryLeadingPadding: CGFloat = 4
        static let subtitleMinHeight: CGFloat = 21
    }

    var body: some View {
        HStack(spacing: 0) {
            Image(uiImage: row.icon.glyph)
                .resizable()
                .frame(width: Metrics.iconSize, height: Metrics.iconSize)
                .tintIfAvailable(Color(designSystemColor: .icons))

            VStack(alignment: .leading, spacing: 0) {
                Group {
                    // Can't use dax modifiers because they are not typed for Text
                    if let query = row.query, row.title.hasPrefix(query) {
                        Text(query)
                            .font(Font(uiFont: UIFont.daxBodyRegular()))
                            .foregroundColor(Color(designSystemColor: .textPrimary))
                        + Text(row.title.dropping(prefix: query))
                            .font(Font(uiFont: UIFont.daxBodyBold()))
                            .foregroundColor(Color(designSystemColor: .textPrimary))
                    } else {
                        Text(row.title)
                            .font(Font(uiFont: UIFont.daxBodyRegular()))
                            .foregroundColor(Color(designSystemColor: .textPrimary))
                    }
                }
                .lineLimit(1)

                if let subtitle = row.subtitle {
                    Text(subtitle)
                        .daxFootnoteRegular()
                        .foregroundColor(Color(designSystemColor: .textSecondary))
                        .lineLimit(1)
                        .frame(minHeight: Metrics.subtitleMinHeight)
                }
            }
            .padding(.leading, Metrics.iconTextSpacing)

            if row.accessory == .none {
                Spacer(minLength: Metrics.trailingPadding)
            } else {
                Spacer()
                accessory
                    .padding(.leading, Metrics.accessoryLeadingPadding)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var accessory: some View {
        switch row.accessory {
        case .tapAhead:
            Image(uiImage: isAddressBarAtBottom
                  ? DesignSystemImages.Glyphs.Size16.arrowCircleDownLeft
                  : DesignSystemImages.Glyphs.Size16.arrowCircleUpLeft)
                .tintIfAvailable(Color(designSystemColor: .iconsSecondary))
                .highPriorityGesture(TapGesture().onEnded { onTapAhead() })
        case .delete:
            deletionButton(glyph: DesignSystemImages.Glyphs.Size16.clear,
                           accessibilityID: "Autocomplete.Suggestions.ListItem.DeleteButton",
                           action: onDelete)
        case .fire:
            deletionButton(glyph: DesignSystemImages.Glyphs.Size16.fire,
                           accessibilityID: "Autocomplete.Suggestions.ListItem.FireDeleteButton",
                           action: onFire)
        case .none:
            EmptyView()
        }
    }

    private func deletionButton(glyph: UIImage, accessibilityID: String, action: @escaping () -> Void) -> some View {
        Image(uiImage: glyph)
            .tintIfAvailable(Color(designSystemColor: .iconsSecondary))
            .highPriorityGesture(TapGesture().onEnded { action() })
            .accessibilityIdentifier(accessibilityID)
            .accessibilityLabel(UserText.actionDelete)
    }
}

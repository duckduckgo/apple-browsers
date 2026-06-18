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
    /// When the row is keyboard-/pointer-highlighted, content recolors to the on-accent color for contrast
    /// against the filled highlight background (matches the legacy autocomplete row).
    let isSelected: Bool
    let onTapAhead: () -> Void
    let onDelete: () -> Void
    /// Carries the 🔥 button's global frame so the iPad popover can anchor the delete confirmation to it.
    let onFire: (CGRect) -> Void

    @State private var fireButtonFrame: CGRect = .zero

    private var titleColor: Color { Color(designSystemColor: isSelected ? .accentContentPrimary : .textPrimary) }
    private var subtitleColor: Color { Color(designSystemColor: isSelected ? .accentContentPrimary : .textSecondary) }
    private var iconColor: Color { Color(designSystemColor: isSelected ? .accentContentPrimary : .icons) }
    private var accessoryColor: Color { Color(designSystemColor: isSelected ? .accentContentPrimary : .iconsSecondary) }

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
                .tintIfAvailable(iconColor)

            VStack(alignment: .leading, spacing: 0) {
                Group {
                    // Can't use dax modifiers because they are not typed for Text
                    if let query = row.query, row.title.hasPrefix(query) {
                        Text(query)
                            .font(Font(uiFont: UIFont.daxBodyRegular()))
                            .foregroundColor(titleColor)
                        + Text(row.title.dropping(prefix: query))
                            .font(Font(uiFont: UIFont.daxBodyBold()))
                            .foregroundColor(titleColor)
                    } else {
                        Text(row.title)
                            .font(Font(uiFont: UIFont.daxBodyRegular()))
                            .foregroundColor(titleColor)
                    }
                }
                .lineLimit(1)

                if let subtitle = row.subtitle {
                    Text(subtitle)
                        .daxFootnoteRegular()
                        .foregroundColor(subtitleColor)
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
                .tintIfAvailable(accessoryColor)
                .highPriorityGesture(TapGesture().onEnded { onTapAhead() })
        case .delete:
            deletionButton(glyph: DesignSystemImages.Glyphs.Size16.clear,
                           accessibilityID: "Autocomplete.Suggestions.ListItem.DeleteButton",
                           action: onDelete)
        case .fire:
            Image(uiImage: DesignSystemImages.Glyphs.Size16.fire)
                .tintIfAvailable(accessoryColor)
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: FireButtonFrameKey.self, value: proxy.frame(in: .global))
                })
                .onPreferenceChange(FireButtonFrameKey.self) { fireButtonFrame = $0 }
                .highPriorityGesture(TapGesture().onEnded { onFire(fireButtonFrame) })
                .accessibilityIdentifier("Autocomplete.Suggestions.ListItem.FireDeleteButton")
                .accessibilityLabel(UserText.actionDelete)
        case .none:
            EmptyView()
        }
    }

    private func deletionButton(glyph: UIImage, accessibilityID: String, action: @escaping () -> Void) -> some View {
        Image(uiImage: glyph)
            .tintIfAvailable(accessoryColor)
            .highPriorityGesture(TapGesture().onEnded { action() })
            .accessibilityIdentifier(accessibilityID)
            .accessibilityLabel(UserText.actionDelete)
    }
}

private struct FireButtonFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

//
//  SuggestionRowView.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//  Licensed under the Apache License, Version 2.0.
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
            Image(uiImage: DesignSystemImages.Glyphs.Size16.clear)
                .tintIfAvailable(Color(designSystemColor: .iconsSecondary))
                .highPriorityGesture(TapGesture().onEnded { onDelete() })
                .accessibilityIdentifier("Autocomplete.Suggestions.ListItem.DeleteButton")
                .accessibilityLabel(UserText.actionDelete)
        case .none:
            EmptyView()
        }
    }
}

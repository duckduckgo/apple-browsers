//
//  SheetCardRow.swift
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

#if os(iOS)

import SwiftUI
import DesignResourcesKit
import DesignResourcesKitIcons

/// A tappable RMF sheet row (Figma `.Sheet part / Card row`): a 48pt leading icon, a title, supporting
/// text and a chevron, on a 16pt rounded surface. The content is a ``CardItem``.
public struct SheetCardRow: View {

    enum Metrics {
        static let padding: CGFloat = 16
        static let iconSpacing: CGFloat = 16
        static let titleTextSpacing: CGFloat = 8
        static let cornerRadius: CGFloat = 16
        static let chevronSize: CGFloat = 16
        static let chevronTopPadding: CGFloat = 12
        static let chevronLeadingSpacing: CGFloat = 8
    }

    private let icon: Graphic?
    private let title: String
    private let text: String?
    private let action: () -> Void

    public init(icon: Graphic?, title: String, text: String?, action: @escaping () -> Void) {
        self.icon = icon
        self.title = title
        self.text = text
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: Metrics.chevronLeadingSpacing) {
                CardItem(
                    icon: icon.map { CardItemIcon(position: .leading, visual: $0, size: .size48, spacing: Metrics.iconSpacing) },
                    title: CardItemText(title, font: CardItemFont(RMFSheetTypography.headline)),
                    text: text.map { CardItemText($0, font: CardItemFont(RMFSheetTypography.subheadRegular)) },
                    titleTextSpacing: Metrics.titleTextSpacing
                )

                Image(uiImage: DesignSystemImages.Glyphs.Size16.chevronRight)
                    .renderingMode(.template)
                    .foregroundColor(Color(designSystemColor: .iconsSecondary))
                    .frame(width: Metrics.chevronSize, height: Metrics.chevronSize)
                    .padding(.top, Metrics.chevronTopPadding)
                    .accessibilityHidden(true)
            }
            .padding(Metrics.padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: Metrics.cornerRadius))
        }
        .buttonStyle(SheetCardRowButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

private struct SheetCardRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: SheetCardRow.Metrics.cornerRadius)
                    .fill(Color(designSystemColor: configuration.isPressed ? .controlsFillPrimary : .surface))
            )
            .overlay(
                RoundedRectangle(cornerRadius: SheetCardRow.Metrics.cornerRadius)
                    .strokeBorder(Color(designSystemColor: .containerBorderPrimary), lineWidth: 1)
            )
    }
}

#if DEBUG

#Preview("Card row") {
    SheetCardRow(icon: .image(Image(systemName: "flame.fill")),
                 title: "Browse With Fire Tabs",
                 text: "Use Fire Tabs to isolate your browsing from normal tabs and browse without saving local history.") {}
        .padding(18)
}

#Preview("Card row Dark") {
    SheetCardRow(icon: .image(Image(systemName: "flame.fill")),
                 title: "Title",
                 text: "Description") {}
        .padding(18)
        .background(Color(designSystemColor: .surfaceTertiary))
        .preferredColorScheme(.dark)
}

#endif

#endif

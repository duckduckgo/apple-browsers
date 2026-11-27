//
//  SheetCardList.swift
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

/// One row in a ``SheetCardList``.
public struct SheetCardListItem {
    public let icon: Graphic?
    public let title: String
    public let text: String?

    public init(icon: Graphic?, title: String, text: String?) {
        self.icon = icon
        self.title = title
        self.text = text
    }
}

/// Tappable What's New style rows (Figma `Sheet slot / Card list`), stacked with a 12pt gap (Figma node 15:158).
public struct SheetCardList: View {

    static let spacing: CGFloat = 12

    private let items: [SheetCardListItem]
    private let onSelect: (Int) -> Void

    /// - Parameters:
    ///   - items: The rows, in display order. The template expects up to 3.
    ///   - onSelect: Called with the index of the tapped row.
    public init(items: [SheetCardListItem], onSelect: @escaping (Int) -> Void) {
        self.items = items
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(spacing: Self.spacing) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                SheetCardRow(icon: item.icon, title: item.title, text: item.text) {
                    onSelect(index)
                }
            }
        }
    }
}

#if DEBUG

extension SheetCardListItem {
    static let previewWhatsNew: [SheetCardListItem] = [
        SheetCardListItem(icon: .image(Image(systemName: "bubble.left.and.bubble.right.fill")),
                          title: "Sync Duck.ai Chats Across Devices",
                          text: "Sync your chats across desktop and mobile by visiting Duck.ai Settings > Sync & Backup."),
        SheetCardListItem(icon: .image(Image(systemName: "flame.fill")),
                          title: "Browse With Fire Tabs",
                          text: "Use Fire Tabs to isolate your browsing from normal tabs and browse without saving local history."),
        SheetCardListItem(icon: .image(Image(systemName: "plus.circle.fill")),
                          title: "Explore More Subscription Options",
                          text: "Pick from two plans: Plus (for all four protections) or Pro (for more powerful AI functionality)."),
    ]
}

#Preview("Card list") {
    SheetCardList(items: SheetCardListItem.previewWhatsNew) { _ in }
        .padding(18)
}

#Preview("Card list Dark") {
    SheetCardList(items: SheetCardListItem.previewWhatsNew) { _ in }
        .padding(18)
        .background(Color(designSystemColor: .surfaceTertiary))
        .preferredColorScheme(.dark)
}

#endif

#endif

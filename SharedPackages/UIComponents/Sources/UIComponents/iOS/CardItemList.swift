//
//  CardItemList.swift
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

// MARK: - Card Item List

/// Lays out a `[CardItem]` as a vertical list with a hairline divider between adjacent rows (a single
/// item, or none, draws no divider). Drop it into any card or container that hosts a list of rows.
public struct CardItemList: View {
    /// Per-row content padding — insets each row's content horizontally and vertically so the padding
    /// becomes part of the row's tap target (and the vertical inset sets the gap between adjacent rows).
    /// `.zero` (the default) leaves rows unpadded and flush.
    public struct ContentInset {
        public let horizontal: CGFloat
        public let vertical: CGFloat

        public init(horizontal: CGFloat, vertical: CGFloat) {
            self.horizontal = horizontal
            self.vertical = vertical
        }

        public static let zero = ContentInset(horizontal: 0, vertical: 0)
    }

    private let items: [CardItem]
    private let dividerLeadingInset: CGFloat?
    private let contentInset: ContentInset
    private let onSelect: (Int) -> (() -> Void)?

    /// - Parameters:
    ///   - items: The rows, top to bottom.
    ///   - dividerLeadingInset: How far each divider clears the icon column so it starts under the text.
    ///     `contentInset.horizontal` is added automatically and mirrored on the trailing edge. Defaults to
    ///     `nil`, deriving the inset from each row's leading icon column; pass an explicit value (`0` for a
    ///     full-width divider) to override.
    ///   - contentInset: Per-row padding that becomes part of each row's tap target (and sets the gap
    ///     between rows via its vertical inset). Defaults to `.zero`.
    ///   - onSelect: Returns the tap action for the row at a given index, or `nil` if the row isn't
    ///     selectable. Defaults to non-interactive for every row.
    public init(_ items: [CardItem],
                dividerLeadingInset: CGFloat? = nil,
                contentInset: ContentInset = .zero,
                onSelect: @escaping (Int) -> (() -> Void)? = { _ in nil }) {
        self.items = items
        self.dividerLeadingInset = dividerLeadingInset
        self.contentInset = contentInset
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { entry in
                if entry.offset > 0 {
                    Color(designSystemColor: .lines)
                        .frame(height: 1)
                        .padding(.leading, contentInset.horizontal + (dividerLeadingInset ?? entry.element.leadingIconColumnWidth))
                        .padding(.trailing, contentInset.horizontal)
                }
                row(entry.element, at: entry.offset)
            }
        }
    }
}

// MARK: - Card Item List Layout

private extension CardItemList {
    @ViewBuilder
    func row(_ item: CardItem, at index: Int) -> some View {
        let padded = item
            .padding(.horizontal, contentInset.horizontal)
            .padding(.vertical, contentInset.vertical)
        if let action = onSelect(index) {
            Button(action: action) {
                padded.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            padded
        }
    }
}

// MARK: - Row Selection

public extension CardItemList {
    /// Builds a row-select handler for a `CardItemList` over `items` — `nil` for an out-of-bounds or
    /// non-selectable row, otherwise the tap action for that row's element.
    static func selectAction<Element>(over items: [Element],
                                      where isSelectable: @escaping (Element) -> Bool = { _ in true },
                                      perform action: @escaping (Element) -> Void) -> (Int) -> (() -> Void)? {
        { index in
            guard items.indices.contains(index), isSelectable(items[index]) else { return nil }
            return { action(items[index]) }
        }
    }
}

// MARK: - Previews

#if DEBUG

private struct CardItemListPreviewSamples: View {
    @State private var selection = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                CardItemList([
                    CardItem(
                        icon: CardItemIcon(position: .leading, visual: .image(Image(systemName: "lock.shield.fill"))),
                        title: CardItemText("VPN", font: .headline),
                        text: CardItemText("An extra layer of online protection.", font: .footnoteRegular),
                        trailing: .chevron(Color(designSystemColor: .iconsTertiary))),
                    CardItem(
                        icon: CardItemIcon(position: .leading, visual: .image(Image(systemName: "person.text.rectangle.fill"))),
                        title: CardItemText("Identity Theft Restoration", font: .headline),
                        text: CardItemText("If your identity is stolen, we'll help restore it.", font: .footnoteRegular),
                        trailing: .chevron(Color(designSystemColor: .iconsTertiary))),
                    CardItem(
                        icon: CardItemIcon(position: .leading, visual: .image(Image(systemName: "sparkles"))),
                        title: CardItemText("Advanced AI Models", font: .headline),
                        text: CardItemText("Private conversations with 3rd-party AI chat models.", font: .footnoteRegular),
                        trailing: .chevron(Color(designSystemColor: .iconsTertiary))),
                ], contentInset: .init(horizontal: 16, vertical: 12))

                CardItemList([
                    CardItem(
                        icon: CardItemIcon(position: .leadingColumn, visual: .image(Image(systemName: "brain")), size: .size24),
                        title: CardItemText("GPT-4o mini", font: .bodyRegular),
                        trailing: selection == 0 ? .checkmark(Color(designSystemColor: .accentPrimary)) : nil),
                    CardItem(
                        icon: CardItemIcon(position: .leadingColumn, visual: .image(Image(systemName: "cpu")), size: .size24),
                        title: CardItemText("Claude", font: .bodyRegular),
                        titleDetails: [CardItemText("· PLUS", font: .footnoteRegular)],
                        trailing: selection == 1 ? .checkmark(Color(designSystemColor: .accentPrimary)) : nil),
                ], contentInset: .init(horizontal: 16, vertical: 12), onSelect: { index in { selection = index } })

                CardItemList([
                    CardItem(
                        icon: CardItemIcon(position: .leadingColumn, visual: .image(Image(systemName: "checkmark.circle.fill")), size: .size24),
                        title: CardItemText("DuckDuckGo VPN", font: .subheadRegular)),
                ], contentInset: .init(horizontal: 16, vertical: 12))
            }
            .padding()
        }
        .background(Color(designSystemColor: .surfaceTertiary).ignoresSafeArea())
    }
}

#Preview("Light") {
    CardItemListPreviewSamples()
}

#Preview("Dark") {
    CardItemListPreviewSamples()
        .preferredColorScheme(.dark)
}

#Preview("Large Text") {
    CardItemListPreviewSamples()
        .dynamicTypeSize(.accessibility5)
}

#endif

#endif

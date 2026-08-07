//
//  SuggestionsListView.swift
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

import Combine
import DesignResourcesKit
import SwiftUI

/// The data-driven suggestion sections (the scrolling rows). The escape hatch + sync promo are
/// chrome rendered above this by `UnifiedSuggestionsView`. Replaces `DuckAISuggestionsViewController`'s table.
struct SuggestionsListView: View {

    @ObservedObject var viewModel: SuggestionsListViewModel
    let isAddressBarAtBottom: Bool
    var isFloatingPopover: Bool = false

    private enum Metrics {
        /// Per Figma: the list table sits 6pt below the top-positioned input's bottom margin.
        static let listTopInset: CGFloat = 6
        static let popoverVerticalInset: CGFloat = 12
        static let popoverSectionSpacing: CGFloat = 10
        /// Per Figma: single-line rows use 15pt top/bottom padding; rows with a subtitle use 14pt
        static let rowVerticalPaddingSingleLine: CGFloat = 15
        static let rowVerticalPaddingWithSubtitle: CGFloat = 14
        static let rowLeftInset: CGFloat = 12
        static let rowRightInset: CGFloat = 13
        /// List's horizontal content margin (cell edge). Reduced 8pt from the NTP's 24pt regularPadding
        /// to widen the cells in step with the narrower input card.
        static let listHorizontalContentMargin: CGFloat = 16
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(viewModel.sections) { section in
                    Section {
                        rows(for: section)
                    } header: {
                        sectionHeader(section.title)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .modifier(SectionSpacingModifier(isFloatingPopover: isFloatingPopover,
                                             popoverSpacing: Metrics.popoverSectionSpacing))
            // Replace insetGrouped's variable top margin with the design's list top inset (6pt below the
            // input on the top bar; 0 on the bottom bar, where the input sits below the list).
            .modifier(ListContentMarginsModifier(top: isFloatingPopover ? Metrics.popoverVerticalInset : (isAddressBarAtBottom ? 0 : Metrics.listTopInset),
                                                 bottom: isFloatingPopover ? Metrics.popoverVerticalInset : nil,
                                                 horizontal: Metrics.listHorizontalContentMargin))
            .hideScrollContentBackground()
            .background(Color(designSystemColor: .background))
            .scrollDismissesKeyboardIfAvailable()
            // Pointer (trackpad/mouse) leaving the list clears the hover highlight. Touch never fires onHover.
            .onHover { isHovering in
                if !isHovering { viewModel.selectedRowID = nil }
            }
            // Keep the keyboard-/pointer-highlighted row scrolled into view.
            .onReceive(viewModel.$selectedRowID) { id in
                guard let id else { return }
                withAnimation { proxy.scrollTo(id) }
            }
        }
    }

    @ViewBuilder
    private func rows(for section: SuggestionSection) -> some View {
        ForEach(section.rows) { row in
            Button {
                viewModel.selectRow(id: row.id)
            } label: {
                SuggestionRowView(
                    row: row,
                    isAddressBarAtBottom: isAddressBarAtBottom,
                    isSelected: row.id == viewModel.selectedRowID,
                    onTapAhead: { viewModel.tapAheadRow(id: row.id) },
                    onDelete: { viewModel.deleteRow(id: row.id) },
                    onFire: { frame in viewModel.fireDeleteRow(id: row.id, sourceRect: frame) })
            }
            .accessibilityIdentifier(row.accessibilityID)
            .listRowInsets(rowInsets(for: row))
            .listRowBackground(rowBackground(for: row))
            .modifier(SeparatorTrailingToContentModifier())
            // Pointer hover highlights the row, reusing the keyboard-selection highlight (matches the
            // legacy autocomplete). Touch never fires onHover, so this is pointer-only.
            .onHover { isHovering in
                if isHovering { viewModel.selectedRowID = row.id }
            }
        }
    }

    /// Highlights the hardware-keyboard-selected row (iPad popover); plain surface otherwise.
    /// `selectedRowID` stays nil on iPhone (no arrow-key navigation), so this is inert there.
    private func rowBackground(for row: SuggestionRow) -> Color {
        row.id == viewModel.selectedRowID
            ? Color(designSystemColor: .accentPrimary)
            : Color(designSystemColor: .surface)
    }

    /// Vertical padding per Figma; horizontal inset (on top of the list's content margin) keeps
    /// the rows aligned with the input's text + X clear button.
    private func rowInsets(for row: SuggestionRow) -> EdgeInsets {
        let vertical = row.subtitle == nil ? Metrics.rowVerticalPaddingSingleLine : Metrics.rowVerticalPaddingWithSubtitle
        let trailing = isFloatingPopover ? Metrics.rowLeftInset : Metrics.rowRightInset
        return EdgeInsets(top: vertical, leading: Metrics.rowLeftInset, bottom: vertical, trailing: trailing)
    }

    @ViewBuilder
    private func sectionHeader(_ title: String?) -> some View {
        if let title, !title.isEmpty {
            Text(title)
                .daxTitle3()
                .foregroundColor(Color(designSystemColor: .textPrimary))
        } else {
            EmptyView()
        }
    }
}

/// insetGrouped reserves a large variable top inset above the first section; replace it with the
/// design's `top` inset, and set the `horizontal` content margin (the cell edge) explicitly so the
/// rows align with the escape hatch and favorites grid in every orientation.
private struct ListContentMarginsModifier: ViewModifier {
    let top: CGFloat
    let bottom: CGFloat?
    let horizontal: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 17, *) {
            applyMargins(to: content)
        } else {
            content
        }
    }

    @available(iOS 17, *)
    @ViewBuilder
    private func applyMargins(to content: Content) -> some View {
        let base = content
            .contentMargins(.top, top, for: .scrollContent)
            .contentMargins(.horizontal, horizontal, for: .scrollContent)
        if let bottom {
            base.contentMargins(.bottom, bottom, for: .scrollContent)
        } else {
            base
        }
    }
}

private struct SectionSpacingModifier: ViewModifier {
    let isFloatingPopover: Bool
    let popoverSpacing: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 17, *) {
            if isFloatingPopover {
                content.listSectionSpacing(popoverSpacing)
            } else {
                content.listSectionSpacing(.compact)
            }
        } else {
            content
        }
    }
}

/// Pins the row separator's trailing end to the row content's trailing edge (the `rowRightInset`),
/// so the hairline ends the same distance from the cell's right edge as the content.
private struct SeparatorTrailingToContentModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16, *) {
            content.alignmentGuide(.listRowSeparatorTrailing) { $0[.trailing] }
        } else {
            content
        }
    }
}

private extension View {
    @ViewBuilder
    func scrollDismissesKeyboardIfAvailable() -> some View {
        if #available(iOS 16, *) { self.scrollDismissesKeyboard(.immediately) } else { self }
    }
}

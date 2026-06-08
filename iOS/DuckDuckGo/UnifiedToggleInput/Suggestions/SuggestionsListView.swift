//
//  SuggestionsListView.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//  Licensed under the Apache License, Version 2.0.
//

import DesignResourcesKit
import SwiftUI

/// The suggestions rows surface: an optional escape-hatch + sync-promo header
/// followed by the data-driven sections. Replaces `DuckAISuggestionsViewController`'s table.
struct SuggestionsListView: View {

    @ObservedObject var viewModel: SuggestionsListViewModel
    let isAddressBarAtBottom: Bool

    private enum Metrics {
        /// Per Figma: the list table sits 6pt below the top-positioned input's bottom margin.
        static let listTopInset: CGFloat = 6
    }

    var body: some View {
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
        .modifier(CompactSectionSpacingModifier())
        // Replace insetGrouped's variable top margin with the design's list top inset (6pt below the
        // input on the top bar; 0 on the bottom bar, where the input sits below the list).
        .modifier(ListTopContentMarginModifier(top: isAddressBarAtBottom ? 0 : Metrics.listTopInset))
        .modifier(HideScrollContentBackgroundModifier())
        .background(Color(designSystemColor: .background))
        .scrollDismissesKeyboardIfAvailable()
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
                    onTapAhead: { viewModel.tapAheadRow(id: row.id) },
                    onDelete: { viewModel.deleteRow(id: row.id) })
            }
            .listRowBackground(Color(designSystemColor: .surface))
        }
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
/// design's `top` inset, and pin the horizontal margin to the NTP's content margin (regularPadding,
/// 24) so the rows align with the escape hatch and favorites grid in every orientation.
private struct ListTopContentMarginModifier: ViewModifier {
    let top: CGFloat
    func body(content: Content) -> some View {
        if #available(iOS 17, *) {
            content
                .contentMargins(.top, top, for: .scrollContent)
                .contentMargins(.horizontal, 24, for: .scrollContent)
        } else {
            content
        }
    }
}

private struct HideScrollContentBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16, *) { content.scrollContentBackground(.hidden) } else { content }
    }
}

private struct CompactSectionSpacingModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17, *) { content.listSectionSpacing(.compact) } else { content }
    }
}

private extension View {
    @ViewBuilder
    func scrollDismissesKeyboardIfAvailable() -> some View {
        if #available(iOS 16, *) { self.scrollDismissesKeyboard(.immediately) } else { self }
    }
}

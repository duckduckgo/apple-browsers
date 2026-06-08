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
        // Trim insetGrouped's variable top margin so the first row sits tight below the input
        // (the escape hatch, when present, is spaced separately above the list by the parent).
        .modifier(TightTopContentMarginModifier())
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

/// insetGrouped reserves a large top inset above the first section; trim it so the first row sits
/// just below the input (matching legacy Search) rather than ~40pt down.
private struct TightTopContentMarginModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17, *) {
            content.contentMargins(.top, 0, for: .scrollContent)
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

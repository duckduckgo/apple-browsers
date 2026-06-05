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
    let header: AnyView?

    var body: some View {
        List {
            if let header {
                header
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
            }

            ForEach(viewModel.sections) { section in
                Section {
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
                        .listRowBackground(row.id == viewModel.selectedRowID
                            ? Color(designSystemColor: .accent)
                            : Color(designSystemColor: .surface))
                    }
                } header: {
                    sectionHeader(section.title)
                }
            }
        }
        .listStyle(.insetGrouped)
        .modifier(CompactSectionSpacingModifier())
        .modifier(HideScrollContentBackgroundModifier())
        .background(Color(designSystemColor: .background))
        .scrollDismissesKeyboardIfAvailable()
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

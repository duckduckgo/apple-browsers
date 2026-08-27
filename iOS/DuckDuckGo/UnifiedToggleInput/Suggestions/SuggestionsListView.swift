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

/// The data-driven suggestion sections (the scrolling rows), including optional Duck.ai chrome.
/// Replaces `DuckAISuggestionsViewController`'s table.
struct SuggestionsListView: View {

    @ObservedObject var viewModel: SuggestionsListViewModel
    let isAddressBarAtBottom: Bool
    var scrollContentInsetTop: CGFloat = 0
    var escapeHatch: EscapeHatchModel?
    var syncPromo: AnyView?
    var favoritesViewModel: FavoritesViewModel?
    var messagesModel: NewTabPageMessagesModel?
    var showsRestingContent = false
    var showsFavorites = false
    var showsSuggestionRows = true
    var animationModel: UnifiedSuggestionsAnimationModel
    var isFloatingPopover: Bool = false

    private enum Metrics {
        /// Per Figma: the list table sits 6pt below the top-positioned input's bottom margin.
        static let listTopInset: CGFloat = 6
        static let popoverVerticalInset: CGFloat = 12
        static let popoverSectionSpacing: CGFloat = 10
        static let embeddedHatchTopBarTopInset: CGFloat = 4
        static let embeddedHatchBottomBarTopInset: CGFloat = 10
        static let syncPromoBottomBarTopInset: CGFloat = 4
        static let scrollableChromeBottomInset: CGFloat = 16
        static let searchSectionSpacing: CGFloat = 26
        static let searchAfterHatchTopInset: CGFloat = searchSectionSpacing - scrollableChromeBottomInset
        static let duckAIAfterHatchTopInset: CGFloat = 4
        /// The focused RMF's 12pt shadow with its 4pt downward offset extends 8pt above and 16pt below the card.
        /// The bottom-bar layout's existing 10pt top inset already contains the upper shadow.
        static let messageShadowTopInset: CGFloat = 8
        static let messageShadowBottomInset: CGFloat = 16
        /// Search content starts at 16pt; favorites use the NTP's 24pt grid margin.
        static let favoritesHorizontalInset: CGFloat = 8
        /// Per Figma: single-line rows use 15pt top/bottom padding; rows with a subtitle use 14pt
        static let rowVerticalPaddingSingleLine: CGFloat = 15
        static let rowVerticalPaddingWithSubtitle: CGFloat = 14
        static let rowLeftInset: CGFloat = 12
        static let rowRightInset: CGFloat = 13
        /// List's horizontal content margin (cell edge). Reduced 8pt from the NTP's 24pt regularPadding
        /// to widen the cells in step with the narrower input card.
        static let listHorizontalContentMargin: CGFloat = 16
        static var suggestionGroupCornerRadius: CGFloat {
            if #available(iOS 26, *) { return 24 }
            return 10
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                // Keep scrollable chrome and the first suggestion group in one section so resting
                // content flows directly into suggestions or Duck.ai recents.
                Section {
                    if let escapeHatch {
                        EscapeHatchView(model: escapeHatch)
                        .frame(height: showsRestingContent ? nil : 0)
                        .clipped()
                        .opacity(showsRestingContent ? 1 : 0)
                        .allowsHitTesting(showsRestingContent)
                        .accessibilityHidden(!showsRestingContent)
                        .padding(.top, showsRestingContent ? scrollableChromeTopInset : 0)
                        .padding(.bottom, showsRestingContent ? escapeHatchBottomInset : 0)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                    if isSearchContentVisible {
                        VStack(spacing: Metrics.searchSectionSpacing) {
                            if hasMessages, let messagesModel {
                                FocusedNewTabPageMessagesView(messagesModel: messagesModel)
                            }
                            if hasFavorites, let favoritesViewModel {
                                FavoritesView(model: favoritesViewModel, isolatesContextMenu: true)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.horizontal, Metrics.favoritesHorizontalInset)
                            }
                        }
                        .padding(.top, searchContentTopInset)
                        .padding(.bottom, searchContentBottomInset)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .modifier(DisableListRowSelection())
                        .modifier(DismissFade(animationModel: animationModel))
                    }
                    if showsRestingContent, let syncPromo {
                        syncPromo
                            .padding(.top, syncPromoTopInset)
                            .padding(.bottom, syncPromoBottomInset)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .modifier(DismissFade(animationModel: animationModel))
                    }
                    if showsSuggestionRows, let firstSection = viewModel.sections.first {
                        if hasVisibleChromeRows, let title = firstSection.title, !title.isEmpty {
                            inlineSectionHeader(title)
                        }
                        rows(for: firstSection, roundsFirstRowTop: hasRowsBeforeFirstSuggestion)
                    }
                } header: {
                    if showsSuggestionRows, !hasVisibleChromeRows, let firstSection = viewModel.sections.first {
                        sectionHeader(firstSection.title)
                    }
                }
                if showsSuggestionRows {
                    ForEach(viewModel.sections.dropFirst()) { section in
                        Section {
                            rows(for: section)
                        } header: {
                            sectionHeader(section.title)
                        }
                    }
                }
            }
            .environment(\.defaultMinListRowHeight, 0)
            .listStyle(.insetGrouped)
            .modifier(SectionSpacingModifier(isFloatingPopover: isFloatingPopover,
                                             popoverSpacing: Metrics.popoverSectionSpacing,
                                             restingSpacing: restingSectionSpacing))
            // Replace insetGrouped's variable top margin with the design's list top inset (6pt below the
            // input on the top bar; 0 on the bottom bar, where the input sits below the list).
            .modifier(ListContentMarginsModifier(top: listTopContentInset,
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

    private var restingSectionSpacing: CGFloat? {
        guard showsRestingContent && showsSuggestionRows else { return nil }
        return isAddressBarAtBottom ? 0 : Metrics.listTopInset
    }

    private var listTopContentInset: CGFloat {
        scrollContentInsetTop + (isFloatingPopover ? Metrics.popoverVerticalInset : (isAddressBarAtBottom ? 0 : Metrics.listTopInset))
    }

    private var hasVisibleChromeRows: Bool {
        showsRestingContent && (escapeHatch != nil || isSearchContentVisible || syncPromo != nil)
    }

    private var hasRowsBeforeFirstSuggestion: Bool {
        escapeHatch != nil
            || isSearchContentVisible
            || (showsRestingContent && syncPromo != nil)
    }

    private var embeddedSuggestionSpacing: CGFloat {
        guard hasVisibleChromeRows, showsSuggestionRows else { return 0 }
        return restingSectionSpacing ?? 0
    }

    private var escapeHatchBottomInset: CGFloat {
        let precedesSuggestionSection = syncPromo == nil && !isSearchContentVisible ? embeddedSuggestionSpacing : 0
        return Metrics.scrollableChromeBottomInset + precedesSuggestionSection
    }

    private var syncPromoBottomInset: CGFloat {
        Metrics.scrollableChromeBottomInset + embeddedSuggestionSpacing
    }

    private var hasMessages: Bool {
        !(messagesModel?.homeMessageViewModels.isEmpty ?? true)
    }

    private var hasFavorites: Bool {
        !(favoritesViewModel?.allFavorites.isEmpty ?? true)
    }

    private var hasSearchContent: Bool {
        hasMessages || hasFavorites
    }

    private var isSearchContentVisible: Bool {
        showsRestingContent && showsFavorites && hasSearchContent
    }

    private var scrollableChromeTopInset: CGFloat {
        isAddressBarAtBottom ? Metrics.embeddedHatchBottomBarTopInset : Metrics.embeddedHatchTopBarTopInset
    }

    private var searchContentTopInset: CGFloat {
        let contentInset = escapeHatch == nil ? scrollableChromeTopInset : Metrics.searchAfterHatchTopInset
        return contentInset + (hasMessages && !isAddressBarAtBottom ? Metrics.messageShadowTopInset : 0)
    }

    private var searchContentBottomInset: CGFloat {
        hasMessages && !hasFavorites ? Metrics.messageShadowBottomInset : Metrics.scrollableChromeBottomInset
    }

    private var syncPromoTopInset: CGFloat {
        guard escapeHatch != nil else { return isAddressBarAtBottom ? Metrics.syncPromoBottomBarTopInset : 0 }
        return Metrics.duckAIAfterHatchTopInset
    }

    @ViewBuilder
    private func rows(for section: SuggestionSection, roundsFirstRowTop: Bool = false) -> some View {
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
            .listRowBackground(rowBackground(for: row,
                                             roundsTop: roundsFirstRowTop && row.id == section.rows.first?.id))
            .modifier(SeparatorTrailingToContentModifier())
            .modifier(DismissFade(animationModel: animationModel))
            // Pointer hover highlights the row, reusing the keyboard-selection highlight (matches the
            // legacy autocomplete). Touch never fires onHover, so this is pointer-only.
            .onHover { isHovering in
                if isHovering { viewModel.selectedRowID = row.id }
            }
        }
    }

    /// Highlights the hardware-keyboard-selected row (iPad popover); plain surface otherwise.
    /// `selectedRowID` stays nil on iPhone (no arrow-key navigation), so this is inert there.
    @ViewBuilder
    private func rowBackground(for row: SuggestionRow, roundsTop: Bool) -> some View {
        let color = row.id == viewModel.selectedRowID
            ? Color(designSystemColor: .accentPrimary)
            : Color(designSystemColor: .surface)
        if roundsTop {
            if #available(iOS 17, *) {
                color.clipShape(UnevenRoundedRectangle(topLeadingRadius: Metrics.suggestionGroupCornerRadius,
                                                       topTrailingRadius: Metrics.suggestionGroupCornerRadius,
                                                       style: .continuous))
            } else {
                color.cornerRadius(Metrics.suggestionGroupCornerRadius, corners: [.topLeft, .topRight])
            }
        } else {
            color
        }
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

    private func inlineSectionHeader(_ title: String) -> some View {
        Text(title)
            .daxTitle3()
            .foregroundColor(Color(designSystemColor: .textPrimary))
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
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
    let restingSpacing: CGFloat?

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 17, *) {
            let spacing = restingSpacing.map(ListSectionSpacing.custom)
                ?? (isFloatingPopover ? .custom(popoverSpacing) : .compact)
            content.listSectionSpacing(spacing)
        } else {
            content
        }
    }
}

private struct DisableListRowSelection: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 17, *) {
            content.selectionDisabled()
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

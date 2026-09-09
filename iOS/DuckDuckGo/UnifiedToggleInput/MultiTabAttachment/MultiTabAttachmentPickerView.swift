//
//  MultiTabAttachmentPickerView.swift
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

import Core
import DesignResourcesKit
import DesignResourcesKitIcons
import DuckUI
import SwiftUI
import UIKit

@MainActor
final class MultiTabAttachmentPickerViewModel: ObservableObject {

    struct Item: Identifiable {
        let candidate: MultiTabAttachmentCandidate
        let favicon: UIImage

        var id: TabUID { candidate.tabId }
    }

    @Published var query = ""
    @Published private(set) var selectedTabIds: Set<TabUID>

    let items: [Item]
    private let itemsById: [TabUID: Item]
    private let attachmentLimit: Int

    init(candidates: [MultiTabAttachmentCandidate], selectedTabIds: Set<TabUID>, attachmentLimit: Int) {
        let items = candidates.map { candidate in
            let favicon = FaviconsHelper.loadFaviconSync(
                forDomain: candidate.url.host,
                usingCache: .tabs,
                useFakeFavicon: true).image ?? DesignSystemImages.Glyphs.Size24.globe
            return Item(candidate: candidate, favicon: favicon)
        }
        self.items = items
        itemsById = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        self.selectedTabIds = selectedTabIds
        self.attachmentLimit = attachmentLimit
    }

    var filteredItems: [Item] {
        let candidates = MultiTabAttachmentCandidateFilter.filter(items.map(\.candidate), query: query)
        return candidates.compactMap { itemsById[$0.tabId] }
    }

    func isSelected(_ item: Item) -> Bool {
        selectedTabIds.contains(item.id)
    }

    func isEnabled(_ item: Item) -> Bool {
        isSelected(item) || selectedTabIds.count < attachmentLimit
    }

    func toggleSelection(for item: Item) {
        if isSelected(item) {
            selectedTabIds.remove(item.id)
        } else if selectedTabIds.count < attachmentLimit {
            selectedTabIds.insert(item.id)
        }
    }
}

struct MultiTabAttachmentPickerView: View {

    @ObservedObject var viewModel: MultiTabAttachmentPickerViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.promptSpacing) {
                Text(UserText.aiChatChooseTabsPrompt)
                    .daxHeadline()

                Spacer(minLength: 0)

                Text(UserText.aiChatChooseTabsSelectionCount(
                    viewModel.selectedTabIds.count,
                    attachmentLimit: MultiTabAttachmentSelectionPolicy.attachmentLimit))
                    .daxBodyRegular()
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundColor(Color(designSystemColor: .textSecondary))
            .padding(.horizontal, Metrics.horizontalPadding)
            .padding(.top, Metrics.promptTopPadding)
            .padding(.bottom, Metrics.promptBottomPadding)

            tabList
        }
        .background(Color(designSystemColor: .background))
        .searchable(text: $viewModel.query, prompt: Text(UserText.aiChatChooseTabsSearchPlaceholder))
        .navigationTitle(UserText.aiChatChooseTabsTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var tabList: some View {
        let items = viewModel.filteredItems
        if items.isEmpty {
            Text(UserText.aiChatChooseTabsNoMatches)
                .daxBodyRegular()
                .foregroundColor(Color(designSystemColor: .textSecondary))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        tabRow(item)
                        if index < items.count - 1 {
                            Divider()
                                .padding(.leading, Metrics.separatorLeadingPadding)
                        }
                    }
                }
                .background(Color(designSystemColor: .surface))
                .clipShape(RoundedRectangle(cornerRadius: Metrics.listCornerRadius))
                .padding(.horizontal, Metrics.horizontalPadding)
                .padding(.bottom, Metrics.listBottomPadding)
            }
        }
    }

    private func tabRow(_ item: MultiTabAttachmentPickerViewModel.Item) -> some View {
        let isSelected = viewModel.isSelected(item)
        let isEnabled = viewModel.isEnabled(item)

        return Button {
            viewModel.toggleSelection(for: item)
        } label: {
            HStack(spacing: Metrics.rowSpacing) {
                Image(uiImage: isSelected
                      ? DesignSystemImages.Glyphs.Size24.checkSolid
                      : DesignSystemImages.Glyphs.Size24.shapeCircle)
                    .resizable()
                    .renderingMode(.template)
                    .foregroundColor(Color(designSystemColor: isSelected ? .accentPrimary : .iconsTertiary))
                    .frame(width: Metrics.selectionSize, height: Metrics.selectionSize)

                Image(uiImage: item.favicon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: Metrics.faviconSize, height: Metrics.faviconSize)
                    .clipShape(RoundedRectangle(cornerRadius: Metrics.faviconCornerRadius))

                VStack(alignment: .leading, spacing: Metrics.textSpacing) {
                    Text(item.candidate.title)
                        .daxBodyRegular()
                        .foregroundColor(Color(designSystemColor: .textPrimary))
                        .lineLimit(1)

                    Text(item.candidate.url.host ?? item.candidate.url.absoluteString)
                        .daxFootnoteRegular()
                        .foregroundColor(Color(designSystemColor: .textSecondary))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, Metrics.rowHorizontalPadding)
            .padding(.vertical, Metrics.rowVerticalPadding)
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : Metrics.disabledOpacity)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

}

private extension MultiTabAttachmentPickerView {

    enum Metrics {
        static let horizontalPadding: CGFloat = 16
        static let promptSpacing: CGFloat = 12
        static let promptTopPadding: CGFloat = 24
        static let promptBottomPadding: CGFloat = 12
        static let listCornerRadius: CGFloat = 16
        static let listBottomPadding: CGFloat = 8
        static let rowSpacing: CGFloat = 12
        static let rowHorizontalPadding: CGFloat = 16
        static let rowVerticalPadding: CGFloat = 12
        static let selectionSize: CGFloat = 24
        static let faviconSize: CGFloat = 32
        static let faviconCornerRadius: CGFloat = 8
        static let textSpacing: CGFloat = 2
        static let separatorLeadingPadding: CGFloat = 84
        static let disabledOpacity = 0.4
    }
}

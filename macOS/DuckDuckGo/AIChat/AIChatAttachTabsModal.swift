//
//  AIChatAttachTabsModal.swift
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

import AppKit
import DesignResourcesKitIcons
import SwiftUI
import SwiftUIExtensions

struct AIChatAttachTabsModal: ModalView {

    private enum Layout {
        static let rowHeight: CGFloat = 22
        static let rowSpacing: CGFloat = 4
        static let maxListHeight: CGFloat = 234
        /// Row inset wide enough that titles and the checkbox hit area clear the scroller lane.
        static let listTrailingInset: CGFloat = 34
    }

    @ObservedObject private var themeManager: ThemeManager = NSApp.delegateTyped.themeManager
    @Environment(\.dismiss) private var dismiss

    private let tabs: [AIChatTabAttachment]
    private let currentTabId: String?
    private let maxSelection: Int
    private let onAttach: ([AIChatTabAttachment]) -> Void

    @State private var selectedIds: Set<String>
    @State private var searchQuery: String = ""

    private var filteredTabs: [AIChatTabAttachment] {
        AIChatMentionPickerFilter.filter(tabs, query: searchQuery, currentTabId: currentTabId)
    }

    init(tabs: [AIChatTabAttachment],
         currentTabId: String?,
         preselectedIds: Set<String>,
         maxSelection: Int,
         onAttach: @escaping ([AIChatTabAttachment]) -> Void) {
        self.tabs = tabs
        self.currentTabId = currentTabId
        self.maxSelection = maxSelection
        self.onAttach = onAttach
        _selectedIds = State(initialValue: preselectedIds)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(UserText.aiChatAttachMenuAttachTabs)
                .font(.system(size: 13).weight(.semibold))
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

            Divider()

            TextField(UserText.aiChatAttachTabsModalSearchPlaceholder, text: $searchQuery)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 20)
                .padding(.top, 14)

            Text(UserText.aiChatAttachMenuTabsHeader)
                .font(.system(size: 10).weight(.semibold))
                .foregroundColor(Color(designSystemColor: .textSecondary))
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 6)

            let visibleTabs = filteredTabs
            ScrollView {
                VStack(alignment: .leading, spacing: Layout.rowSpacing) {
                    if visibleTabs.isEmpty {
                        Text(UserText.aiChatAttachMenuNoOpenTabs)
                            .font(.system(size: 13))
                            .foregroundColor(Color(designSystemColor: .textSecondary))
                            .frame(height: Layout.rowHeight)
                    }
                    ForEach(visibleTabs) { tab in
                        row(for: tab)
                            .frame(height: Layout.rowHeight)
                    }
                }
                .padding(.leading, 20)
                .padding(.trailing, Layout.listTrailingInset)
            }
            .frame(height: min(CGFloat(max(tabs.count, 1)) * (Layout.rowHeight + Layout.rowSpacing), Layout.maxListHeight))

            HStack(spacing: 8) {
                Button {
                    dismiss()
                } label: {
                    Text(UserText.cancel)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                }
                .buttonStyle(StandardButtonStyle(topPadding: 0, bottomPadding: 0, pillShape: true))
                .keyboardShortcut(.cancelAction)

                Button {
                    onAttach(tabs.filter { selectedIds.contains($0.id) })
                    dismiss()
                } label: {
                    Text(UserText.aiChatAttachTabsModalAttachButton)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                }
                .buttonStyle(DefaultActionButtonStyle(enabled: true, topPadding: 0, bottomPadding: 0, pillShape: true))
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 340)
        .background(Color(designSystemColor: .surfaceSecondary, palette: themeManager.designColorPalette))
    }

    private func row(for tab: AIChatTabAttachment) -> some View {
        let isSelected = selectedIds.contains(tab.id)
        return Toggle(isOn: Binding(
            get: { isSelected },
            set: { isOn in
                if isOn {
                    selectedIds.insert(tab.id)
                } else {
                    selectedIds.remove(tab.id)
                }
            }
        )) {
            HStack(spacing: 6) {
                favicon(for: tab)
                    .frame(width: 16, height: 16)
                Text(tab.title.isEmpty ? (tab.url.host ?? tab.url.absoluteString) : tab.title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if tab.id == currentTabId {
                    Text(UserText.aiChatTabPickerCurrentTabSuffix)
                        .font(.system(size: 13))
                        .foregroundColor(Color(designSystemColor: .textSecondary))
                }
                Spacer(minLength: 0)
            }
            .help(tab.url.absoluteString)
        }
        .toggleStyle(.checkbox)
        .disabled(!isSelected && selectedIds.count >= maxSelection)
    }

    @ViewBuilder
    private func favicon(for tab: AIChatTabAttachment) -> some View {
        if let favicon = tab.favicon {
            Image(nsImage: favicon).resizable().aspectRatio(contentMode: .fit)
        } else {
            Image(nsImage: DesignSystemImages.Glyphs.Size16.globe).resizable().aspectRatio(contentMode: .fit)
        }
    }
}

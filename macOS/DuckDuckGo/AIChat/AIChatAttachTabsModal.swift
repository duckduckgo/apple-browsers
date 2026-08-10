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
import Carbon.HIToolbox
import DesignResourcesKitIcons
import SwiftUI
import SwiftUIExtensions

struct AIChatAttachTabsModal: ModalView {

    private enum Layout {
        static let rowHeight: CGFloat = 22
        static let rowSpacing: CGFloat = 4
        static let maxListHeight: CGFloat = 234
        static let blockedRowOpacity: CGFloat = 0.4
        /// Row inset wide enough that titles and the checkbox hit area clear the scroller lane.
        static let listTrailingInset: CGFloat = 34
    }

    @ObservedObject private var themeManager: ThemeManager = NSApp.delegateTyped.themeManager
    @Environment(\.dismiss) private var dismiss

    private let tabs: [AIChatTabAttachment]
    private let currentTabId: String?
    private let maxSelection: Int
    private let onAttach: ([AIChatTabAttachment]) -> Void

    /// Set when the dialog opens and not recalculated: confirming can remove tabs as well as add
    /// them, so a session that began with attachments updates them however the boxes end up.
    private let opensWithAttachments: Bool

    @State private var selectedIds: Set<String>
    @State private var searchQuery: String = ""
    /// Row the arrow keys are on. Nil until the first arrow press, so typing a space still types.
    @State private var highlightedId: String?
    @State private var keyMonitor: Any?
    @State private var sheetWindow: NSWindow?

    /// Opening with nothing attached and selecting nothing leaves nothing to add, so confirming is
    /// pointless. Opening with attachments is different: clearing every box is an edit like any
    /// other, and Update is what applies it — disabling it there strands the removal behind Cancel,
    /// which throws it away.
    private var canConfirm: Bool {
        opensWithAttachments || !selectedIds.isEmpty
    }

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
        self.opensWithAttachments = !preselectedIds.isEmpty
        _selectedIds = State(initialValue: preselectedIds)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(UserText.aiChatAttachMenuAttachTabs)
                .font(.system(size: 16).weight(.bold))
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 14)

            TextField(UserText.aiChatAttachTabsModalSearchPlaceholder, text: $searchQuery)
                .textFieldStyle(.themed)
                .padding(.horizontal, 20)

            Divider()
                .padding(.top, 14)
                .padding(.bottom, 14)

            let visibleTabs = filteredTabs
            ScrollViewReader { scroller in
                ScrollView {
                    VStack(alignment: .leading, spacing: Layout.rowSpacing) {
                        if visibleTabs.isEmpty {
                            Text(searchQuery.isEmpty ? UserText.aiChatAttachMenuNoOpenTabs : UserText.aiChatMentionPickerNoMatches)
                                .font(.system(size: 13))
                                .foregroundColor(Color(designSystemColor: .textSecondary))
                                .frame(height: Layout.rowHeight)
                        }
                        ForEach(visibleTabs) { tab in
                            row(for: tab)
                                .frame(height: Layout.rowHeight)
                                .background(highlightBackground(for: tab))
                                .id(tab.id)
                        }
                    }
                    .padding(.leading, 20)
                    .padding(.trailing, Layout.listTrailingInset)
                }
                .onChange(of: highlightedId) { id in
                    guard let id else { return }
                    scroller.scrollTo(id)
                }
            }
            .frame(height: min(CGFloat(max(tabs.count, 1)) * (Layout.rowHeight + Layout.rowSpacing), Layout.maxListHeight))

            Divider()

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
                    Text(opensWithAttachments ? UserText.aiChatAttachTabsModalUpdateButton : UserText.aiChatAttachTabsModalAttachButton)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                }
                .buttonStyle(DefaultActionButtonStyle(enabled: canConfirm, topPadding: 0, bottomPadding: 0, pillShape: true))
                .disabled(!canConfirm)
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 340)
        .background(Color(designSystemColor: .surfaceSecondary, palette: themeManager.designColorPalette))
        .background(WindowReader { sheetWindow = $0 })
        .onAppear { startKeyMonitor() }
        .onDisappear { stopKeyMonitor() }
    }

    // MARK: - Keyboard

    /// Arrow keys move a highlight through the filtered rows and space toggles the highlighted one,
    /// while the search field keeps focus for typing. A monitor rather than `onMoveCommand` because
    /// the field consumes arrow keys itself.
    private func startKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // The monitor is app-wide; only this sheet's keys are this view's business.
            guard let sheetWindow, event.window === sheetWindow else { return event }
            switch Int(event.keyCode) {
            case kVK_DownArrow: return moveHighlight(by: 1) ? nil : event
            case kVK_UpArrow: return moveHighlight(by: -1) ? nil : event
            case kVK_Space where highlightedId != nil: return toggleHighlighted() ? nil : event
            default: return event
            }
        }
    }

    private func stopKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
    }

    private func moveHighlight(by offset: Int) -> Bool {
        let visibleTabs = filteredTabs
        guard !visibleTabs.isEmpty else { return false }
        let current = highlightedId.flatMap { id in visibleTabs.firstIndex { $0.id == id } }
        let next = current.map { min(max($0 + offset, 0), visibleTabs.count - 1) } ?? (offset > 0 ? 0 : visibleTabs.count - 1)
        highlightedId = visibleTabs[next].id
        return true
    }

    private func toggleHighlighted() -> Bool {
        guard let highlightedId, let tab = filteredTabs.first(where: { $0.id == highlightedId }) else { return false }
        if selectedIds.contains(tab.id) {
            selectedIds.remove(tab.id)
        } else if selectedIds.count < maxSelection {
            selectedIds.insert(tab.id)
        }
        return true
    }

    @ViewBuilder
    private func highlightBackground(for tab: AIChatTabAttachment) -> some View {
        if tab.id == highlightedId {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(designSystemColor: .controlsFillPrimary, palette: themeManager.designColorPalette))
                .padding(.horizontal, -6)
        }
    }

    private func row(for tab: AIChatTabAttachment) -> some View {
        let isSelected = selectedIds.contains(tab.id)
        // At the limit, picking a different tab means unchecking one first — the row says so by
        // greying out. `disabled` alone leaves the favicon and the explicitly coloured suffix lit.
        let isBlockedByLimit = !isSelected && selectedIds.count >= maxSelection
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
            .opacity(isBlockedByLimit ? Layout.blockedRowOpacity : 1)
        }
        .toggleStyle(.checkbox)
        .disabled(isBlockedByLimit)
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

/// Hands back the window hosting this SwiftUI view, so a key monitor can tell this sheet's events
/// from every other window's.
private struct WindowReader: NSViewRepresentable {

    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onWindow(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { onWindow(nsView.window) }
    }
}

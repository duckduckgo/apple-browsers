//
//  TabOrganizerPopover.swift
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
import SwiftUI

@MainActor
enum TabOrganizerPopover {

    private static var current: NSPopover?

    static func show(relativeTo button: NSView, tabCollectionViewModel: TabCollectionViewModel) {
        current?.close()

        let viewModel = TabOrganizerViewModel(tabCollectionViewModel: tabCollectionViewModel)
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: TabOrganizerView(viewModel: viewModel))
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: button.isFlipped ? .maxY : .minY)
        current = popover
    }
}

// MARK: - View model

@MainActor
final class TabOrganizerViewModel: ObservableObject {

    enum State {
        case idle
        case loading(String)
        case results
        case failed(String)
    }

    static let pageContentExcerptLength = 600
    static let defaultSuggestions = ["Close shopping tabs", "Keep only news", "Find tabs about travel"]

    @Published private(set) var tabs: [TabSnapshot]
    @Published private(set) var state: State = .idle
    @Published private(set) var groups: [ProposedGroup] = []
    @Published private(set) var selectedTabIDs: Set<String> = []
    @Published private(set) var suggestions = TabOrganizerViewModel.defaultSuggestions
    @Published private(set) var isLoadingSuggestions = false
    @Published var instruction = ""
    @Published var readsPageContent = false

    let favicons: [String: NSImage]
    private let tabCollectionViewModel: TabCollectionViewModel
    private var task: Task<Void, Never>?

    init(tabCollectionViewModel: TabCollectionViewModel) {
        self.tabCollectionViewModel = tabCollectionViewModel
        tabs = TabSnapshotProvider.snapshots(in: tabCollectionViewModel)
        let allTabs = (tabCollectionViewModel.pinnedTabsCollection?.tabs ?? []) + tabCollectionViewModel.tabCollection.tabs
        favicons = Dictionary(allTabs.compactMap { tab in tab.favicon.map { (tab.uuid, $0) } }, uniquingKeysWith: { first, _ in first })
        loadSuggestions()
    }

    private func loadSuggestions() {
        guard #available(macOS 26.0, *) else { return }
        isLoadingSuggestions = true
        Task { [weak self, tabs] in
            let generated = (try? await AppleTabOrganizer().suggestions(for: tabs)) ?? []
            guard let self else { return }
            if !generated.isEmpty {
                suggestions = generated
            }
            isLoadingSuggestions = false
        }
    }

    func tab(withID id: String) -> TabSnapshot? {
        tabs.first { $0.id == id }
    }

    // MARK: Asking

    func groupByTopic() {
        organize(.groupByTopic)
    }

    func submitInstruction() {
        let text = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        organize(.instruction(text))
    }

    func useSuggestion(_ suggestion: String) {
        instruction = suggestion
        submitInstruction()
    }

    func startOver() {
        task?.cancel()
        groups = []
        selectedTabIDs = []
        state = .idle
    }

    private func organize(_ request: TabOrganizerRequest) {
        guard #available(macOS 26.0, *) else {
            state = .failed("Organizing tabs needs macOS 26 or later with Apple Intelligence.")
            return
        }
        task?.cancel()
        let excerptLength = readsPageContent ? Self.pageContentExcerptLength : 0
        state = .loading(readsPageContent ? "Reading \(tabs.count) pages…" : "Organizing \(tabs.count) tabs…")

        task = Task { [weak self, tabCollectionViewModel] in
            guard let self else { return }
            var snapshots = TabSnapshotProvider.snapshots(in: tabCollectionViewModel)
            snapshots = await TabSnapshotProvider.addingContent(to: snapshots, in: tabCollectionViewModel, excerptLength: excerptLength)
            if excerptLength > 0 {
                state = .loading("Organizing \(snapshots.count) tabs…")
            }
            do {
                let proposal = try await AppleTabOrganizer().organize(snapshots, request: request)
                guard !Task.isCancelled else { return }
                tabs = snapshots
                groups = proposal.groups
                selectedTabIDs = Set(proposal.groups.flatMap(\.tabIDs))
                state = .results
            } catch TabOrganizerError.modelUnavailable {
                state = .failed("Apple Intelligence isn't available. Turn it on in System Settings ▸ Apple Intelligence & Siri.")
            } catch TabOrganizerError.noTabs {
                state = .failed("There are no tabs to organize in this window.")
            } catch {
                guard !Task.isCancelled else { return }
                state = .failed("Couldn't organize tabs. Try again.")
            }
        }
    }

    // MARK: Reviewing

    var hasNoMatches: Bool {
        groups.first?.name == TabOrganizerProposalBuilder.everythingElseGroupName
    }

    func isSelected(_ tabID: String) -> Bool {
        selectedTabIDs.contains(tabID)
    }

    func toggleTab(_ tabID: String) {
        if selectedTabIDs.contains(tabID) {
            selectedTabIDs.remove(tabID)
        } else {
            selectedTabIDs.insert(tabID)
        }
    }

    func isGroupSelected(_ group: ProposedGroup) -> Bool {
        group.tabIDs.contains { selectedTabIDs.contains($0) }
    }

    func toggleGroup(_ group: ProposedGroup) {
        if isGroupSelected(group) {
            selectedTabIDs.subtract(group.tabIDs)
        } else {
            selectedTabIDs.formUnion(group.tabIDs)
        }
    }

    func setAction(_ action: TabGroupAction, for group: ProposedGroup) {
        guard let index = groups.firstIndex(where: { $0.id == group.id }) else { return }
        groups[index].action = action
    }

    /// Selected tabs per action. Pinned tabs are never closed or moved.
    func selectedTabIDs(for action: TabGroupAction) -> [String] {
        groups.filter { $0.action == action }
            .flatMap(\.tabIDs)
            .filter { selectedTabIDs.contains($0) && tab(withID: $0)?.isPinned != true }
    }

    var applySummary: String? {
        let move = selectedTabIDs(for: .moveToNewWindow).count
        let close = selectedTabIDs(for: .close).count
        let parts = [move > 0 ? "move \(move)" : nil, close > 0 ? "close \(close)" : nil].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    func apply() {
        // Step 6: close and move tabs.
    }
}

extension TabGroupAction {
    var title: String {
        switch self {
        case .keep: return "Keep"
        case .close: return "Close"
        case .moveToNewWindow: return "New window"
        }
    }
}

// MARK: - Views

struct TabOrganizerView: View {

    @ObservedObject var viewModel: TabOrganizerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            askSection
            Divider()
            content.frame(maxHeight: .infinity, alignment: .top)
            if case .results = viewModel.state {
                Divider()
                footer
            }
        }
        .padding(16)
        .frame(width: 440, height: 560)
    }

    private var header: some View {
        HStack {
            Image(systemName: "sparkles")
            Text("Organize tabs").font(.headline)
            Spacer()
            Text("\(viewModel.tabs.count) tabs").foregroundColor(.secondary)
        }
    }

    private var askSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: viewModel.groupByTopic) {
                Label("Group by topic", systemImage: "square.grid.2x2")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .disabled(isLoading)

            HStack(spacing: 8) {
                TextField("Find, close or move tabs…", text: $viewModel.instruction)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(viewModel.submitInstruction)
                Button(action: viewModel.submitInstruction) {
                    Image(systemName: "arrow.up.circle.fill")
                }
                .buttonStyle(.borderless)
                .disabled(isLoading || viewModel.instruction.isEmpty)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if viewModel.isLoadingSuggestions {
                        ProgressView().controlSize(.small)
                    }
                    ForEach(viewModel.suggestions, id: \.self) { suggestion in
                        Button(suggestion) { viewModel.useSuggestion(suggestion) }
                            .controlSize(.small)
                            .disabled(isLoading)
                    }
                }
            }

            Toggle("Look inside pages (slower)", isOn: $viewModel.readsPageContent)
                .toggleStyle(.checkbox)
                .font(.caption)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle:
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(viewModel.tabs, id: \.id) { tab in
                        TabOrganizerRow(tab: tab, favicon: viewModel.favicons[tab.id])
                    }
                }
            }
        case .loading(let message):
            VStack(spacing: 8) {
                ProgressView()
                Text(message).foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            Text(message)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .multilineTextAlignment(.center)
        case .results:
            results
        }
    }

    private var results: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                if viewModel.hasNoMatches {
                    Text("No matching tabs").foregroundColor(.secondary).padding(.bottom, 4)
                }
                ForEach(viewModel.groups) { group in
                    groupHeader(group)
                    ForEach(group.tabIDs, id: \.self) { tabID in
                        if let tab = viewModel.tab(withID: tabID) {
                            HStack(spacing: 6) {
                                Toggle("", isOn: Binding(get: { viewModel.isSelected(tabID) },
                                                         set: { _ in viewModel.toggleTab(tabID) }))
                                    .toggleStyle(.checkbox)
                                    .labelsHidden()
                                TabOrganizerRow(tab: tab, favicon: viewModel.favicons[tab.id])
                            }
                            .padding(.leading, 20)
                        }
                    }
                }
            }
        }
    }

    private func groupHeader(_ group: ProposedGroup) -> some View {
        HStack(spacing: 6) {
            Toggle("", isOn: Binding(get: { viewModel.isGroupSelected(group) },
                                     set: { _ in viewModel.toggleGroup(group) }))
                .toggleStyle(.checkbox)
                .labelsHidden()
            Text(group.name).font(.headline)
            Text("\(group.tabIDs.count)").foregroundColor(.secondary)
            Spacer()
            Picker("", selection: Binding(get: { group.action },
                                          set: { viewModel.setAction($0, for: group) })) {
                ForEach(TabGroupAction.allCases, id: \.self) { action in
                    Text(action.title).tag(action)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
        .padding(.top, 8)
    }

    private var footer: some View {
        HStack {
            Button("Start over", action: viewModel.startOver)
            Spacer()
            Button(viewModel.applySummary.map { "Apply · \($0)" } ?? "Apply", action: viewModel.apply)
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.applySummary == nil)
        }
    }

    private var isLoading: Bool {
        if case .loading = viewModel.state { return true }
        return false
    }
}

struct TabOrganizerRow: View {

    let tab: TabSnapshot
    let favicon: NSImage?

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let favicon {
                    Image(nsImage: favicon).resizable()
                } else {
                    Image(systemName: "globe").foregroundColor(.secondary)
                }
            }
            .frame(width: 16, height: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(tab.title).lineLimit(1)
                Text(tab.host).font(.caption).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer()
            if tab.isPinned {
                Image(systemName: "pin").foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

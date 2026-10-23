//
//  TabOrganizerViewModel.swift
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
import Combine

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
    @Published private(set) var cleanupTabIDs: [String] = []
    @Published private(set) var notice: String?
    @Published var instruction = ""
    @Published var readsPageContent = false

    let favicons: [String: NSImage]
    var onApplied: (() -> Void)?
    private let tabCollectionViewModel: TabCollectionViewModel
    private var task: Task<Void, Never>?
    private var lastRequest: TabOrganizerRequest?

    init(tabCollectionViewModel: TabCollectionViewModel) {
        self.tabCollectionViewModel = tabCollectionViewModel
        tabs = TabSnapshotProvider.snapshots(in: tabCollectionViewModel)
        let allTabs = (tabCollectionViewModel.pinnedTabsCollection?.tabs ?? []) + tabCollectionViewModel.tabCollection.tabs
        favicons = Dictionary(allTabs.compactMap { tab in tab.favicon.map { (tab.uuid, $0) } }, uniquingKeysWith: { first, _ in first })
        cleanupTabIDs = TabOrganizerActions(tabCollectionViewModel: tabCollectionViewModel).cleanupCandidateIDs()
        loadSuggestions()
    }

    func closeCleanupTabs() {
        TabOrganizerActions(tabCollectionViewModel: tabCollectionViewModel).close(cleanupTabIDs)
        cleanupTabIDs = []
        tabs = TabSnapshotProvider.snapshots(in: tabCollectionViewModel)
        if case .results = state {
            startOver()
        }
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

    struct TabSection: Identifiable {
        let id: String
        /// nil for ungrouped tabs when the window has no groups at all.
        let name: String?
        let color: NSColor?
        let tabs: [TabSnapshot]
    }

    /// Existing tab groups in tab order, then the ungrouped tabs.
    var idleSections: [TabSection] {
        var names: [String] = []
        for name in tabs.compactMap(\.groupName) where !names.contains(name) {
            names.append(name)
        }
        var sections = names.map { name in
            TabSection(id: name, name: name, color: groupColor(named: name), tabs: tabs.filter { $0.groupName == name })
        }
        let ungrouped = tabs.filter { $0.groupName == nil }
        if !ungrouped.isEmpty {
            sections.append(TabSection(id: "", name: names.isEmpty ? nil : "Not in a group", color: nil, tabs: ungrouped))
        }
        return sections
    }

    func groupColor(named name: String) -> NSColor? {
        tabCollectionViewModel.tabGroupManager.groups.first { $0.name == name }?.color.nsColor
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

    func retry() {
        lastRequest.map(organize)
    }

    private func organize(_ request: TabOrganizerRequest) {
        lastRequest = request
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
                if case .instruction = request, !groups.isEmpty {
                    refine(with: proposal)
                } else {
                    groups = proposal.groups
                    showsLeftovers = false
                    selectedTabIDs = Set(proposal.groups.flatMap { group in group.tabIDs.filter { !isUnchanged($0, in: group) } })
                    notice = proposal.groups.first?.name == TabOrganizerProposalBuilder.everythingElseGroupName ? "No matching tabs" : nil
                }
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

    /// An instruction on top of existing results only reshapes the tabs it matched: they leave their groups
    /// and the new groups take the place of the first group they came from. The rest stays as it was.
    private func refine(with proposal: TabOrganizerProposal) {
        let everythingElse = proposal.groups.first { $0.name == TabOrganizerProposalBuilder.everythingElseGroupName }
        let newGroups = proposal.groups.filter { $0.name != TabOrganizerProposalBuilder.everythingElseGroupName }
        let matched = Set(newGroups.flatMap(\.tabIDs))
        guard !matched.isEmpty else {
            notice = "No matching tabs"
            return
        }

        var refined: [ProposedGroup] = []
        var inserted = false
        for var group in groups {
            let containsMatched = group.tabIDs.contains(where: matched.contains)
            group.tabIDs.removeAll(where: matched.contains)
            if containsMatched, !inserted {
                refined += newGroups
                inserted = true
            }
            if let action = everythingElse?.action, action != .keep {
                group.action = action
            }
            if !group.tabIDs.isEmpty {
                refined.append(group)
            }
        }
        groups = inserted ? refined : newGroups + refined
        selectedTabIDs.formUnion(matched)
        notice = nil
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

    func switchToTab(_ tabID: String) {
        guard let index = tabCollectionViewModel.indexInAllTabs(where: { $0.uuid == tabID }) else { return }
        tabCollectionViewModel.select(at: index)
    }

    // MARK: Group menus

    /// Acts on an existing tab group straight away, then refreshes the list.
    func perform(_ operation: TabGroupOperations.Operation, onExistingGroupNamed name: String) {
        guard let group = tabCollectionViewModel.tabGroupManager.groups.first(where: { $0.name == name }) else { return }
        TabGroupOperations(tabCollectionViewModel: tabCollectionViewModel).perform(operation, on: group)
        tabs = TabSnapshotProvider.snapshots(in: tabCollectionViewModel)
    }

    func isExistingGroupCollapsed(named name: String) -> Bool {
        tabCollectionViewModel.tabGroupManager.groups.first { $0.name == name }
            .map(tabCollectionViewModel.tabGroupManager.isCollapsed) ?? false
    }

    func renameProposedGroup(_ group: ProposedGroup) {
        guard let name = TabGroupOperations.askForName(current: group.name)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty, let index = groups.firstIndex(where: { $0.id == group.id }) else { return }
        groups[index].name = name
    }

    func merge(_ group: ProposedGroup, into target: ProposedGroup) {
        guard let targetIndex = groups.firstIndex(where: { $0.id == target.id }) else { return }
        groups[targetIndex].tabIDs += group.tabIDs.filter { !groups[targetIndex].tabIDs.contains($0) }
        groups.removeAll { $0.id == group.id }
    }

    func moveTabToNewGroup(_ tabID: String) {
        let action = groups.first { $0.tabIDs.contains(tabID) }?.action ?? .createTabGroup
        for index in groups.indices {
            groups[index].tabIDs.removeAll { $0 == tabID }
        }
        groups.append(ProposedGroup(name: "New group", tabIDs: [tabID], action: action == .keep ? .createTabGroup : action))
    }

    /// Takes a tab out of whatever its group would do.
    func keepTab(_ tabID: String) {
        if let index = groups.firstIndex(where: { isLeftover($0) }) {
            moveTab(tabID, toGroupWithID: groups[index].id)
        } else {
            for index in groups.indices {
                groups[index].tabIDs.removeAll { $0 == tabID }
            }
            groups.append(ProposedGroup(name: TabOrganizerProposalBuilder.everythingElseGroupName, tabIDs: [tabID], action: .keep))
        }
    }

    /// Drag and drop between groups. Empty groups stay so a tab can be dragged back.
    func moveTab(_ tabID: String, toGroupWithID groupID: UUID) {
        guard groups.contains(where: { $0.id == groupID }), groups.contains(where: { $0.tabIDs.contains(tabID) }) else { return }
        for index in groups.indices {
            groups[index].tabIDs.removeAll { $0 == tabID }
        }
        if let index = groups.firstIndex(where: { $0.id == groupID }) {
            groups[index].tabIDs.append(tabID)
        }
    }

    func setActionForAll(_ action: TabGroupAction) {
        for index in groups.indices {
            groups[index].action = action
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

    // MARK: Changes

    @Published var showsLeftovers = false

    /// With the Tab group action, a tab already in that tab group doesn't change.
    func isUnchanged(_ tabID: String, in group: ProposedGroup) -> Bool {
        group.action == .createTabGroup && tab(withID: tabID)?.groupName.map { Self.sameName($0, group.name) } == true
    }

    func changeLabel(for tabID: String, in group: ProposedGroup) -> String? {
        guard group.action == .createTabGroup, !isUnchanged(tabID, in: group), let tab = tab(withID: tabID) else { return nil }
        return tab.groupName.map { "+ from \($0)" } ?? "+ joins"
    }

    func isNewTabGroup(_ group: ProposedGroup) -> Bool {
        group.action == .createTabGroup && existingGroupColor(named: group.name) == nil
    }

    func existingGroupColor(named name: String) -> NSColor? {
        tabCollectionViewModel.tabGroupManager.groups.first { Self.sameName($0.name, name) }?.color.nsColor
    }

    /// "Other" and "Everything else" left as Keep fold into one line.
    func isLeftover(_ group: ProposedGroup) -> Bool {
        group.action == .keep
            && [TabOrganizerProposalBuilder.otherGroupName, TabOrganizerProposalBuilder.everythingElseGroupName].contains(group.name)
    }

    private func changedTabIDs(in group: ProposedGroup) -> [String] {
        guard group.action != .keep else { return [] }
        return group.tabIDs.filter { selectedTabIDs.contains($0) && !isUnchanged($0, in: group) && tab(withID: $0)?.isPinned != true }
    }

    var changeCount: Int {
        groups.reduce(0) { $0 + changedTabIDs(in: $1).count }
    }

    var isCloseOnly: Bool {
        let actions = Set(groups.filter { !changedTabIDs(in: $0).isEmpty }.map(\.action))
        return actions == [.close]
    }

    var applyTitle: String {
        let count = changeCount
        guard count > 0 else { return "Apply" }
        if isCloseOnly {
            return count == 1 ? "Close 1 tab" : "Close \(count) tabs"
        }
        return count == 1 ? "Apply 1 change" : "Apply \(count) changes"
    }

    /// Existing tab groups that every one of their tabs would leave.
    var summary: String? {
        var leavingTabIDs = Set<String>()
        for group in groups where [.close, .moveToNewWindow, .createTabGroup, .ungroup].contains(group.action) {
            leavingTabIDs.formUnion(changedTabIDs(in: group))
        }
        var emptied: [String] = []
        for name in tabs.compactMap(\.groupName) where !emptied.contains(name) {
            let members = tabs.filter { $0.groupName == name }.map(\.id)
            if !members.isEmpty, members.allSatisfy(leavingTabIDs.contains) {
                emptied.append(name)
            }
        }
        guard !emptied.isEmpty else { return nil }
        let names = emptied.count == 1 ? emptied[0] : emptied.dropLast().joined(separator: ", ") + " and " + emptied.last!
        return "\(names) will be empty and removed."
    }

    private static func sameName(_ lhs: String, _ rhs: String) -> Bool {
        lhs.caseInsensitiveCompare(rhs) == .orderedSame
    }

    func apply() {
        let selectedGroups = groups.compactMap { group -> ProposedGroup? in
            guard group.action != .keep else { return nil }
            var selected = group
            selected.tabIDs = selectedTabIDs(for: group.action).filter(group.tabIDs.contains)
            return selected.tabIDs.isEmpty ? nil : selected
        }
        TabOrganizerActions(tabCollectionViewModel: tabCollectionViewModel).apply(selectedGroups)
        onApplied?()
    }
}

extension TabGroupAction {
    var title: String {
        switch self {
        case .keep: return "Keep"
        case .close: return "Close"
        case .moveToNewWindow: return "New window"
        case .bookmark: return "Bookmark"
        case .addToFavorites: return "Add to favorites"
        case .createTabGroup: return "Tab group"
        case .ungroup: return "Ungroup"
        }
    }
}

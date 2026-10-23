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
import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor
enum TabOrganizerPopover {

    private static var current: NSPopover?
    private static var stateCancellable: AnyCancellable?

    static func show(relativeTo button: NSView, tabCollectionViewModel: TabCollectionViewModel) {
        current?.close()

        let viewModel = TabOrganizerViewModel(tabCollectionViewModel: tabCollectionViewModel)
        let popover = NSPopover()
        popover.behavior = .semitransient
        popover.contentViewController = NSHostingController(rootView: TabOrganizerView(viewModel: viewModel))
        // Sized up front: positioning happens before SwiftUI reports its size.
        popover.contentSize = TabOrganizerView.size
        viewModel.onApplied = { [weak popover] in popover?.close() }
        // A click elsewhere must not throw away a request that is still running.
        stateCancellable = viewModel.$state.sink { [weak popover] state in
            if case .loading = state {
                popover?.behavior = .applicationDefined
            } else {
                popover?.behavior = .semitransient
            }
        }
        popover.show(positionedBelow: button)
        current = popover
    }
}

// MARK: - Views

struct TabOrganizerView: View {

    static let size = NSSize(width: 440, height: 560)

    @ObservedObject var viewModel: TabOrganizerViewModel
    @State private var dropTargetGroupID: UUID?

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
        .frame(width: Self.size.width, height: Self.size.height)
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

            if !viewModel.cleanupTabIDs.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "square.on.square")
                    Text("\(viewModel.cleanupTabIDs.count) duplicate or empty tabs")
                    Spacer()
                    Button("Close", action: viewModel.closeCleanupTabs)
                        .controlSize(.small)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle:
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(viewModel.idleSections) { section in
                        if let name = section.name {
                            HStack(spacing: 6) {
                                if let color = section.color {
                                    TabOrganizerGroupPill(name: name, color: Color(color))
                                } else {
                                    Text(name).font(.headline)
                                }
                                Text("\(section.tabs.count)").foregroundColor(.secondary)
                                Spacer()
                                if section.color != nil {
                                    existingGroupMenu(named: name)
                                }
                            }
                            .padding(.top, 10)
                            .padding(.bottom, 2)
                        }
                        ForEach(section.tabs, id: \.id) { tab in
                            TabOrganizerRow(tab: tab, favicon: viewModel.favicons[tab.id])
                                .onTapGesture { viewModel.switchToTab(tab.id) }
                                .padding(.leading, section.name == nil ? 0 : 14)
                        }
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
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle").font(.title2).foregroundColor(.secondary)
                Text(message)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                HStack {
                    Button("Start over", action: viewModel.startOver)
                    Button("Try again", action: viewModel.retry)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .results:
            results
        }
    }

    private var results: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                HStack {
                    Spacer()
                    Menu("Set all to…") {
                        ForEach(TabGroupAction.choices, id: \.self) { action in
                            Button(action.title) { viewModel.setActionForAll(action) }
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .font(.caption)
                }
                if let notice = viewModel.notice {
                    Text(notice).foregroundColor(.secondary).padding(.bottom, 4)
                }
                ForEach(viewModel.groups) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        if viewModel.isLeftover(group) && !viewModel.showsLeftovers {
                            Button {
                                viewModel.showsLeftovers = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                                    Text("\(group.name) · \(group.tabIDs.count) tabs unchanged")
                                }
                                .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 10)
                        } else {
                            groupHeader(group)
                            ForEach(group.tabIDs, id: \.self) { tabID in
                                if let tab = viewModel.tab(withID: tabID) {
                                    resultRow(tab: tab, in: group)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, 4)
                    .background(RoundedRectangle(cornerRadius: 6)
                        .fill(dropTargetGroupID == group.id ? Color.accentColor.opacity(0.12) : Color.clear))
                    .onDrop(of: [UTType.plainText], isTargeted: dropTargetBinding(for: group.id)) { providers in
                        drop(providers, on: group.id)
                    }
                }
            }
        }
    }

    private func dropTargetBinding(for groupID: UUID) -> Binding<Bool> {
        Binding(get: { dropTargetGroupID == groupID },
                set: { isTargeted in
                    if isTargeted {
                        dropTargetGroupID = groupID
                    } else if dropTargetGroupID == groupID {
                        dropTargetGroupID = nil
                    }
                })
    }

    private func drop(_ providers: [NSItemProvider], on groupID: UUID) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let tabID = object as? String else { return }
            DispatchQueue.main.async { viewModel.moveTab(tabID, toGroupWithID: groupID) }
        }
        return true
    }

    private func resultRow(tab: TabSnapshot, in group: ProposedGroup) -> some View {
        let isUnchanged = viewModel.isUnchanged(tab.id, in: group)
        return HStack(spacing: 6) {
            Toggle("", isOn: Binding(get: { viewModel.isSelected(tab.id) },
                                     set: { _ in viewModel.toggleTab(tab.id) }))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(isUnchanged)
            TabOrganizerRow(tab: tab, favicon: viewModel.favicons[tab.id])
                .onTapGesture { viewModel.switchToTab(tab.id) }
            if let label = viewModel.changeLabel(for: tab.id, in: group) {
                Text(label)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                    .foregroundColor(.accentColor)
            } else if group.action != .createTabGroup, let groupName = tab.groupName {
                TabOrganizerGroupPill(name: groupName, color: Color(viewModel.existingGroupColor(named: groupName) ?? .gray))
                    .font(.caption)
            }
        }
        .padding(.leading, 20)
        .opacity(isUnchanged ? 0.45 : 1)
        .onDrag { NSItemProvider(object: tab.id as NSString) }
        .contextMenu {
            Menu("Move to") {
                ForEach(viewModel.groups.filter { $0.id != group.id }) { other in
                    Button(other.name) { viewModel.moveTab(tab.id, toGroupWithID: other.id) }
                }
                Divider()
                Button("New group") { viewModel.moveTabToNewGroup(tab.id) }
            }
            if !viewModel.isLeftover(group) {
                Button("Keep this tab") { viewModel.keepTab(tab.id) }
            }
        }
    }

    private func groupHeader(_ group: ProposedGroup) -> some View {
        HStack(spacing: 6) {
            Toggle("", isOn: Binding(get: { viewModel.isGroupSelected(group) },
                                     set: { _ in viewModel.toggleGroup(group) }))
                .toggleStyle(.checkbox)
                .labelsHidden()
            if group.action == .createTabGroup, let color = viewModel.existingGroupColor(named: group.name) {
                TabOrganizerGroupPill(name: group.name, color: Color(color))
            } else {
                Text(group.name).font(.headline)
            }
            if viewModel.isNewTabGroup(group) {
                Text("new group")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.green.opacity(0.18)))
                    .foregroundColor(.green)
            }
            Text("\(group.tabIDs.count)").foregroundColor(.secondary)
            Spacer()
            Picker("", selection: Binding(get: { group.action },
                                              set: { viewModel.setAction($0, for: group) })) {
                    ForEach(TabGroupAction.choices, id: \.self) { action in
                        Text(action.title).tag(action)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            Menu {
                Button("Rename…") { viewModel.renameProposedGroup(group) }
                let others = viewModel.groups.filter { $0.id != group.id }
                if !others.isEmpty {
                    Menu("Merge into") {
                        ForEach(others) { other in
                            Button(other.name) { viewModel.merge(group, into: other) }
                        }
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.top, 8)
    }

    private func existingGroupMenu(named name: String) -> some View {
        Menu {
            ForEach(TabGroupOperations.Operation.allCases, id: \.self) { operation in
                Button(operation.title(isCollapsed: viewModel.isExistingGroupCollapsed(named: name))) {
                    viewModel.perform(operation, onExistingGroupNamed: name)
                }
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let summary = viewModel.summary {
                Text(summary).font(.caption).foregroundColor(.secondary)
            }
            HStack {
                Button("Start over", action: viewModel.startOver)
                Spacer()
                Button(viewModel.applyTitle, action: viewModel.apply)
                    .keyboardShortcut(.defaultAction)
                    .tint(viewModel.isCloseOnly ? .red : .accentColor)
                    .disabled(viewModel.changeCount == 0)
            }
        }
    }

    private var isLoading: Bool {
        if case .loading = viewModel.state { return true }
        return false
    }
}

/// The same look as the tab bar's group header: colour dot and name on a tint of the group colour.
struct TabOrganizerGroupPill: View {

    let name: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(name).font(.system(size: 12, weight: .medium)).lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.18)))
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
        .contentShape(Rectangle())
        .help("Switch to this tab")
    }
}

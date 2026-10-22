//
//  TabGroupsManagementView.swift
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

import SwiftUI

struct TabGroupsManagementView: View {

    @ObservedObject var tabGroupManager: TabGroupManager
    let currentTabUUID: String?
    @State private var editingGroup: TabGroup?
    @State private var isCreatingGroup = false

    let onAddToGroup: ((TabGroup) -> Void)?
    let onRemoveFromGroup: (() -> Void)?
    let onDismiss: () -> Void

    init(
        tabGroupManager: TabGroupManager,
        currentTabUUID: String?,
        onAddToGroup: ((TabGroup) -> Void)? = nil,
        onRemoveFromGroup: (() -> Void)? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.tabGroupManager = tabGroupManager
        self.currentTabUUID = currentTabUUID
        self.onAddToGroup = onAddToGroup
        self.onRemoveFromGroup = onRemoveFromGroup
        self.onDismiss = onDismiss
    }

    /// Current tab's group (if any)
    private var currentTabGroupID: UUID? {
        guard let tabUUID = currentTabUUID else { return nil }
        return tabGroupManager.groupID(forTabUUID: tabUUID)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Groups list
            if tabGroupManager.groups.isEmpty {
                emptyState
            } else {
                groupsList
            }

            Divider()

            // Footer
            footerView
        }
        .frame(width: 400, height: 350)
        .sheet(item: $editingGroup) { group in
            TabGroupEditorView(
                mode: .edit(group),
                onSave: { name, color in
                    tabGroupManager.updateGroup(group, name: name, color: color)
                    editingGroup = nil
                },
                onCancel: { editingGroup = nil }
            )
        }
        .sheet(isPresented: $isCreatingGroup) {
            TabGroupEditorView(
                mode: .create,
                onSave: { name, color in
                    let newGroup = tabGroupManager.createGroup(name: name, color: color)
                    isCreatingGroup = false
                    // If we have a current tab, add it to the new group
                    if currentTabUUID != nil {
                        onAddToGroup?(newGroup)
                    }
                },
                onCancel: { isCreatingGroup = false }
            )
        }
    }

    private var headerView: some View {
        HStack {
            Text("Tab Groups")
                .font(.headline)

            Spacer()

            Button(action: { isCreatingGroup = true }) {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help("New Tab Group")
        }
        .padding()
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "folder.badge.plus")
                .font(.system(size: 40))
                .foregroundColor(.secondary)

            Text("No Tab Groups")
                .font(.headline)

            Text("Create a group to organize your tabs")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Button("Create Tab Group") {
                isCreatingGroup = true
            }
            .buttonStyle(.automatic)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var groupsList: some View {
        List {
            ForEach(tabGroupManager.groups) { group in
                let isCurrentTabInGroup = currentTabGroupID == group.id
                let tabCount = tabGroupManager.tabUUIDs(in: group).count

                TabGroupRowView(
                    group: group,
                    tabCount: tabCount,
                    isCurrentTabInGroup: isCurrentTabInGroup,
                    showTabActions: currentTabUUID != nil,
                    onAddToGroup: {
                        onAddToGroup?(group)
                        onDismiss()
                    },
                    onRemoveFromGroup: {
                        onRemoveFromGroup?()
                        onDismiss()
                    },
                    onEdit: { editingGroup = group },
                    onDelete: { tabGroupManager.unregisterGroup(group) }
                )
            }
        }
        .listStyle(.inset)
    }

    private var footerView: some View {
        HStack {
            Spacer()
            Button("Done") {
                onDismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding()
    }
}

// MARK: - Row View

private struct TabGroupRowView: View {

    let group: TabGroup
    let tabCount: Int
    let isCurrentTabInGroup: Bool
    let showTabActions: Bool
    let onAddToGroup: () -> Void
    let onRemoveFromGroup: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            // Color dot
            Circle()
                .fill(Color(group.color.nsColor))
                .frame(width: 12, height: 12)

            // Name and tab count
            Text(group.name)
                .lineLimit(1)

            if tabCount > 0 {
                Text("(\(tabCount))")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }

            Spacer()

            // Tab action button (add/remove from group)
            if showTabActions {
                if isCurrentTabInGroup {
                    Button(action: onRemoveFromGroup) {
                        HStack(spacing: 4) {
                            Image(systemName: "minus.circle")
                            Text("Remove")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button(action: onAddToGroup) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle")
                            Text("Add")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }
            }

            // Edit/Delete actions (show on hover)
            if isHovering {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help("Edit")

                Button(action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundColor(.red)
                .help("Delete")
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }
}

#Preview {
    let manager = TabGroupManager()
    manager.createGroup(name: "Work", color: .blue)
    manager.createGroup(name: "Personal", color: .green)
    manager.createGroup(name: "Research", color: .purple)

    return TabGroupsManagementView(
        tabGroupManager: manager,
        currentTabUUID: "test-tab-uuid",
        onAddToGroup: { _ in },
        onRemoveFromGroup: {},
        onDismiss: {}
    )
}

#Preview("Empty State") {
    TabGroupsManagementView(
        tabGroupManager: TabGroupManager(),
        currentTabUUID: nil,
        onAddToGroup: nil,
        onRemoveFromGroup: nil,
        onDismiss: {}
    )
}

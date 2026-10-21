//
//  TabOrganizerDebugMenu.swift
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
import os.log

/// Runs the organizer on the current window and shows the raw proposal, before any UI exists.
final class TabOrganizerDebugMenu: NSMenu {

    static let contentExcerptLength = 300

    init() {
        super.init(title: "")
        buildItems {
            NSMenuItem(title: "Group by Topic", action: #selector(groupByTopic)).targetting(self)
            NSMenuItem(title: "Group by Topic (with Page Content)", action: #selector(groupByTopicWithContent)).targetting(self)
            NSMenuItem(title: "Instruction…", action: #selector(instruction)).targetting(self)
        }
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @MainActor @objc private func groupByTopic() {
        run(.groupByTopic, excerptLength: 0)
    }

    @MainActor @objc private func groupByTopicWithContent() {
        run(.groupByTopic, excerptLength: Self.contentExcerptLength)
    }

    @MainActor @objc private func instruction() {
        let alert = NSAlert()
        alert.messageText = "Organize tabs"
        alert.informativeText = "What should happen to your tabs?"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = "Move my Japan trip to a new window"
        alert.accessoryView = field
        alert.addButton(withTitle: "Organize")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn, !field.stringValue.isEmpty else { return }
        run(.instruction(field.stringValue), excerptLength: 0)
    }

    @MainActor private func run(_ request: TabOrganizerRequest, excerptLength: Int) {
        guard #available(macOS 26.0, *) else {
            show("Tab organizer needs macOS 26 or later.")
            return
        }
        guard let collection = NSApp.delegateTyped.windowControllersManager.lastKeyMainWindowController?.mainViewController.tabCollectionViewModel else { return }

        Task { @MainActor in
            let start = Date()
            var tabs = TabSnapshotProvider.snapshots(in: collection)
            tabs = await TabSnapshotProvider.addingContent(to: tabs, in: collection, excerptLength: excerptLength)
            do {
                let proposal = try await AppleTabOrganizer().organize(tabs, request: request)
                let titles = Dictionary(uniqueKeysWithValues: tabs.map { ($0.id, $0.title) })
                let summary = proposal.groups.map { group in
                    "\(group.name) [\(group.action.rawValue)]\n" + group.tabIDs.map { "  • \(titles[$0] ?? $0)" }.joined(separator: "\n")
                }.joined(separator: "\n\n")
                let elapsed = String(format: "%.1f", Date().timeIntervalSince(start))
                Logger.aiChat.debug("Tab organizer (\(elapsed)s):\n\(summary)")
                show("\(tabs.count) tabs, \(elapsed)s\n\n\(summary)")
            } catch {
                show("Tab organizer failed: \(error)")
            }
        }
    }

    @MainActor private func show(_ text: String) {
        let alert = NSAlert()
        alert.messageText = "Tab organizer"
        alert.informativeText = text
        alert.runModal()
    }
}

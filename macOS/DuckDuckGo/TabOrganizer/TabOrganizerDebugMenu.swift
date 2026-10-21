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

    static let contentExcerptLength = 600

    init() {
        super.init(title: "")
        buildItems {
            NSMenuItem(title: "Group by Topic", action: #selector(groupByTopic)).targetting(self)
            NSMenuItem(title: "Group by Topic (with Page Content)", action: #selector(groupByTopicWithContent)).targetting(self)
            NSMenuItem(title: "Instruction…", action: #selector(instruction)).targetting(self)
            NSMenuItem.separator()
            NSMenuItem(title: "Open Demo Tabs", action: #selector(openDemoTabs)).targetting(self)
        }
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// A fixed mix of topics, plus duplicates and an empty tab, so every rehearsal starts the same.
    static let demoURLs = [
        "https://unsplash.com/s/photos/dachshund",
        "https://www.japan-guide.com/e/e2158.html",
        "https://www.jrailpass.com/",
        "https://www.japan-guide.com/e/e3013.html",
        "https://www.timeout.com/tokyo/restaurants/best-ramen-in-tokyo",
        "https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/",
        "https://developer.apple.com/documentation/testing",
        "https://github.com/duckduckgo/apple-browsers",
        "https://github.com/duckduckgo/apple-browsers/pulls",
        "https://www.rtings.com/headphones/reviews/best/by-type/noise-cancelling",
        "https://www.amazon.com/s?k=noise+cancelling+headphones",
        "https://www.bestbuy.com/site/searchpage.jsp?st=headphones",
        "https://www.bbc.com/news",
        "https://www.nytimes.com/",
        "https://www.netflix.com/",
        "https://www.disneyplus.com/",
        "https://en.wikipedia.org/wiki/Dachshund",
        "https://www.akc.org/dog-breeds/dachshund/",
        "https://www.reddit.com/r/Dachshund/",
        "https://www.etsy.com/search?q=dachshund",
        "https://en.wikipedia.org/wiki/Poodle",
        "https://www.akc.org/dog-breeds/poodle-standard/",
        "https://www.reddit.com/r/poodles/",
        "https://www.bbc.com/news",
        "https://www.nytimes.com/"
    ]

    @MainActor @objc private func openDemoTabs() {
        let tabs = Self.demoURLs.compactMap(URL.init(string:)).map { Tab(content: .contentFromURL($0, source: .ui)) }
            + [Tab(content: .newtab)]
        let collection = TabCollectionViewModel(tabCollection: TabCollection(tabs: tabs, isPopup: false))
        NSApp.delegateTyped.windowControllersManager.openNewWindow(with: collection, showWindow: true)
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
        let field = NSTextField(frame: NSRect(x: 0, y: 26, width: 320, height: 24))
        field.placeholderString = "Move my Japan trip to a new window"
        let readContent = NSButton(checkboxWithTitle: "Read page content (slower)", target: nil, action: nil)
        readContent.frame = NSRect(x: 0, y: 0, width: 320, height: 20)
        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 50))
        accessory.addSubview(field)
        accessory.addSubview(readContent)
        alert.accessoryView = accessory
        alert.addButton(withTitle: "Organize")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn, !field.stringValue.isEmpty else { return }
        run(.instruction(field.stringValue), excerptLength: readContent.state == .on ? Self.contentExcerptLength : 0)
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
                var summary = proposal.groups.map { group in
                    "\(group.name) [\(group.action.rawValue)]\n" + group.tabIDs.map { "  • \(titles[$0] ?? $0)" }.joined(separator: "\n")
                }.joined(separator: "\n\n")
                if case .instruction = request, proposal.groups.first?.name == TabOrganizerProposalBuilder.everythingElseGroupName {
                    summary = "No matching tabs.\n\n" + summary
                }
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

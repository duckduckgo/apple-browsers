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
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
        current = popover
    }
}

@MainActor
final class TabOrganizerViewModel: ObservableObject {

    @Published private(set) var tabs: [TabSnapshot]
    let favicons: [String: NSImage]

    init(tabCollectionViewModel: TabCollectionViewModel) {
        tabs = TabSnapshotProvider.snapshots(in: tabCollectionViewModel)
        let allTabs = (tabCollectionViewModel.pinnedTabsCollection?.tabs ?? []) + tabCollectionViewModel.tabCollection.tabs
        favicons = Dictionary(allTabs.compactMap { tab in tab.favicon.map { (tab.uuid, $0) } }, uniquingKeysWith: { first, _ in first })
    }
}

struct TabOrganizerView: View {

    @ObservedObject var viewModel: TabOrganizerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles")
                Text("Organize tabs").font(.headline)
                Spacer()
                Text("\(viewModel.tabs.count) tabs").foregroundColor(.secondary)
            }

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(viewModel.tabs, id: \.id) { tab in
                        TabOrganizerRow(tab: tab, favicon: viewModel.favicons[tab.id])
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 420, height: 480)
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

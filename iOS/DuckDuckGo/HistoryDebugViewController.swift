//
//  HistoryDebugViewController.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import UIKit
import SwiftUI
import History
import Core
import Persistence
import CoreData

class HistoryDebugViewController: UIHostingController<HistoryDebugRootView> {

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder, rootView: HistoryDebugRootView(tabManager: nil))
    }

}

struct HistoryDebugRootView: View {

    @StateObject private var model: HistoryDebugViewModel

    init(tabManager: TabManager?) {
        _model = StateObject(wrappedValue: HistoryDebugViewModel(tabManager: tabManager))
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("View Mode", selection: $model.viewMode) {
                ForEach(HistoryDebugViewModel.ViewMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            switch model.viewMode {
            case .allHistory:
                allHistoryList
            case .perTab:
                tabListView
            }
        }
        .navigationTitle(navigationTitle)
        .toolbar {
            if model.viewMode == .allHistory {
                Button("Delete All", role: .destructive) {
                    model.deleteAll()
                }
            }
        }
    }

    private var navigationTitle: String {
        switch model.viewMode {
        case .allHistory:
            return "\(model.displayItems.count) History Items"
        case .perTab:
            return "\(model.tabItems.count) Tabs"
        }
    }

    private var allHistoryList: some View {
        List(model.displayItems) { item in
            historyItemRow(item)
        }
    }

    private var tabListView: some View {
        List {
            Section {
                ForEach(model.tabItems) { tabItem in
                    NavigationLink {
                        TabHistoryDetailView(tabItem: tabItem, tabManager: model.tabManager)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(tabItem.title)
                                    .font(.system(size: 14, weight: tabItem.isCurrent ? .semibold : .regular))
                                if let url = tabItem.urlString {
                                    Text(url)
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            Text("\(tabItem.historyCount) items")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            } footer: {
                Text("Total stored: \(model.totalTabHistoryCount)")
                    .font(.system(size: 12))
            }
        }
    }

    private func historyItemRow(_ item: HistoryDisplayItem) -> some View {
        VStack(alignment: .leading) {
            Text(item.title)
                .font(.system(size: 14))
            Text(item.urlString)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            if let lastVisit = item.lastVisit {
                Text(lastVisit)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct TabHistoryDetailView: View {

    let tabItem: TabHistoryItem
    let tabManager: TabManager?
    @State private var historyItems: [HistoryDisplayItem] = []

    var body: some View {
        List(historyItems) { item in
            VStack(alignment: .leading) {
                Text(item.title)
                    .font(.system(size: 14))
                Text(item.urlString)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle(tabItem.title)
        .task {
            await loadHistory()
        }
    }

    @MainActor
    private func loadHistory() async {
        guard let tabManager = tabManager,
              tabItem.tabIndex < tabManager.model.tabs.count else {
            return
        }

        let tab = tabManager.model.tabs[tabItem.tabIndex]
        let urls = await tabManager.viewModel(for: tab).tabHistory()
        historyItems = urls.enumerated().map { HistoryDisplayItem(url: $1, index: $0) }
    }
}

struct TabHistoryItem: Identifiable {
    let id: String
    let tabIndex: Int
    let title: String
    let urlString: String?
    let historyCount: Int
    let isCurrent: Bool
}

struct HistoryDisplayItem: Identifiable {
    let id: String
    let title: String
    let urlString: String
    let lastVisit: String?

    init(managedObject: BrowsingHistoryEntryManagedObject) {
        self.id = managedObject.objectID.uriRepresentation().absoluteString
        self.title = managedObject.title ?? ""
        self.urlString = managedObject.url?.absoluteString ?? ""
        self.lastVisit = managedObject.lastVisit?.description
    }

    init(url: URL, index: Int) {
        self.id = "\(index)-\(url.absoluteString)"
        self.title = url.host ?? ""
        self.urlString = url.absoluteString
        self.lastVisit = nil
    }
}

@MainActor
class HistoryDebugViewModel: ObservableObject {

    enum ViewMode: String, CaseIterable {
        case allHistory = "All History"
        case perTab = "Per Tab"
    }

    @Published var viewMode: ViewMode = .allHistory {
        didSet { updateData() }
    }

    @Published private(set) var displayItems: [HistoryDisplayItem] = []
    @Published private(set) var tabItems: [TabHistoryItem] = []
    @Published private(set) var totalTabHistoryCount: Int = 0

    private let database: CoreDataDatabase
    private let context: NSManagedObjectContext
    let tabManager: TabManager?

    init(tabManager: TabManager?) {
        self.tabManager = tabManager
        self.database = HistoryDatabase.make()
        database.loadStore()
        self.context = database.makeContext(concurrencyType: .mainQueueConcurrencyType)

        updateData()
    }

    func deleteAll() {
        let fetchRequest = BrowsingHistoryEntryManagedObject.fetchRequest()
        let items = try? context.fetch(fetchRequest)
        items?.forEach { context.delete($0) }
        try? context.save()
        updateData()
    }

    private func updateData() {
        switch viewMode {
        case .allHistory:
            fetchAllHistory()
        case .perTab:
            fetchTotalTabHistoryCount()
            Task { await loadTabItems() }
        }
    }

    private func fetchTotalTabHistoryCount() {
        let fetchRequest = TabHistoryManagedObject.fetchRequest()
        totalTabHistoryCount = (try? context.count(for: fetchRequest)) ?? 0
    }

    private func fetchAllHistory() {
        let fetchRequest = BrowsingHistoryEntryManagedObject.fetchRequest()
        fetchRequest.returnsObjectsAsFaults = false
        let managedObjects = (try? context.fetch(fetchRequest)) ?? []
        displayItems = managedObjects.map { HistoryDisplayItem(managedObject: $0) }
    }

    private func loadTabItems() async {
        guard let tabManager = tabManager else {
            tabItems = []
            return
        }

        let currentTab = tabManager.model.currentTab
        var items: [TabHistoryItem] = []

        for (index, tab) in tabManager.model.tabs.enumerated() {
            let historyCount = await tabManager.viewModel(for: tab).tabHistory().count
            let isCurrent = tab === currentTab

            let title: String
            if let linkTitle = tab.link?.title, !linkTitle.isEmpty {
                title = linkTitle
            } else if let host = tab.link?.url.host {
                title = host
            } else {
                title = "Home"
            }

            let urlString = tab.link?.url.absoluteString

            items.append(TabHistoryItem(
                id: "\(index)",
                tabIndex: index,
                title: title,
                urlString: urlString,
                historyCount: historyCount,
                isCurrent: isCurrent
            ))
        }

        tabItems = items
    }
}

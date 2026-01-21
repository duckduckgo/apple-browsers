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

    @ObservedObject var model: HistoryDebugViewModel

    init(tabManager: TabManager?) {
        self.model = HistoryDebugViewModel(tabManager: tabManager)
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

            if model.viewMode == .perTab && !model.tabNames.isEmpty {
                Picker("Select Tab", selection: $model.selectedTabIndex) {
                    ForEach(model.tabNames.indices, id: \.self) { index in
                        Text(model.tabNames[index]).tag(index)
                    }
                }
                .pickerStyle(.menu)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            List(model.displayItems) { item in
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
            .id(model.viewMode)
        }
        .navigationTitle("\(model.displayItems.count) History Items")
        .toolbar {
            if model.viewMode == .allHistory {
                Button("Delete All", role: .destructive) {
                    model.deleteAll()
                }
            }
        }
    }

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
        didSet { updateHistoryEntries() }
    }

    @Published var selectedTabIndex: Int = 0 {
        didSet {
            updateHistoryEntries()
        }
    }

    @Published private(set) var displayItems: [HistoryDisplayItem] = []
    @Published private(set) var tabNames: [String] = []

    private let database: CoreDataDatabase
    private let context: NSManagedObjectContext
    private weak var tabManager: TabManager?

    init(tabManager: TabManager?) {
        self.tabManager = tabManager
        self.database = HistoryDatabase.make()
        database.loadStore()
        self.context = database.makeContext(concurrencyType: .mainQueueConcurrencyType)

        loadTabNames()
        updateHistoryEntries()
    }

    func deleteAll() {
        let fetchRequest = BrowsingHistoryEntryManagedObject.fetchRequest()
        let items = try? context.fetch(fetchRequest)
        items?.forEach { context.delete($0) }
        try? context.save()
        updateHistoryEntries()
    }

    private func updateHistoryEntries() {
        switch viewMode {
        case .allHistory:
            fetchAllHistory()
        case .perTab:
            Task { await fetchTabHistory() }
        }
    }

    private func fetchAllHistory() {
        let fetchRequest = BrowsingHistoryEntryManagedObject.fetchRequest()
        fetchRequest.returnsObjectsAsFaults = false
        let managedObjects = (try? context.fetch(fetchRequest)) ?? []
        displayItems = managedObjects.map { HistoryDisplayItem(managedObject: $0) }
    }

    private func fetchTabHistory() async {
        guard let tabManager = tabManager,
              selectedTabIndex >= 0,
              selectedTabIndex < tabManager.model.tabs.count else {
            displayItems = []
            return
        }

        let tab = tabManager.model.tabs[selectedTabIndex]
        let urls = await tabManager.viewModel(for: tab).tabHistory()
        displayItems = urls.enumerated().map { HistoryDisplayItem(url: $1, index: $0) }
    }

    private func loadTabNames() {
        guard let tabManager = tabManager else {
            tabNames = []
            return
        }

        let currentTab = tabManager.model.currentTab
        tabNames = tabManager.model.tabs.map { tab in
            let prefix = tab === currentTab ? "● " : ""
            if let title = tab.link?.title, !title.isEmpty {
                return prefix + title
            } else if let host = tab.link?.url.host {
                return prefix + host
            } else {
                return prefix + "Home"
            }
        }
    }
}

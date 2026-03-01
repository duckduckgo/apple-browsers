//
//  TabsModelProvider.swift
//  DuckDuckGo
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

import Foundation
import Combine

protocol ReadableTabCollection {
    var count: Int { get }
    var tabs: [Tab] { get }
}

extension ReadableTabCollection {
    func indexOf(tab: Tab) -> Int? {
        return tabs.firstIndex { $0 === tab }
    }
}

protocol MutableTabCollection: AnyObject, ReadableTabCollection {
    var shouldCreateFireTabs: Bool { get }
    var tabsPublisher: AnyPublisher<[Tab], Never> { get }
    var currentTab: Tab? { get }
    var currentIndex: Int { get }
    var hasUnread: Bool { get }
    var hasActiveTabs: Bool { get }
    func select(tabAt index: Int)
    func get(tabAt index: Int) -> Tab
    func add(tab: Tab)
    func insert(tab: Tab, at index: Int)
    func moveTab(from sourceIndex: Int, to destIndex: Int)
    func remove(at index: Int)
    /// This *does not* add a new empty tab after removing the items.
    func remove(_ indexPaths: [IndexPath])
    func remove(tab: Tab)
    func clearAll()
    func tabExists(withHost host: String) -> Bool
}

protocol TabsModelProviding {
    var normalTabsModel: MutableTabCollection { get }
    var fireModeTabsModel: MutableTabCollection { get }
    var aggregateTabsModel: ReadableTabCollection { get }
    func save()
}

class TabsModelProvider: TabsModelProviding {
    
    private var _normalTabsModel: TabsModel
    var normalTabsModel: MutableTabCollection {
        _normalTabsModel
    }
    private var _fireModeTabsModel: TabsModel
    var fireModeTabsModel: MutableTabCollection {
        _fireModeTabsModel
    }
    private(set) var aggregateTabsModel: ReadableTabCollection
    private var persistence: TabsModelPersisting

    
    init(normalTabsModel: TabsModel, fireModeTabsModel: TabsModel, persistence: TabsModelPersisting) {
        self._normalTabsModel = normalTabsModel
        self._fireModeTabsModel = fireModeTabsModel
        self.persistence = persistence
        self.aggregateTabsModel = AggregateTabsModel(normalTabsModel: normalTabsModel, fireModeTabsModel: fireModeTabsModel)
    }
    
    func save() {
        persistence.save(model: _normalTabsModel, for: .normal)
        persistence.save(model: _fireModeTabsModel, for: .fire)
    }
}

private extension TabsModelProvider {
    class AggregateTabsModel: ReadableTabCollection {
        private var normalTabsModel: ReadableTabCollection
        private var fireModeTabsModel: ReadableTabCollection
        
        init(normalTabsModel: ReadableTabCollection, fireModeTabsModel: ReadableTabCollection) {
            self.normalTabsModel = normalTabsModel
            self.fireModeTabsModel = fireModeTabsModel
        }
        
        var count: Int {
            normalTabsModel.count + fireModeTabsModel.count
        }
        
        var tabs: [Tab] {
            // TODO: - Consider removing duplicates, even though there shouldn't be any
            normalTabsModel.tabs + fireModeTabsModel.tabs
        }
    }
}

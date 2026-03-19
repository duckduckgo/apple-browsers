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
import PrivacyConfig

protocol TabsModelReading {
    var count: Int { get }
    var tabs: [Tab] { get }
}

extension TabsModelReading {
    func indexOf(tab: Tab) -> Int? {
        return tabs.firstIndex { $0 === tab }
    }
    
    var isEmpty: Bool {
        tabs.isEmpty
    }
}

protocol TabsModelManaging: AnyObject, TabsModelReading {
    var shouldCreateFireTabs: Bool { get }
    var allowsEmpty: Bool { get }
    var tabsPublisher: AnyPublisher<[Tab], Never> { get }
    var currentTab: Tab? { get }
    var nextTab: Tab? { get }
    var previousTab: Tab? { get }
    var tabBefore: Tab? { get }
    var currentIndex: Int? { get }
    var hasUnread: Bool { get }
    var hasActiveTabs: Bool { get }
    func select(tab: Tab)
    func get(tabAt index: Int?) -> Tab?
    func insert(tab: Tab, placement: TabsModel.TabPlacement, selectNewTab: Bool)
    func move(tab: Tab, to destIndex: Int)
    /// This *does not* add a new empty tab after removing the items.
    func removeTabs(_ tabs: [Tab])
    func remove(tab: Tab)
    func clearAll()
    func tabExists(tab: Tab) -> Bool
    func tabExists(withHost host: String) -> Bool
}

protocol TabsModelProviding {
    var normalTabsModel: TabsModelManaging { get }
    var fireModeTabsModel: TabsModelManaging { get }
    var aggregateTabsModel: TabsModelReading { get }
    /// Clears tabs for the given browsing mode, or all tabs if `nil`.
    func clearTabs(for browsingMode: BrowsingMode?)
    func save() -> Result<Void, Error>
}

class TabsModelProvider: TabsModelProviding {
    
    private var _normalTabsModel: TabsModel
    var normalTabsModel: TabsModelManaging {
        _normalTabsModel
    }
    private var _fireModeTabsModel: TabsModel
    var fireModeTabsModel: TabsModelManaging {
        _fireModeTabsModel
    }
    private(set) var aggregateTabsModel: TabsModelReading
    private var persistence: TabsModelPersisting

    
    init(normalTabsModel: TabsModel, fireModeTabsModel: TabsModel, persistence: TabsModelPersisting, featureFlagger: FeatureFlagger) {
        self._normalTabsModel = normalTabsModel
        self._fireModeTabsModel = fireModeTabsModel
        self.persistence = persistence
        let capability = FireModeCapability.create(using: featureFlagger)
        self.aggregateTabsModel = capability.isFireModeEnabled ? AggregateTabsModel(normalTabsModel: normalTabsModel, fireModeTabsModel: fireModeTabsModel) : normalTabsModel
    }
    
    func clearTabs(for browsingMode: BrowsingMode?) {
        switch browsingMode {
        case .normal:
            _normalTabsModel.clearAll()
        case .fire:
            _fireModeTabsModel.clearAll()
        case nil:
            _normalTabsModel.clearAll()
            _fireModeTabsModel.clearAll()
        }
    }

    func save() -> Result<Void, Error> {
        let normalResult = persistence.save(model: _normalTabsModel, for: .normal)
        let fireResult = persistence.save(model: _fireModeTabsModel, for: .fire)

        if case .failure(let error) = normalResult {
            return .failure(error)
        }
        if case .failure(let error) = fireResult {
            return .failure(error)
        }
        return .success(())
    }
}

private extension TabsModelProvider {
    class AggregateTabsModel: TabsModelReading {
        private var normalTabsModel: TabsModelReading
        private var fireModeTabsModel: TabsModelReading
        
        init(normalTabsModel: TabsModelReading, fireModeTabsModel: TabsModelReading) {
            self.normalTabsModel = normalTabsModel
            self.fireModeTabsModel = fireModeTabsModel
        }
        
        var count: Int {
            normalTabsModel.count + fireModeTabsModel.count
        }
        
        var tabs: [Tab] {
            normalTabsModel.tabs + fireModeTabsModel.tabs
        }
    }
}

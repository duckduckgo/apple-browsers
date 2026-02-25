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

protocol ReadableTabCollection {
    var count: Int { get }
}

protocol MutableTabCollection: ReadableTabCollection {
    
}

protocol TabsModelProviding {
    var normalTabsModel: MutableTabCollection { get }
    var fireModeTabsModel: MutableTabCollection { get }
    var aggregateTabsModel: ReadableTabCollection { get }
}

class TabsModelProvider: TabsModelProviding {
    
    private(set) var normalTabsModel: MutableTabCollection
    private(set) var fireModeTabsModel: MutableTabCollection
    private(set) var aggregateTabsModel: ReadableTabCollection
    
    init(normalTabsModel: TabsModel, fireModeTabsModel: TabsModel) {
        self.normalTabsModel = normalTabsModel
        self.fireModeTabsModel = fireModeTabsModel
        self.aggregateTabsModel = AggregateTabsModel(normalTabsModel: normalTabsModel, fireModeTabsModel: fireModeTabsModel)
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
    }
}

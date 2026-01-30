//
//  MockTabManager.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
@testable import DuckDuckGo

@MainActor
class MockTabManager: TabManaging {
    nonisolated(unsafe) var count: Int = 0
    private(set) var prepareAllTabsExceptCurrentCalled = false
    private(set) var prepareCurrentTabCalled = false
    nonisolated(unsafe) private(set) var removeAllCalled = false
    
    func prepareAllTabsExceptCurrentForDataClearing() {
        prepareAllTabsExceptCurrentCalled = true
    }
    
    func prepareCurrentTabForDataClearing() {
        prepareCurrentTabCalled = true
    }
    
    nonisolated func removeAll() {
        removeAllCalled = true
    }

    func viewModelForCurrentTab() -> DuckDuckGo.TabViewModel? {
        return nil
    }
}

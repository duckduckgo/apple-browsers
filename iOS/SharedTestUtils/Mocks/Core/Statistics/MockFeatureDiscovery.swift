//
//  MockFeatureDiscovery.swift
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

@testable import Core

class MockFeatureDiscovery: FeatureDiscovery {
    
    private var wasUsedBeforeValues: [WasUsedBeforeFeature: Bool] = [:]
    private var setWasUsedBeforeCalls: [WasUsedBeforeFeature] = []
    
    func setReturnValue(_ value: Bool, for feature: WasUsedBeforeFeature) {
        wasUsedBeforeValues[feature] = value
    }
    
    var setWasUsedBeforeCallCount: Int {
        setWasUsedBeforeCalls.count
    }
    
    func wasSetWasUsedBeforeCalled(for feature: WasUsedBeforeFeature) -> Bool {
        setWasUsedBeforeCalls.contains(feature)
    }
    
    func reset() {
        wasUsedBeforeValues.removeAll()
        setWasUsedBeforeCalls.removeAll()
    }

    func setWasUsedBefore(_ feature: WasUsedBeforeFeature) {
        setWasUsedBeforeCalls.append(feature)
    }
    
    func wasUsedBefore(_ feature: WasUsedBeforeFeature) -> Bool {
        return wasUsedBeforeValues[feature] ?? false
    }
    
    func addToParams(_ params: [String: String], forFeature feature: Core.WasUsedBeforeFeature) -> [String: String] {
        var updatedParams = params
        let wasUsed = wasUsedBefore(feature)
        updatedParams["was_used_before"] = wasUsed ? "1" : "0"
        return updatedParams
    }
}

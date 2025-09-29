//
//  FreeTrialBadgePersistor.swift
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
import Persistence

protocol FreeTrialBadgePersisting {
    var viewCount: Int { get }
    var hasReachedViewLimit: Bool { get }
    func incrementViewCount()
}

struct FreeTrialBadgePersistor: FreeTrialBadgePersisting {

    private enum Key: String {
        case freeTrialBadgeViewCount = "free-trial-badge.view-count"
    }

    private static let maxViewCount = 4

    private let keyValueStore: KeyValueStoring

    init(keyValueStore: KeyValueStoring) {
        self.keyValueStore = keyValueStore
    }

    var viewCount: Int {
        keyValueStore.object(forKey: Key.freeTrialBadgeViewCount.rawValue) as? Int ?? 0
    }

    var hasReachedViewLimit: Bool {
        viewCount >= Self.maxViewCount
    }

    func incrementViewCount() {
        let currentCount = viewCount
        if currentCount < Self.maxViewCount {
            keyValueStore.set(currentCount + 1, forKey: Key.freeTrialBadgeViewCount.rawValue)
        }
    }
}

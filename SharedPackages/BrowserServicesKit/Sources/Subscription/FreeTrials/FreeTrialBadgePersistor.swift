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

public protocol FreeTrialBadgePersisting {
    var viewCount: Int { get }
    var hasReachedViewLimit: Bool { get }
    func incrementViewCount()
}

public struct FreeTrialBadgePersistor: FreeTrialBadgePersisting {

    private enum Key: String {
        case freeTrialBadgeViewCount = "free-trial-badge.view-count"
    }

    private static let maxViewCount = 4

    private let keyValueStore: KeyValueStoring
    private let keyPrefix: String?

    var freeTrialBadgeViewCountKey: String {
        guard let keyPrefix else {
            return Key.freeTrialBadgeViewCount.rawValue
        }
        return "\(keyPrefix).\(Key.freeTrialBadgeViewCount.rawValue)"
    }

    public init(keyValueStore: KeyValueStoring, keyPrefix: String? = nil) {
        self.keyValueStore = keyValueStore
        self.keyPrefix = keyPrefix
    }

    public var viewCount: Int {
        return keyValueStore.object(forKey: freeTrialBadgeViewCountKey) as? Int ?? 0
    }

    public var hasReachedViewLimit: Bool {
        viewCount >= Self.maxViewCount
    }

    public func incrementViewCount() {
        let currentCount = viewCount
        if currentCount < Self.maxViewCount {
            keyValueStore.set(currentCount + 1, forKey: freeTrialBadgeViewCountKey)
        }
    }
}

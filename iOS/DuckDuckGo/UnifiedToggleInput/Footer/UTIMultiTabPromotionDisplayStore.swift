//
//  UTIMultiTabPromotionDisplayStore.swift
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

import Common
import Foundation
import Persistence

protocol UTIFooterDisplayStoring {
    var displayCount: Int { get }
    func recordDisplay()
    func reset()
}

protocol UTIMultiTabPromotionDisplayStoring: UTIFooterDisplayStoring {
    func isAvailable(startDate: Date?, isCurrentDisplay: Bool) -> Bool
    func dismiss()
    func recordTabAttachment()
}

struct UTIMultiTabPromotionDisplayStore: UTIMultiTabPromotionDisplayStoring {
    private enum Key: String {
        case displayCount = "aichat.multi-tab-promotion.display-count"
        case dismissed = "aichat.multi-tab-promotion.dismissed"
        case hasAttachedTab = "aichat.multi-tab-promotion.has-attached-tab"
    }

    private static let displayLimit = 3
    private static let promotionDuration: TimeInterval = 30 * 24 * 60 * 60
    private let keyValueStore: ThrowingKeyValueStoring
    private let dateProvider: CurrentDateProviding

    init(keyValueStore: ThrowingKeyValueStoring = UserDefaults.standard,
         dateProvider: CurrentDateProviding = DefaultCurrentDateProvider()) {
        self.keyValueStore = keyValueStore
        self.dateProvider = dateProvider
    }

    var displayCount: Int {
        max(0, (try? keyValueStore.object(forKey: Key.displayCount.rawValue) as? Int) ?? 0)
    }

    var hasAttachedTab: Bool {
        (try? keyValueStore.object(forKey: Key.hasAttachedTab.rawValue) as? Bool) ?? false
    }

    func isAvailable(startDate: Date?, isCurrentDisplay: Bool) -> Bool {
        guard !hasAttachedTab, let startDate else { return false }
        let now = dateProvider.currentDate
        let dismissed = (try? keyValueStore.object(forKey: Key.dismissed.rawValue) as? Bool) ?? false
        return !dismissed && now >= startDate && now < startDate.addingTimeInterval(Self.promotionDuration)
            && (isCurrentDisplay || displayCount < Self.displayLimit)
    }

    func recordDisplay() {
        let count = displayCount
        guard count < Self.displayLimit else { return }
        try? keyValueStore.set(count + 1, forKey: Key.displayCount.rawValue)
    }

    func dismiss() {
        try? keyValueStore.set(true, forKey: Key.dismissed.rawValue)
    }

    func recordTabAttachment() {
        guard !hasAttachedTab else { return }
        try? keyValueStore.set(true, forKey: Key.hasAttachedTab.rawValue)
    }

    func reset() {
        try? keyValueStore.removeObject(forKey: Key.displayCount.rawValue)
    }

#if DEBUG || ALPHA
    func resetForDebugging() {
        reset()
        try? keyValueStore.removeObject(forKey: Key.dismissed.rawValue)
        try? keyValueStore.removeObject(forKey: Key.hasAttachedTab.rawValue)
    }
#endif
}

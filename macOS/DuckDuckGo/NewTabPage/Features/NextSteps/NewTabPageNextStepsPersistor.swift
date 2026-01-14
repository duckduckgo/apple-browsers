//
//  NewTabPageNextStepsPersistor.swift
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
import NewTabPage
import Persistence

protocol NewTabPageNextStepsCardsPersisting {
    func timesShown(for card: NewTabPageDataModel.CardID) -> Int
    func setTimesShown(_ value: Int, for card: NewTabPageDataModel.CardID)
    func timesDismissed(for card: NewTabPageDataModel.CardID) -> Int
    func setTimesDismissed(_ value: Int, for card: NewTabPageDataModel.CardID)
    func incrementTimesShown(for card: NewTabPageDataModel.CardID)
    func incrementTimesDismissed(for card: NewTabPageDataModel.CardID)

    /// Clear all persisted data about next steps cards.
    /// This is used in the Debug menu to reset the Next Steps cards for testing.
    func clear()
}

final class NewTabPageNextStepsCardsPersistor: NewTabPageNextStepsCardsPersisting {
    private let keyValueStore: ThrowingKeyValueStoring
    private let lock = NSLock()

    init(keyValueStore: ThrowingKeyValueStoring) {
        self.keyValueStore = keyValueStore
    }

    func timesShown(for card: NewTabPageDataModel.CardID) -> Int {
        lock.lock()
        defer {
            lock.unlock()
        }
        return (try? keyValueStore.object(forKey: shownKey(for: card)) as? Int) ?? 0
    }

    func setTimesShown(_ value: Int, for card: NewTabPageDataModel.CardID) {
        lock.lock()
        defer {
            lock.unlock()
        }
        try? keyValueStore.set(value, forKey: shownKey(for: card))
    }

    func timesDismissed(for card: NewTabPageDataModel.CardID) -> Int {
        lock.lock()
        defer {
            lock.unlock()
        }
        return (try? keyValueStore.object(forKey: dismissedKey(for: card)) as? Int) ?? 0
    }

    func setTimesDismissed(_ value: Int, for card: NewTabPageDataModel.CardID) {
        lock.lock()
        defer {
            lock.unlock()
        }
        try? keyValueStore.set(value, forKey: dismissedKey(for: card))
    }

    func incrementTimesShown(for card: NewTabPageDataModel.CardID) {
        lock.lock()
        defer {
            lock.unlock()
        }
        let current = (try? keyValueStore.object(forKey: shownKey(for: card)) as? Int) ?? 0
        try? keyValueStore.set(current + 1, forKey: shownKey(for: card))
    }

    func incrementTimesDismissed(for card: NewTabPageDataModel.CardID) {
        lock.lock()
        defer {
            lock.unlock()
        }
        let current = (try? keyValueStore.object(forKey: dismissedKey(for: card)) as? Int) ?? 0
        try? keyValueStore.set(current + 1, forKey: dismissedKey(for: card))
    }

    func clear() {
        lock.lock()
        defer {
            lock.unlock()
        }
        for card in NewTabPageDataModel.CardID.allCases {
            try? keyValueStore.removeObject(forKey: shownKey(for: card))
            try? keyValueStore.removeObject(forKey: dismissedKey(for: card))
        }
    }

    private func shownKey(for card: NewTabPageDataModel.CardID) -> String {
        "new.tab.page.next.steps.\(card.rawValue).card.times.shown"
    }

    private func dismissedKey(for card: NewTabPageDataModel.CardID) -> String {
        "new.tab.page.next.steps.\(card.rawValue).card.times.dismissed"
    }
}

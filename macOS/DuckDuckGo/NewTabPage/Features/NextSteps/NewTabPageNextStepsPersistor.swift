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
    func clear()
}

final class NewTabPageNextStepsCardsPersistor: NewTabPageNextStepsCardsPersisting {
    private let keyValueStore: ThrowingKeyValueStoring

    init(keyValueStore: ThrowingKeyValueStoring) {
        self.keyValueStore = keyValueStore
    }

    func timesShown(for card: NewTabPageDataModel.CardID) -> Int {
        (try? keyValueStore.object(forKey: shownKey(for: card)) as? Int) ?? 0
    }

    func setTimesShown(_ value: Int, for card: NewTabPageDataModel.CardID) {
        try? keyValueStore.set(value, forKey: shownKey(for: card))
    }

    func timesDismissed(for card: NewTabPageDataModel.CardID) -> Int {
        (try? keyValueStore.object(forKey: dismissedKey(for: card)) as? Int) ?? 0
    }

    func setTimesDismissed(_ value: Int, for card: NewTabPageDataModel.CardID) {
        try? keyValueStore.set(value, forKey: dismissedKey(for: card))
    }

    func incrementTimesShown(for card: NewTabPageDataModel.CardID) {
        let current = timesShown(for: card)
        setTimesShown(current + 1, for: card)
    }

    func incrementTimesDismissed(for card: NewTabPageDataModel.CardID) {
        let current = timesDismissed(for: card)
        setTimesDismissed(current + 1, for: card)
    }

    func clear() {
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

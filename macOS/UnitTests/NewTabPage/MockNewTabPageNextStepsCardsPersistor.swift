//
//  MockNewTabPageNextStepsCardsPersistor.swift
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
@testable import DuckDuckGo_Privacy_Browser

final class MockNewTabPageNextStepsCardsPersistor: NewTabPageNextStepsCardsPersisting {
    private var timesShownStorage: [NewTabPageDataModel.CardID: Int] = [:]
    private var timesDismissedStorage: [NewTabPageDataModel.CardID: Int] = [:]

    func timesShown(for card: NewTabPageDataModel.CardID) -> Int {
        timesShownStorage[card] ?? 0
    }

    func setTimesShown(_ value: Int, for card: NewTabPageDataModel.CardID) {
        timesShownStorage[card] = value
    }

    func timesDismissed(for card: NewTabPageDataModel.CardID) -> Int {
        timesDismissedStorage[card] ?? 0
    }

    func setTimesDismissed(_ value: Int, for card: NewTabPageDataModel.CardID) {
        timesDismissedStorage[card] = value
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
        timesShownStorage.removeAll()
        timesDismissedStorage.removeAll()
    }
}

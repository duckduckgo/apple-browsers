//
//  MockPromoHistoryStore.swift
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
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
@testable import DuckDuckGo_Privacy_Browser

final class MockPromoHistoryStore: PromoHistoryStoring {

    private var records: [String: PromoHistoryRecord] = [:]

    private(set) var recordCallCount = 0
    private(set) var saveCallCount = 0
    private(set) var resetAllCallCount = 0

    init(records: [String: PromoHistoryRecord] = [:]) {
        self.records = records
    }

    func record(for promoId: String) -> PromoHistoryRecord {
        recordCallCount += 1
        return records[promoId] ?? PromoHistoryRecord(id: promoId)
    }

    func save(_ record: PromoHistoryRecord) {
        saveCallCount += 1
        records[record.id] = record
    }

    func resetAll() {
        resetAllCallCount += 1
        records = [:]
    }
}

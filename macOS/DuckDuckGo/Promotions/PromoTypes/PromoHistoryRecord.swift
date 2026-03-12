//
//  PromoHistoryRecord.swift
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

struct PromoHistoryRecord: Codable, Equatable {
    let id: String
    var timesDismissed: Int
    var lastDismissed: Date?
    var lastShown: Date?
    var nextEligibleDate: Date?
    var actioned: Bool

    var isPermanentlyDismissed: Bool {
        nextEligibleDate == .distantFuture
    }

    /// Whether the promo is now eligible to be shown, e.g. after a cooldown.
    var isEligible: Bool {
        isEligible(asOf: Date())
    }

    /// Debug: Whether the promo is eligible as of a specified (simulated) date.
    func isEligible(asOf date: Date) -> Bool {
        guard !actioned else { return false }
        guard let nextEligibleDate else { return true }
        return nextEligibleDate <= date
    }

    init(id: String) {
        self.id = id
        self.timesDismissed = 0
        self.lastDismissed = nil
        self.lastShown = nil
        self.nextEligibleDate = nil
        self.actioned = false
    }
}

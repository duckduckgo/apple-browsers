//
//  AutoconsentStatsMock.swift
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

import AutoconsentStats
import Combine
import Foundation

final class AutoconsentStatsMock: AutoconsentStatsCollecting {
    private(set) var clearAutoconsentStatsCalled = false
    private(set) var recordAutoconsentActionCalled = false

    private var totalCookiePopUpsBlocked: Int64 = 0
    private var totalClicksMade: Int64 = 0
    private var totalTimeSpent: TimeInterval = 0

    var statsUpdatePublisher: AnyPublisher<Void, Never> {
        statsUpdateSubject.eraseToAnyPublisher()
    }

    private let statsUpdateSubject = PassthroughSubject<Void, Never>()

    var isEnabledValue: Bool = true

    func recordAutoconsentAction(clicksMade: Int64, timeSpent: TimeInterval) async {
        recordAutoconsentActionCalled = true
        totalCookiePopUpsBlocked += 1
        totalClicksMade += clicksMade
        totalTimeSpent += timeSpent
        statsUpdateSubject.send()
    }

    func fetchTotalCookiePopUpsBlocked() async -> Int64 {
        return totalCookiePopUpsBlocked
    }

    func fetchAutoconsentDailyUsagePack() async -> AutoconsentDailyUsagePack {
        return AutoconsentDailyUsagePack(
            totalCookiePopUpsBlocked: totalCookiePopUpsBlocked,
            totalClicksMadeBlockingCookiePopUps: totalClicksMade,
            totalTotalTimeSpentBlockingCookiePopUps: totalTimeSpent
        )
    }

    func clearAutoconsentStats() async {
        clearAutoconsentStatsCalled = true
        totalCookiePopUpsBlocked = 0
        totalClicksMade = 0
        totalTimeSpent = 0
        statsUpdateSubject.send()
    }

    func isEnabled() async -> Bool {
        return isEnabledValue
    }
}

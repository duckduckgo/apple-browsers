//
//  SettingsNextStepsDismissalTests.swift
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

import Foundation
import Testing
@testable import DuckDuckGo

@Suite("Settings Next Steps Dismissal")
struct SettingsNextStepsDismissalTests {

    private let oneDay: TimeInterval = 24 * 60 * 60
    private let tappedAt: TimeInterval = 1_000_000

    @Test("Item stays visible when never tapped", .timeLimit(.minutes(1)))
    func itemStaysVisibleWhenNeverTapped() {
        #expect(!SettingsViewModel.hasTapDismissalElapsed(tappedAt: nil, now: tappedAt, interval: oneDay))
    }

    @Test("Item stays visible before interval elapses", .timeLimit(.minutes(1)))
    func itemStaysVisibleBeforeIntervalElapses() {
        #expect(!SettingsViewModel.hasTapDismissalElapsed(tappedAt: tappedAt,
                                                          now: tappedAt + oneDay - 1,
                                                          interval: oneDay))
    }

    @Test("Item dismisses exactly at interval", .timeLimit(.minutes(1)))
    func itemDismissesExactlyAtInterval() {
        #expect(SettingsViewModel.hasTapDismissalElapsed(tappedAt: tappedAt,
                                                         now: tappedAt + oneDay,
                                                         interval: oneDay))
    }

    @Test("Item dismisses after interval", .timeLimit(.minutes(1)))
    func itemDismissesAfterInterval() {
        #expect(SettingsViewModel.hasTapDismissalElapsed(tappedAt: tappedAt,
                                                         now: tappedAt + oneDay + 60,
                                                         interval: oneDay))
    }

    // MARK: - hasInstallGracePeriodElapsed (Next Steps "Hide" 14-day install gate)

    private let fourteenDays: TimeInterval = 14 * 24 * 60 * 60
    private let installedAt = Date(timeIntervalSinceReferenceDate: 1_000_000)

    @Test("Hide button hidden when install date missing", .timeLimit(.minutes(1)))
    func hideButtonHiddenWhenInstallDateMissing() {
        #expect(!SettingsViewModel.hasInstallGracePeriodElapsed(installDate: nil,
                                                               now: installedAt,
                                                               requiredInterval: fourteenDays))
    }

    @Test("Hide button hidden just before grace period elapses", .timeLimit(.minutes(1)))
    func hideButtonHiddenJustBeforeGracePeriodElapses() {
        let now = Date(timeIntervalSinceReferenceDate: installedAt.timeIntervalSinceReferenceDate + fourteenDays - 1)
        #expect(!SettingsViewModel.hasInstallGracePeriodElapsed(installDate: installedAt,
                                                               now: now,
                                                               requiredInterval: fourteenDays))
    }

    @Test("Hide button appears exactly at grace period", .timeLimit(.minutes(1)))
    func hideButtonAppearsExactlyAtGracePeriod() {
        let now = Date(timeIntervalSinceReferenceDate: installedAt.timeIntervalSinceReferenceDate + fourteenDays)
        #expect(SettingsViewModel.hasInstallGracePeriodElapsed(installDate: installedAt,
                                                              now: now,
                                                              requiredInterval: fourteenDays))
    }

    @Test("Hide button appears well after grace period", .timeLimit(.minutes(1)))
    func hideButtonAppearsWellAfterGracePeriod() {
        let now = Date(timeIntervalSinceReferenceDate: installedAt.timeIntervalSinceReferenceDate + fourteenDays * 3)
        #expect(SettingsViewModel.hasInstallGracePeriodElapsed(installDate: installedAt,
                                                              now: now,
                                                              requiredInterval: fourteenDays))
    }
}

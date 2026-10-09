//
//  IdleReturnInfoTests.swift
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

import Testing
@testable import DuckDuckGo

@available(iOS 16, macOS 13, *)
struct IdleReturnInfoTests {

    private let ntp = IdleReturnOutcome.afterIdle(treatment: .ntp, timeAwayMs: 61_000)

    @Test("An after-idle New Tab Page is drawn at launch", .timeLimit(.minutes(1)))
    func afterIdleNTPIsDrawnAtLaunch() {
        let info = IdleReturnInfo(outcome: ntp, isAppLockEnabled: false, clearsTabsOnLaunch: false)
        #expect(info.newTabPageDrawnAtLaunch)
        #expect(info.outcome == ntp)
    }

    @Test("With App Lock on the New Tab Page is not drawn at launch, but the outcome is kept", .timeLimit(.minutes(1)))
    func appLockKeepsOutcomeWithoutDrawing() {
        let info = IdleReturnInfo(outcome: ntp, isAppLockEnabled: true, clearsTabsOnLaunch: false)
        #expect(!info.newTabPageDrawnAtLaunch)
        #expect(info.outcome == ntp)
    }

    @Test("When tabs are cleared on launch the New Tab Page is not drawn at launch, but the outcome is kept", .timeLimit(.minutes(1)))
    func clearingTabsKeepsOutcomeWithoutDrawing() {
        let info = IdleReturnInfo(outcome: ntp, isAppLockEnabled: false, clearsTabsOnLaunch: true)
        #expect(!info.newTabPageDrawnAtLaunch)
        #expect(info.outcome == ntp)
    }

    @Test("A last-used-tab return is not drawn at launch", .timeLimit(.minutes(1)))
    func lastUsedTabIsNotDrawnAtLaunch() {
        let lut = IdleReturnOutcome.afterIdle(treatment: .lut, timeAwayMs: 61_000)
        let info = IdleReturnInfo(outcome: lut, isAppLockEnabled: false, clearsTabsOnLaunch: false)
        #expect(!info.newTabPageDrawnAtLaunch)
        #expect(info.outcome == lut)
    }

    @Test("An ordinary return is not drawn at launch", .timeLimit(.minutes(1)))
    func ordinaryReturnIsNotDrawnAtLaunch() {
        let ordinary = IdleReturnOutcome.ordinary(timeAwayMs: 5_000)
        let info = IdleReturnInfo(outcome: ordinary, isAppLockEnabled: false, clearsTabsOnLaunch: false)
        #expect(!info.newTabPageDrawnAtLaunch)
        #expect(info.outcome == ordinary)
    }

}

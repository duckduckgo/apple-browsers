//
//  IdleReturnLaunchLandingTests.swift
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
struct IdleReturnLaunchLandingTests {

    private let ntp = IdleReturnOutcome.afterIdle(treatment: .ntp, timeAwayMs: 61_000)

    @Test("An after-idle New Tab Page replacing a restored page is drawn at launch", .timeLimit(.minutes(1)))
    func afterIdleNTPIsDrawnAtLaunch() {
        #expect(ntp.drawsNewTabPageAtLaunch(isAppLockEnabled: false, hasPageToReplace: true))
    }

    @Test("With App Lock on the New Tab Page is not drawn at launch", .timeLimit(.minutes(1)))
    func appLockIsNotDrawnAtLaunch() {
        #expect(!ntp.drawsNewTabPageAtLaunch(isAppLockEnabled: true, hasPageToReplace: true))
    }

    @Test("With no restored page to replace the New Tab Page is not drawn at launch", .timeLimit(.minutes(1)))
    func noPageToReplaceIsNotDrawnAtLaunch() {
        #expect(!ntp.drawsNewTabPageAtLaunch(isAppLockEnabled: false, hasPageToReplace: false))
    }

    @Test("Last-used-tab and ordinary returns are not drawn at launch", .timeLimit(.minutes(1)),
          arguments: [IdleReturnOutcome.afterIdle(treatment: .lut, timeAwayMs: 61_000), .ordinary(timeAwayMs: 5_000)])
    func otherOutcomesAreNotDrawnAtLaunch(outcome: IdleReturnOutcome) {
        #expect(!outcome.drawsNewTabPageAtLaunch(isAppLockEnabled: false, hasPageToReplace: true))
    }

}

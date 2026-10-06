//
//  EventHubSchedulerTests.swift
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
@testable import EventHub

@Suite("ManualEventHubScheduler")
struct EventHubSchedulerTests {
    @Test("fires the armed action once the deadline is reached")
    func firesArmedActionOnceDeadlineReached() {
        let scheduler = ManualEventHubScheduler(startMillis: 0)
        var fired = false
        scheduler.arm(atMillis: 1000) { fired = true }
        scheduler.advance(by: 0.5)
        #expect(!fired)
        scheduler.advance(by: 0.5)
        #expect(fired)
    }

    @Test("re-arming replaces the previously armed action")
    func rearmingReplacesPreviousAction() {
        let scheduler = ManualEventHubScheduler(startMillis: 0)
        var firstFired = false
        var secondFired = false
        scheduler.arm(atMillis: 1000) { firstFired = true }
        scheduler.arm(atMillis: 2000) { secondFired = true }
        scheduler.advance(by: 1.5)
        #expect(!firstFired)
        #expect(!secondFired)
        scheduler.advance(by: 1)
        #expect(!firstFired)
        #expect(secondFired)
    }

    @Test("arming nil cancels without arming a new action")
    func armingNilCancels() {
        let scheduler = ManualEventHubScheduler(startMillis: 0)
        var fired = false
        scheduler.arm(atMillis: 1000) { fired = true }
        scheduler.arm(atMillis: nil) {}
        scheduler.advance(by: 2)
        #expect(!fired)
    }

    @Test("an action that re-arms another already-due action fires it within the same advance")
    func reentrantRearmFiresWithinSameAdvance() {
        let scheduler = ManualEventHubScheduler(startMillis: 0)
        var secondFired = false
        scheduler.arm(atMillis: 1000) {
            scheduler.arm(atMillis: 1000) { secondFired = true }
        }
        scheduler.advance(by: 1)
        #expect(secondFired)
    }
}

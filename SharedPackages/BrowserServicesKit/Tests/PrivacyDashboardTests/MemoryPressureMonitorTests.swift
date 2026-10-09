//
//  MemoryPressureMonitorTests.swift
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
@testable import PrivacyDashboard
import Testing

struct MemoryPressureMonitorTests {

    @available(iOS 16, macOS 13, *)
    @Test("Disabled monitor returns no level", .timeLimit(.minutes(1)))
    func disabledMonitorReturnsNil() {
        let monitor = MemoryPressureMonitor(isEnabledProvider: { false })
        monitor.handle(.critical)

        #expect(monitor.currentLevel == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Level is unknown until the first event", .timeLimit(.minutes(1)))
    func levelIsUnknownInitially() {
        let monitor = MemoryPressureMonitor(isEnabledProvider: { true })

        #expect(monitor.currentLevel == .unknown)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Level follows each event", .timeLimit(.minutes(1)))
    func levelFollowsEachEvent() {
        let monitor = MemoryPressureMonitor(isEnabledProvider: { true })

        monitor.handle(.warning)
        #expect(monitor.currentLevel == .warning)

        monitor.handle(.critical)
        #expect(monitor.currentLevel == .critical)

        monitor.handle(.normal)
        #expect(monitor.currentLevel == .normal)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Combined events resolve to the most severe level", .timeLimit(.minutes(1)))
    func combinedEventsResolveToMostSevereLevel() {
        let monitor = MemoryPressureMonitor(isEnabledProvider: { true })
        monitor.handle([.normal, .warning, .critical])

        #expect(monitor.currentLevel == .critical)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Level is kept while the flag toggles", .timeLimit(.minutes(1)))
    func levelIsKeptWhileFlagToggles() {
        var isEnabled = false
        let monitor = MemoryPressureMonitor(isEnabledProvider: { isEnabled })
        monitor.handle(.warning)

        #expect(monitor.currentLevel == nil)

        isEnabled = true
        #expect(monitor.currentLevel == .warning)
    }
}

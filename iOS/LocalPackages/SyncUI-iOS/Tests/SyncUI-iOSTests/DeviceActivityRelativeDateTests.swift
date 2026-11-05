//
//  DeviceActivityRelativeDateTests.swift
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
@testable import SyncUI_iOS

@MainActor
struct DeviceActivityRelativeDateTests {

    @available(iOS 16, macOS 13, *)
    @Test("Activity less than a minute old says Just now", .timeLimit(.minutes(1)), arguments: [-60.0, -1.0, 0.0, 1.0, 59.999])
    func recentActivity(seconds: TimeInterval) {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        #expect(DeviceActivityView.relativeDateString(for: now.addingTimeInterval(-seconds), relativeTo: now) == "Just now")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Activity dates use minutes, hours, days, months and years at the agreed boundaries", .timeLimit(.minutes(1)), arguments: [
        (60.0, DateComponents(minute: -1)),
        (3_599.0, DateComponents(minute: -59)),
        (3_600.0, DateComponents(hour: -1)),
        (86_399.0, DateComponents(hour: -23)),
        (86_400.0, DateComponents(day: -1)),
        (1_209_600.0, DateComponents(day: -14)),
        (2_591_999.0, DateComponents(day: -29)),
        (2_592_000.0, DateComponents(month: -1)),
        (31_535_999.0, DateComponents(month: -12)),
        (31_536_000.0, DateComponents(year: -1)),
        (63_072_000.0, DateComponents(year: -2))
    ])
    func relativeActivityDate(seconds: TimeInterval, components: DateComponents) {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let expected = RelativeDateTimeFormatter().localizedString(from: components)
        #expect(DeviceActivityView.relativeDateString(for: now.addingTimeInterval(-seconds), relativeTo: now) == expected)
    }
}

//
//  DeviceActivityViewTests.swift
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

import SnapshotTestingSupport
import SwiftUI
import Testing
@testable import SyncUI_iOS

@MainActor
struct DeviceActivityViewTests {

    @available(iOS 16, macOS 13, *)
    @Test("Activity rows keep actions visible and truncate long device names", .timeLimit(.minutes(1)), arguments: [false, true])
    func activityRowSnapshots(isLargeText: Bool) async {
        let date = Date().addingTimeInterval(-3 * 24 * 60 * 60)
        let entries = [
            DeviceActivityEntry(id: "phone", action: .removed, date: date,
                                deviceName: "A phone with a deliberately long name that must be truncated", deviceType: "phone"),
            DeviceActivityEntry(id: "desktop", action: .synced, date: date.addingTimeInterval(-86_400),
                                deviceName: "A laptop with a deliberately long name that must be truncated", deviceType: "desktop"),
            DeviceActivityEntry(id: "tablet", action: .synced, date: date.addingTimeInterval(-172_800),
                                deviceName: "iPad", deviceType: "tablet")
        ]
        let model = DeviceActivityViewModel(accountIdentifier: { "snapshot-account" }, makePageFetcher: {
            { DeviceActivityPage(entries: entries, hasMore: false) }
        })
        await model.loadIfNeeded()
        assertImageSnapshot(
            matching: NavigationStack {
                DeviceActivityView(model: model)
                    .environment(\.sizeCategory, isLargeText ? .accessibilityExtraExtraExtraLarge : .large)
            },
            size: .screen,
            testName: "activityRowSnapshots\(isLargeText ? "-LargeText" : "")"
        )
    }
}

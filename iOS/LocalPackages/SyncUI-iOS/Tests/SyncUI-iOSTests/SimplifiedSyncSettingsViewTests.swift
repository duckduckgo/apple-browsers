//
//  SimplifiedSyncSettingsViewTests.swift
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
@Suite("Simplified Sync Settings View Tests")
final class SimplifiedSyncSettingsViewTests {

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func testSimplifiedSyncSettingsViewSnapshots() {
        assertImageSnapshots(
            SimplifiedSyncSettingsView_Previews.snapshots,
            size: .screen
        )
    }

    @available(iOS 16, macOS 13, *)
    @Test("Device Activity entry point visibility", .timeLimit(.minutes(1)), arguments: [false, true])
    func testDeviceActivitySettingsSnapshots(isAvailable: Bool) {
        let model = SyncSettingsViewModel.preview(isSyncEnabled: true,
                                                 devices: [.thisDevice, .desktop, .otherMobile],
                                                 autoRestoreProvider: .enabled)
        model.isDeviceActivityAvailable = isAvailable
        let configurations = SnapshotDevice.defaultIOSDevices.flatMap { device in
            SnapshotAppearance.allCases.map { appearance in
                SnapshotImageConfiguration(appearance: appearance,
                                           device: device,
                                           size: CGSize(width: device.size.width, height: 1600))
            }
        }

        // Keep each device's width and traits, with enough height to show the entry point in the real settings view.
        assertImageSnapshot(
            matching: NavigationStack {
                SimplifiedSyncSettingsView(model: model)
                    .navigationTitle(UserText.syncTitle)
                    .navigationBarTitleDisplayMode(.inline)
            },
            strategy: .custom(configurations),
            size: .screen,
            testName: "testDeviceActivitySettingsSnapshots-\(isAvailable ? "Enabled" : "Disabled")"
        )
    }
}

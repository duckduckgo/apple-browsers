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
    @Test("New-device card wraps names and summarizes overflow", .timeLimit(.minutes(1)), arguments: [1, 3, 5, 10])
    func testNewDevicesCardSnapshots(deviceCount: Int) {
        let activityModel = DeviceActivityViewModel(accountIdentifier: { "snapshot-account" }, makePageFetcher: {
            { DeviceActivityPage(entries: [], hasMore: false) }
        })
        let model = SyncSettingsViewModel.preview(isSyncEnabled: true,
                                                 devices: [.thisDevice, .desktop, .otherMobile],
                                                 autoRestoreProvider: .enabled,
                                                 deviceActivityViewModel: activityModel)
        model.isDeviceActivityAvailable = true
        let names = ["Dave’s iPhone", "MacBook Pro", "iPad", "Anya’s MacBook Pro with a deliberately long device name", "Another phone with a long name"] + (6...10).map { "Device \($0)" }
        model.pendingLoginEvents = names.prefix(deviceCount).enumerated().map {
            .init(id: "event-\($0.offset)", deviceName: $0.element)
        }
        assertImageSnapshot(
            matching: NavigationStack {
                SimplifiedSyncSettingsView(model: model)
                    .navigationBarTitleDisplayMode(.inline)
            },
            size: .screen,
            testName: "testNewDevicesCardSnapshots-\(deviceCount)Devices"
        )
    }

    @available(iOS 16, macOS 13, *)
    @Test("Device Activity entry point visibility", .timeLimit(.minutes(1)), arguments: [false, true])
    func testDeviceActivitySettingsSnapshots(isAvailable: Bool) {
        let deviceActivityModel = DeviceActivityViewModel(accountIdentifier: { "snapshot-account" }, makePageFetcher: {
            { DeviceActivityPage(entries: [], hasMore: false) }
        })
        let model = SyncSettingsViewModel.preview(isSyncEnabled: true,
                                                 devices: [.thisDevice, .desktop, .otherMobile],
                                                 autoRestoreProvider: .enabled,
                                                 deviceActivityViewModel: deviceActivityModel)
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
    @available(iOS 16, macOS 13, *)
    @Test("Sync notification permissions", .timeLimit(.minutes(1)), arguments: [false, true], [false, true])
    func testSyncNotificationSettingsSnapshots(isAuthorized: Bool, isLargeText: Bool) async {
        let provider = MockSyncNotificationSettingsProvider(status: isAuthorized ? .authorized : .provisional)
        let notificationModel = SyncNotificationSettingsViewModel(provider: provider)
        await notificationModel.refresh()
        let activityModel = DeviceActivityViewModel(accountIdentifier: { "snapshot-account" }, makePageFetcher: {
            { DeviceActivityPage(entries: [], hasMore: false) }
        })
        let model = SyncSettingsViewModel.preview(isSyncEnabled: true,
                                                 devices: [.thisDevice, .desktop, .otherMobile],
                                                 autoRestoreProvider: .enabled,
                                                 deviceActivityViewModel: activityModel,
                                                 notificationSettingsViewModel: notificationModel)
        model.isDeviceActivityAvailable = true
        model.areSyncNotificationsAvailable = true
        let configurations = SnapshotDevice.defaultIOSDevices.flatMap { device in
            SnapshotAppearance.allCases.map { appearance in
                SnapshotImageConfiguration(appearance: appearance, device: device,
                                           size: CGSize(width: device.size.width, height: isLargeText ? 4000 : 1900))
            }
        }
        assertImageSnapshot(
            matching: NavigationStack {
                SimplifiedSyncSettingsView(model: model)
                    .navigationBarTitleDisplayMode(.inline)
                    .environment(\.sizeCategory, isLargeText ? .accessibilityExtraExtraExtraLarge : .large)
            },
            strategy: .custom(configurations),
            size: .screen,
            testName: "testSyncNotificationSettingsSnapshots-\(isAuthorized ? "Enabled" : "Provisional")\(isLargeText ? "-LargeText" : "")"
        )
    }

}

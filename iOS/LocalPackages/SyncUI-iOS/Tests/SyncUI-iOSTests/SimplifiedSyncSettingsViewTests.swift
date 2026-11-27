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

import Foundation
import TipKit
import UIKit
import SnapshotTestingSupport
import SwiftUI
import Testing
@testable import SyncUI_iOS

@MainActor
@Suite("Simplified Sync Settings View Tests", .serialized)
final class SimplifiedSyncSettingsViewTests {

    private static let configureTips: Void = {
        if #available(iOS 18.0, *) {
            do {
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try Tips.configure([.datastoreLocation(.url(directory)), .displayFrequency(.immediate)])
            } catch {
                Issue.record(error)
            }
        }
    }()

    init() {
        _ = Self.configureTips
    }

    @available(iOS 18.0, macOS 15.0, *)
    @Test("Closing a new-device tip does not suppress a later login", .timeLimit(.minutes(1)))
    func testLaterLoginRemainsEligibleAfterTipDismissal() async {
        let firstID = UUID().uuidString
        let first = SyncSettingsTip(kind: .newDevices([firstID]), titleText: "New device",
                                    messageText: "A device joined.", actionText: "Review Activity")
        first.invalidate(reason: .tipClosed)
        for await status in first.statusUpdates {
            if case .invalidated(.tipClosed) = status { break }
        }
        let later = SyncSettingsTip(kind: .newDevices([UUID().uuidString]), titleText: "New device",
                                    messageText: "Another device joined.", actionText: "Review Activity")
        for await shouldDisplay in later.shouldDisplayUpdates where shouldDisplay {
            break
        }
        #expect(later.shouldDisplay)
        #expect(first.id != later.id)
    }

    @available(iOS 18.0, macOS 15.0, *)
    @Test("Tip identity is stable for the same pending events", .timeLimit(.minutes(1)))
    func testTipIdentityIsStableForPendingEvents() {
        let first = SyncSettingsTip(kind: .newDevices(["a", "b"]), titleText: "", messageText: "", actionText: "")
        let reordered = SyncSettingsTip(kind: .newDevices(["b", "a"]), titleText: "", messageText: "", actionText: "")
        #expect(first.id == reordered.id)
    }

    @available(iOS 18.0, macOS 15.0, *)
    @Test("Native tip dismissal reaches the existing Sync callback", .timeLimit(.minutes(1)))
    func testNativeTipDismissalCallsSyncHandler() async throws {
        let tip = SyncSettingsTip(kind: .newDevices([UUID().uuidString]), titleText: "New device",
                                  messageText: "A device joined.", actionText: "Review Activity")
        var dismissCount = 0
        let controller = UIHostingController(rootView: SyncSettingsTipView(tip: tip, action: {}, dismiss: { dismissCount += 1 }))
        let window = UIWindow(frame: CGRect(origin: .zero, size: SnapshotDevice.iPhoneDefault.size))
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        controller.view.layoutIfNeeded()
        tip.invalidate(reason: .tipClosed)
        for _ in 0..<100 {
            if dismissCount > 0 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(dismissCount == 1)
    }

    @available(iOS 16, *)
    private func assertTipSnapshot<Content: View>(matching view: Content,
                                                  strategy: SnapshotImageStrategy = .allAppearances,
                                                  size: SnapshotImageSize,
                                                  record: Bool = false,
                                                  testName: String) async throws {
        for configuration in strategy.configurations(for: .iOS, size: size) {
            let snapshotSize = configuration.size ?? configuration.device?.size ?? SnapshotDevice.iPhoneDefault.size
            let controller = UIHostingController(rootView: view.environment(\.colorScheme, configuration.appearance == .dark ? .dark : .light))
            let window = UIWindow(frame: CGRect(origin: .zero, size: snapshotSize))
            window.rootViewController = controller
            window.isHidden = false
            defer { window.isHidden = true }
            controller.view.layoutIfNeeded()
            // Native TipView resolves eligibility after mounting its view.
            try await Task.sleep(for: .milliseconds(600))
            assertImageSnapshot(matching: controller, strategy: .custom([configuration]),
                                size: .fixed(snapshotSize), record: record, testName: testName)
        }
    }

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
    func testNewDevicesCardSnapshots(deviceCount: Int) async throws {
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
        try await assertTipSnapshot(
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
    func testSyncNotificationSettingsSnapshots(isAuthorized: Bool, isLargeText: Bool) async throws {
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
        try await assertTipSnapshot(
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

    @available(iOS 16, macOS 13, *)
    @Test("New-device activity appears above notification permissions", .timeLimit(.minutes(1)))
    func testNewDeviceAndPermissionCardsSnapshot() async throws {
        let provider = MockSyncNotificationSettingsProvider(status: .provisional)
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
        model.pendingLoginEvents = [.init(id: "new-device", deviceName: "Dave’s iPhone")]
        let configurations = SnapshotDevice.defaultIOSDevices.flatMap { device in
            SnapshotAppearance.allCases.map { appearance in
                SnapshotImageConfiguration(appearance: appearance, device: device,
                                           size: CGSize(width: device.size.width, height: 1800))
            }
        }
        try await assertTipSnapshot(
            matching: NavigationStack {
                SimplifiedSyncSettingsView(model: model)
                    .navigationBarTitleDisplayMode(.inline)
            },
            strategy: .custom(configurations),
            size: .screen,
            testName: "testNewDeviceAndPermissionCardsSnapshot"
        )
    }

}

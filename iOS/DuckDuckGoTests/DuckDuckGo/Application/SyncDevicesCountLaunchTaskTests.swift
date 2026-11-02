//
//  SyncDevicesCountLaunchTaskTests.swift
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

import XCTest
import FeatureFlags_iOS
@_spi(Testing) import Persistence
@testable import Core
@testable import DDGSync
@testable import DuckDuckGo

final class SyncDevicesCountLaunchTaskTests: XCTestCase {

    private let testGroupName = "SyncDevicesCountLaunchTaskTests"
    private var customSuite: UserDefaults!
    private var syncService: MockDDGSyncing!
    private var storage: (any KeyedStoring<SyncPromoStorageKeys>)!

    private struct FetchError: Error {}

    override func setUpWithError() throws {
        try super.setUpWithError()
        customSuite = UserDefaults(suiteName: testGroupName)
        customSuite.removePersistentDomain(forName: testGroupName)
        UserDefaults.app = customSuite
        syncService = MockDDGSyncing(authState: .active, isSyncInProgress: false)
        syncService.registeredDevices = [RegisteredDevice(id: "1", name: "iPhone", type: "phone")]
        storage = MockKeyValueStore().keyedStoring()
    }

    override func tearDownWithError() throws {
        UserDefaults.app = .standard
        customSuite = nil
        syncService = nil
        storage = nil
        try super.tearDownWithError()
    }

    func testWhenEligibleThenFetchesDevicesAndStoresCount() async {
        syncService.registeredDevices = [
            RegisteredDevice(id: "1", name: "iPhone", type: "phone"),
            RegisteredDevice(id: "2", name: "Mac", type: "desktop")
        ]

        let finishCount = await run(makeTask())

        XCTAssertEqual(syncService.fetchDevicesCallCount, 1)
        XCTAssertEqual(storage.syncedDevicesCount, 2)
        XCTAssertEqual(finishCount, 1)
    }

    func testWhenAnotherDeviceFlagOffThenDoesNotFetchDevices() async {
        storage.syncedDevicesCount = 1

        let finishCount = await run(makeTask(featureFlags: [.sync]))

        XCTAssertEqual(syncService.fetchDevicesCallCount, 0)
        XCTAssertEqual(storage.syncedDevicesCount, 1)
        XCTAssertEqual(finishCount, 1)
    }

    func testWhenSyncInactiveThenDoesNotFetchDevices() async {
        syncService.authState = .inactive

        let finishCount = await run(makeTask())

        XCTAssertEqual(syncService.fetchDevicesCallCount, 0)
        XCTAssertNil(storage.syncedDevicesCount)
        XCTAssertEqual(finishCount, 1)
    }

    func testWhenPromoDismissedThenDoesNotFetchDevices() async {
        let task = makeTask()
        task.syncPromoManager.dismissPromoFor(.bookmarksAnotherDevice, reason: .userTapped)

        let finishCount = await run(task)

        XCTAssertEqual(syncService.fetchDevicesCallCount, 0)
        XCTAssertNil(storage.syncedDevicesCount)
        XCTAssertEqual(finishCount, 1)
    }

    func testWhenFetchFailsThenKeepsPreviousCount() async {
        storage.syncedDevicesCount = 1
        syncService.fetchDevicesError = FetchError()

        let finishCount = await run(makeTask())

        XCTAssertEqual(syncService.fetchDevicesCallCount, 1)
        XCTAssertEqual(storage.syncedDevicesCount, 1)
        XCTAssertEqual(finishCount, 1)
    }

    private func makeTask(featureFlags: [FeatureFlag] = [.syncPromotionSyncAnotherDevice, .sync]) -> SyncDevicesCountLaunchTask {
        let manager = SyncPromoManager(syncService: syncService,
                                       featureFlagger: MockFeatureFlagger(enabledFeatureFlags: featureFlags),
                                       storage: storage,
                                       pixelFiring: nil)
        return SyncDevicesCountLaunchTask(syncPromoManager: manager)
    }

    private func run(_ task: SyncDevicesCountLaunchTask) async -> Int {
        var finishCount = 0
        await withCheckedContinuation { continuation in
            task.run(context: LaunchTaskContext(isCancelled: { false }, finish: {
                finishCount += 1
                continuation.resume()
            }))
        }
        return finishCount
    }
}

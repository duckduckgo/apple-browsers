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
@testable import DDGSync
@testable import DuckDuckGo

final class SyncDevicesCountLaunchTaskTests: XCTestCase {

    private var syncService: MockDDGSyncing!
    private var storage: (any KeyedStoring<SyncPromoStorageKeys>)!

    override func setUpWithError() throws {
        try super.setUpWithError()
        syncService = MockDDGSyncing(authState: .active, isSyncInProgress: false)
        storage = MockKeyValueStore().keyedStoring()
    }

    override func tearDownWithError() throws {
        syncService = nil
        storage = nil
        try super.tearDownWithError()
    }

    func testWhenRunThenRefreshesSyncedDevicesCountAndFinishesOnce() async {
        syncService.registeredDevices = [
            RegisteredDevice(id: "1", name: "iPhone", type: "phone"),
            RegisteredDevice(id: "2", name: "Mac", type: "desktop")
        ]

        let finishCount = await run(makeTask())

        XCTAssertEqual(storage.syncedDevicesCount, 2)
        XCTAssertEqual(finishCount, 1)
    }

    private func makeTask() -> SyncDevicesCountLaunchTask {
        let manager = SyncPromoManager(syncService: syncService,
                                       featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.syncPromotionSyncAnotherDevice, .sync]),
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

//
//  SyncServiceTests.swift
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

@Suite("SyncService background launch")
struct SyncServiceTests {

    @available(iOS 16, macOS 13, *)
    @Test("Background launch suspends the sync queue", .timeLimit(.minutes(1)))
    func backgroundLaunchSuspendsSyncQueue() {
        let scheduler = CapturingScheduler()

        SyncService.suspendSyncIfLaunchedInBackground(true, scheduler: scheduler)

        #expect(scheduler.cancelSyncAndSuspendSyncQueueCallCount == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Foreground launch leaves the sync queue running", .timeLimit(.minutes(1)))
    func foregroundLaunchLeavesSyncQueueRunning() {
        let scheduler = CapturingScheduler()

        SyncService.suspendSyncIfLaunchedInBackground(false, scheduler: scheduler)

        #expect(scheduler.cancelSyncAndSuspendSyncQueueCallCount == 0)
    }
}

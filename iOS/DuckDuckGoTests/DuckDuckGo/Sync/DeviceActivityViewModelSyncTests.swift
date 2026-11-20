//
//  DeviceActivityViewModelSyncTests.swift
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
import XCTest
@testable import DDGSync
import SyncUI_iOS
@testable import DuckDuckGo

final class DeviceActivityViewModelSyncTests: XCTestCase {
    @MainActor
    func testFactoryMapsEventsAndCreatesOneReaderPerVisit() async throws {
        let account = makeAccount("account-a")
        let sync = MockDDGSyncing(authState: .active, account: account, isSyncInProgress: false)
        let newestDate = Date(timeIntervalSince1970: 20)
        let olderDate = Date(timeIntervalSince1970: 10)
        sync.auditLogPageStub = SyncAuditLogPage(events: [
            SyncAuditLogEvent(id: "login", kind: .synced, occurredAt: newestDate,
                             device: RegisteredDevice(id: "joining-device", name: "Browser", type: "desktop", credentialId: "3party")),
            SyncAuditLogEvent(id: "logout", kind: .removed, occurredAt: olderDate,
                             device: RegisteredDevice(id: "removed-device", name: "iPhone", type: "phone"))
        ], hasMore: true)
        let model = DeviceActivityViewModel.make(syncService: sync)

        await model.loadIfNeeded()

        XCTAssertEqual(model.entries, [
            DeviceActivityEntry(id: "login", action: .synced, date: newestDate,
                                deviceName: "Browser", deviceType: "desktop", credentialId: "3party"),
            DeviceActivityEntry(id: "logout", action: .removed, date: olderDate,
                                deviceName: "iPhone", deviceType: "phone")
        ])
        XCTAssertEqual(sync.auditLogReaderAccounts, [account.userId])
        XCTAssertEqual(sync.auditLogPageReadCount, 1)
        XCTAssertEqual(try sync.auditLogReviewState(for: account.userId),
                       SyncAuditLogReviewState(reviewedThrough: newestDate, isInitialized: true))

        sync.auditLogPageStub = SyncAuditLogPage(events: [], hasMore: false)
        await model.loadOlderIfNeeded(after: "logout")
        XCTAssertEqual(sync.auditLogReaderAccounts, [account.userId])
        XCTAssertEqual(sync.auditLogPageReadCount, 2)

        model.cancelAndClear()
        await model.loadIfNeeded()
        XCTAssertEqual(sync.auditLogReaderAccounts, [account.userId, account.userId])
        XCTAssertEqual(sync.auditLogPageReadCount, 3)
    }

    @MainActor
    func testFactoryLoadsReviewStateForTheCurrentAccount() async throws {
        let sync = MockDDGSyncing(authState: .active, account: makeAccount("account-a"), isSyncInProgress: false)
        let firstReviewDate = Date(timeIntervalSince1970: 100)
        let secondReviewDate = Date(timeIntervalSince1970: 200)
        try sync.setAuditLogReviewState(SyncAuditLogReviewState(reviewedThrough: firstReviewDate, isInitialized: true), for: "account-a")
        try sync.setAuditLogReviewState(SyncAuditLogReviewState(reviewedThrough: secondReviewDate, isInitialized: true), for: "account-b")
        sync.auditLogPageStub = SyncAuditLogPage(events: [
            SyncAuditLogEvent(id: "login", kind: .synced, occurredAt: Date(timeIntervalSince1970: 150),
                             device: RegisteredDevice(id: "device", name: "iPhone", type: "phone"))
        ], hasMore: false)
        let model = DeviceActivityViewModel.make(syncService: sync)

        await model.loadIfNeeded()
        let firstEntry = try XCTUnwrap(model.entries.first)
        XCTAssertFalse(model.isSeen(firstEntry))
        XCTAssertEqual(model.reviewState.reviewedThrough, firstReviewDate)

        sync.account = makeAccount("account-b")
        await model.loadIfNeeded()
        let secondEntry = try XCTUnwrap(model.entries.first)
        XCTAssertTrue(model.isSeen(secondEntry))
        XCTAssertEqual(model.reviewState.reviewedThrough, secondReviewDate)
        XCTAssertEqual(sync.auditLogReaderAccounts, ["account-a", "account-b"])
        XCTAssertEqual(sync.auditLogPageReadCount, 2)
    }

    private func makeAccount(_ userID: String) -> SyncAccount {
        SyncAccount(deviceId: "this-device", deviceName: "iPhone", deviceType: "phone", userId: userID,
                    primaryKey: Data(repeating: 1, count: 32), secretKey: Data(repeating: 2, count: 32), token: "token", state: .active)
    }
}

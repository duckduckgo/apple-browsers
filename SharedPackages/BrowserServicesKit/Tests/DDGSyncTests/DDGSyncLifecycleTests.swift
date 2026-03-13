//
//  DDGSyncLifecycleTests.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

import Combine
import Common
import XCTest
import PersistenceTestingUtils
@testable import DDGSync

final class DDGSyncLifecycleTests: XCTestCase {

    enum MockError: Error {
        case error
    }

    var dataProvidersSource: MockDataProvidersSource!
    var dependencies: MockSyncDependencies!

    var secureStorageStub: SecureStorageStub {
        dependencies.secureStore as! SecureStorageStub
    }

    var kvfStoreStub: MockKeyValueFileStore {
        dependencies.keyValueStore as! MockKeyValueFileStore
    }

    var mockErrorHandler: MockErrorHandler {
        dependencies.errorEvents as! MockErrorHandler
    }

    override func setUp() {
        super.setUp()

        dataProvidersSource = MockDataProvidersSource()
        dependencies = MockSyncDependencies()
    }

    func testWhenInitializingAndOffThenStateIsInactive() throws {
        secureStorageStub.theAccount = nil
        try dependencies.keyValueStore.set(false, forKey: DDGSync.Constants.syncEnabledKey)

        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        XCTAssertEqual(syncService.authState, .initializing)
        syncService.initializeIfNeeded()
        XCTAssertEqual(syncService.authState, .inactive)
        XCTAssertEqual(mockErrorHandler.handledErrors, [.accountRemoved(.notFoundInSecureStorage)])
    }

    func testWhenInitializingAndOnThenStateIsActive() throws {
        secureStorageStub.theAccount = .mock
        try dependencies.keyValueStore.set(true, forKey: DDGSync.Constants.syncEnabledKey)

        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        XCTAssertEqual(syncService.authState, .initializing)
        syncService.initializeIfNeeded()
        XCTAssertEqual(syncService.authState, .active)
        XCTAssertEqual(mockErrorHandler.handledErrors, [])
    }

    func testWhenInitializingAndAfterReinstallThenStateIsInactive() {
        secureStorageStub.theAccount = .mock

        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        XCTAssertEqual(syncService.authState, .initializing)
        syncService.initializeIfNeeded()
        XCTAssertEqual(syncService.authState, .inactive)
        XCTAssertNil(secureStorageStub.theAccount)
        XCTAssertEqual(mockErrorHandler.handledErrors, [.accountRemoved(.syncEnabledNotSetOnKeyValueStore)])
    }

    func testWhenInitializingAndKeysBeenRemovedThenStateIsInactive() throws {
        secureStorageStub.theAccount = nil
        try dependencies.keyValueStore.set(true, forKey: DDGSync.Constants.syncEnabledKey)

        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        XCTAssertEqual(syncService.authState, .initializing)
        syncService.initializeIfNeeded()
        XCTAssertEqual(syncService.authState, .inactive)

        // Shall we be removing the account? Keeping it tho, allows us to recover sync In case we somehow get back access to the keychain entry.
        // XCTAssertNil(mockKeyValueStore.isSyncEnabled)

        XCTAssertNil(secureStorageStub.theAccount)
        XCTAssertEqual(mockErrorHandler.handledErrors, [.accountRemoved(.notFoundInSecureStorage)])
    }

    func testWhenInitializingAndCannotReadAccountThenErrorIsReportedAndInitializationIsPostponed() throws {
        let expectedError = SyncError.failedToReadSecureStore(status: 0)
        secureStorageStub.theAccount = .mock
        secureStorageStub.mockReadError = expectedError

        try dependencies.keyValueStore.set(true, forKey: DDGSync.Constants.syncEnabledKey)

        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        XCTAssertEqual(syncService.authState, .initializing)
        syncService.initializeIfNeeded()
        XCTAssertEqual(syncService.authState, .initializing)
        XCTAssertEqual(mockErrorHandler.handledErrors, [.failedToLoadAccount])
    }

    func testWhenInitializingAndCannotSaveAccountThenErrorIsReported() throws {
        let expectedError = SyncError.failedToWriteSecureStore(status: 0)
        secureStorageStub.theAccount = .mock
        secureStorageStub.mockWriteError = expectedError

        try dependencies.keyValueStore.set(true, forKey: DDGSync.Constants.syncEnabledKey)

        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        XCTAssertEqual(syncService.authState, .initializing)
        syncService.initializeIfNeeded()
        // Account has been read, so it is active
        XCTAssertEqual(syncService.authState, .active)
        XCTAssertEqual(mockErrorHandler.handledErrors, [.failedToSetupEngine])
    }

    func testWhenMigratingAndDisabledThenStateIsInactive() throws {
        dependencies.legacyKeyValueStore.removeObject(forKey: DDGSync.Constants.syncEnabledKey)

        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        XCTAssertEqual(syncService.authState, .initializing)
        syncService.initializeIfNeeded()

        XCTAssertEqual(syncService.authState, .inactive)
        XCTAssertEqual(mockErrorHandler.handledErrors, [])
    }

    func testWhenMigratingAndEnabledThenStateIsActive() throws {
        dependencies.legacyKeyValueStore.set(true, forKey: DDGSync.Constants.syncEnabledKey)
        secureStorageStub.theAccount = .mock

        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        XCTAssertEqual(syncService.authState, .initializing)
        syncService.initializeIfNeeded()

        XCTAssertEqual(syncService.authState, .active)
        XCTAssertEqual(mockErrorHandler.handledErrors, [.migratedToFileStore])
    }

    func testWhenMigratingAndErrorReadingThenErrorIsReportedAndInitializationIsPostponed() throws {
        dependencies.legacyKeyValueStore.set(true, forKey: DDGSync.Constants.syncEnabledKey)
        kvfStoreStub.throwOnRead = MockError.error

        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        XCTAssertEqual(syncService.authState, .initializing)
        syncService.initializeIfNeeded()

        XCTAssertEqual(syncService.authState, .initializing)
        XCTAssertEqual(mockErrorHandler.handledErrors, [.failedToInitFileStore])
    }

    func testWhenMigratingAndErrorSavingThenErrorIsReportedAndInitializationIsPostponed() throws {
        dependencies.legacyKeyValueStore.set(true, forKey: DDGSync.Constants.syncEnabledKey)
        kvfStoreStub.throwOnSet = MockError.error

        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        XCTAssertEqual(syncService.authState, .initializing)
        syncService.initializeIfNeeded()

        XCTAssertEqual(syncService.authState, .initializing)
        XCTAssertEqual(mockErrorHandler.handledErrors, [.failedToMigrateToFileStore])
    }

    func testWhenMainTokenRescopeReturns401ThenSyncLogsOut() async throws {
        secureStorageStub.theAccount = .mock
        try dependencies.keyValueStore.set(true, forKey: DDGSync.Constants.syncEnabledKey)

        let tokenRescope = MockTokenRescoping()
        tokenRescope.rescopeError = SyncError.unexpectedStatusCode(401)
        dependencies.createTokenRescopeStub = tokenRescope

        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        syncService.initializeIfNeeded()
        XCTAssertEqual(syncService.authState, .active)

        do {
            _ = try await syncService.mainTokenRescope(to: "ai_chats")
            XCTFail("Expected mainTokenRescope(to:) to throw")
        } catch let error as SyncError {
            XCTAssertEqual(error, .unauthenticatedWhileLoggedIn)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(syncService.authState, .inactive)
        XCTAssertNil(secureStorageStub.theAccount)
        XCTAssertEqual(mockErrorHandler.handledErrors, [.accountRemoved(.unauthenticatedRequest)])
    }

    func testWhenMainTokenRescopeReturnsNon401ThenSyncRemainsActive() async throws {
        secureStorageStub.theAccount = .mock
        try dependencies.keyValueStore.set(true, forKey: DDGSync.Constants.syncEnabledKey)

        let tokenRescope = MockTokenRescoping()
        tokenRescope.rescopeError = SyncError.unexpectedStatusCode(400)
        dependencies.createTokenRescopeStub = tokenRescope

        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        syncService.initializeIfNeeded()
        XCTAssertEqual(syncService.authState, .active)

        do {
            _ = try await syncService.mainTokenRescope(to: "ai_chats")
            XCTFail("Expected mainTokenRescope(to:) to throw")
        } catch let error as SyncError {
            XCTAssertEqual(error, .unexpectedStatusCode(400))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(syncService.authState, .active)
        XCTAssertNotNil(secureStorageStub.theAccount)
        XCTAssertEqual(mockErrorHandler.handledErrors, [])
    }

    func testWhenInitializingAndSyncDisabledAndPreserveClosureTrueThenAccountIsNotRemoved() {
        secureStorageStub.theAccount = .mock
        dependencies.shouldPreserveAccountWhenSyncDisabled = { true }

        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        XCTAssertEqual(syncService.authState, .initializing)
        syncService.initializeIfNeeded()

        XCTAssertEqual(syncService.authState, .inactive)
        XCTAssertNotNil(secureStorageStub.theAccount)
        XCTAssertEqual(mockErrorHandler.handledErrors, [])
    }

    func testWhenInitializingAndSyncDisabledAndPreserveClosureTrueAndCannotReadAccountThenAccountIsNotRemoved() {
        let expectedError = SyncError.failedToReadSecureStore(status: 0)
        secureStorageStub.theAccount = .mock
        secureStorageStub.mockReadError = expectedError
        dependencies.shouldPreserveAccountWhenSyncDisabled = { true }

        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        XCTAssertEqual(syncService.authState, .initializing)
        syncService.initializeIfNeeded()

        XCTAssertEqual(syncService.authState, .inactive)
        XCTAssertNotNil(secureStorageStub.theAccount)
        XCTAssertEqual(mockErrorHandler.handledErrors, [.failedToLoadAccount])
    }

    func testWhenInitializingAndSyncDisabledAndPreserveClosureFalseThenAccountIsRemoved() {
        secureStorageStub.theAccount = .mock
        dependencies.shouldPreserveAccountWhenSyncDisabled = { false }

        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        XCTAssertEqual(syncService.authState, .initializing)
        syncService.initializeIfNeeded()

        XCTAssertEqual(syncService.authState, .inactive)
        XCTAssertNil(secureStorageStub.theAccount)
        XCTAssertEqual(mockErrorHandler.handledErrors, [.accountRemoved(.syncEnabledNotSetOnKeyValueStore)])
    }

    func testWhenEnableSyncFromPreservedAccountThenSyncIsReEnabled() async throws {
        secureStorageStub.theAccount = .mock
        dependencies.shouldPreserveAccountWhenSyncDisabled = { true }

        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        syncService.initializeIfNeeded()

        XCTAssertEqual(syncService.authState, .inactive)
        XCTAssertNotNil(secureStorageStub.theAccount)

        try await syncService.enableSyncFromPreservedAccount()

        XCTAssertEqual(syncService.authState, .active)
        XCTAssertNotNil(try dependencies.keyValueStore.object(forKey: DDGSync.Constants.syncEnabledKey))
    }

    func testWhenEnableSyncFromPreservedAccountAndEngineSetupFailsThenErrorIsThrownAndStateReturnsToInactive() async {
        secureStorageStub.theAccount = .mock
        dependencies.shouldPreserveAccountWhenSyncDisabled = { true }

        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        syncService.initializeIfNeeded()
        XCTAssertEqual(syncService.authState, .inactive)

        secureStorageStub.mockWriteError = .failedToWriteSecureStore(status: 0)

        await assertThrowsError(SyncError.failedToSetupEngine) {
            try await syncService.enableSyncFromPreservedAccount()
        }

        XCTAssertEqual(syncService.authState, .inactive)
        XCTAssertNil(try? dependencies.keyValueStore.object(forKey: DDGSync.Constants.syncEnabledKey))
        XCTAssertFalse((dependencies.scheduler as! SchedulerMock).isEnabled)
        XCTAssertEqual(mockErrorHandler.handledErrors, [.failedToSetupEngine])
    }

    func testWhenEnableSyncFromPreservedAccountAndEngineSetupFailsAndRemoveFailsThenFallbackClearsSyncEnabledKey() async {
        secureStorageStub.theAccount = .mock
        dependencies.shouldPreserveAccountWhenSyncDisabled = { true }

        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        syncService.initializeIfNeeded()
        XCTAssertEqual(syncService.authState, .inactive)

        secureStorageStub.mockWriteError = .failedToWriteSecureStore(status: 0)
        kvfStoreStub.throwOnRemove = MockError.error

        await assertThrowsError(SyncError.failedToSetupEngine) {
            try await syncService.enableSyncFromPreservedAccount()
        }

        XCTAssertEqual(syncService.authState, .inactive)
        XCTAssertNil(try? dependencies.keyValueStore.object(forKey: DDGSync.Constants.syncEnabledKey))
        XCTAssertFalse((dependencies.scheduler as! SchedulerMock).isEnabled)
        XCTAssertEqual(mockErrorHandler.handledErrors, [.failedToSetupEngine])
    }

    func testWhenEnableSyncFromPreservedAccountAndAlreadyActiveThenMethodReturnsWithoutWriting() async throws {
        secureStorageStub.theAccount = .mock
        try dependencies.keyValueStore.set(true, forKey: DDGSync.Constants.syncEnabledKey)

        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        syncService.initializeIfNeeded()
        XCTAssertEqual(syncService.authState, .active)

        kvfStoreStub.throwOnSet = MockError.error

        try await syncService.enableSyncFromPreservedAccount()

        XCTAssertEqual(syncService.authState, .active)
    }

    func testWhenEnableSyncFromPreservedAccountAndCannotWriteSyncEnabledThenErrorIsThrown() async {
        secureStorageStub.theAccount = .mock
        dependencies.shouldPreserveAccountWhenSyncDisabled = { true }

        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        syncService.initializeIfNeeded()
        XCTAssertEqual(syncService.authState, .inactive)

        kvfStoreStub.throwOnSet = MockError.error

        await assertThrowsAnyError {
            try await syncService.enableSyncFromPreservedAccount()
        }

        XCTAssertEqual(syncService.authState, .inactive)
        XCTAssertNil(try? dependencies.keyValueStore.object(forKey: DDGSync.Constants.syncEnabledKey))
    }

    func testWhenRemovePreservedSyncAccountAndPreservedAccountExistsThenAccountIsRemoved() throws {
        secureStorageStub.theAccount = .mock
        dependencies.shouldPreserveAccountWhenSyncDisabled = { true }
        let dataProvider = DataProvidingMock(feature: .init(name: "bookmarks"))
        try dataProvider.registerFeature(withState: .readyToSync)
        dataProvidersSource.dataProviders = [dataProvider]

        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        syncService.initializeIfNeeded()
        XCTAssertEqual(syncService.authState, .inactive)
        XCTAssertNotNil(secureStorageStub.theAccount)
        XCTAssertTrue(dataProvider.isFeatureRegistered)

        try syncService.removePreservedSyncAccount()

        XCTAssertEqual(syncService.authState, .inactive)
        XCTAssertNil(secureStorageStub.theAccount)
        XCTAssertFalse(dataProvider.isFeatureRegistered)
        XCTAssertEqual(mockErrorHandler.handledErrors, [.accountRemoved(.userStartedFreshSetup)])
    }

}

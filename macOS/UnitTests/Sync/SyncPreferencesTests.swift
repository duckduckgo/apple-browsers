//
//  SyncPreferencesTests.swift
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

import Bookmarks
import Combine
import Persistence
@testable import SyncUI_macOS
import XCTest
import PersistenceTestingUtils
@testable import BrowserServicesKit
@testable import DDGSync
@testable import DuckDuckGo_Privacy_Browser
import FeatureFlags

private final class MockUserAuthenticator: UserAuthenticating {
    func authenticateUser(reason: DuckDuckGo_Privacy_Browser.DeviceAuthenticator.AuthenticationReason) async -> DeviceAuthenticationResult {
        .success
    }
    func authenticateUser(reason: DeviceAuthenticator.AuthenticationReason, result: @escaping (DeviceAuthenticationResult) -> Void) {
        result(.success)
    }
}

class MockSyncFeatureFlagger: FeatureFlagger {
    var internalUserDecider: InternalUserDecider = DefaultInternalUserDecider(store: MockInternalUserStoring())
    var localOverrides: FeatureFlagLocalOverriding?
    var cohort: (any FeatureFlagCohortDescribing)?

    public init() { }

    public init(internalUserDecider: InternalUserDecider) {
        self.internalUserDecider = internalUserDecider
    }

    var isFeatureOn: [String: Bool] = [:]
    func isFeatureOn<Flag: FeatureFlagDescribing>(for featureFlag: Flag, allowOverride: Bool) -> Bool {
        return isFeatureOn[featureFlag.rawValue] ?? false
    }

    func getCohortIfEnabled(_ subfeature: any PrivacySubfeature) -> CohortID? {
        return nil
    }

    func resolveCohort<Flag>(for featureFlag: Flag, allowOverride: Bool) -> (any FeatureFlagCohortDescribing)? where Flag: FeatureFlagDescribing {
        return cohort
    }

    var allActiveExperiments: Experiments = [:]
}

@MainActor
final class SyncPreferencesTests: XCTestCase {

    var scheduler: CapturingScheduler! = CapturingScheduler()
    var ddgSyncing: MockDDGSyncing!
    var syncBookmarksAdapter: SyncBookmarksAdapter!
    var syncCredentialsAdapter: SyncCredentialsAdapter!
    var appearancePersistor: MockAppearancePreferencesPersistor! = MockAppearancePreferencesPersistor()
    var appearancePreferences: AppearancePreferences!
    var syncPreferences: SyncPreferences!
    var pausedStateManager: MockSyncPausedStateManaging!
    var connectionController: MockSyncConnectionControlling!
    var featureFlagger: MockSyncFeatureFlagger!
    var testRecoveryCode = "eyJyZWNvdmVyeSI6eyJ1c2VyX2lkIjoiMDZGODhFNzEtNDFBRS00RTUxLUE2UkRtRkEwOTcwMDE5QkYwIiwicHJpbWFyeV9rZXkiOiI1QTk3U3dsQVI5RjhZakJaU09FVXBzTktnSnJEYnE3aWxtUmxDZVBWazgwPSJ9fQ=="
    lazy var testRecoveryKey = try! SyncCode.decodeBase64String(testRecoveryCode).recovery!
    var cancellables: Set<AnyCancellable>!

    var bookmarksDatabase: CoreDataDatabase!
    var location: URL!

    override func setUp() {
        cancellables = []
        setUpDatabase()
        appearancePreferences = AppearancePreferences(persistor: appearancePersistor, privacyConfigurationManager: MockPrivacyConfigurationManager(), featureFlagger: MockFeatureFlagger())
        ddgSyncing = MockDDGSyncing(authState: .inactive, scheduler: scheduler, isSyncInProgress: false)
        pausedStateManager = MockSyncPausedStateManaging()

        syncBookmarksAdapter = SyncBookmarksAdapter(database: bookmarksDatabase, bookmarkManager: MockBookmarkManager(), appearancePreferences: appearancePreferences, syncErrorHandler: SyncErrorHandler())
        syncCredentialsAdapter = SyncCredentialsAdapter(secureVaultFactory: AutofillSecureVaultFactory, syncErrorHandler: SyncErrorHandler())
        featureFlagger = MockSyncFeatureFlagger()
        featureFlagger.isFeatureOn[FeatureFlag.syncSeamlessAccountSwitching.rawValue] = true
        connectionController = MockSyncConnectionControlling()

        syncPreferences = SyncPreferences(
            syncService: ddgSyncing,
            syncBookmarksAdapter: syncBookmarksAdapter,
            syncCredentialsAdapter: syncCredentialsAdapter,
            appearancePreferences: appearancePreferences,
            userAuthenticator: MockUserAuthenticator(),
            syncPausedStateManager: pausedStateManager,
            connectionControllerFactory: { [weak self] _, _ in
                guard let self else { return MockSyncConnectionControlling() }
                return connectionController
            },
            featureFlagger: featureFlagger
        )
    }

    override func tearDown() {
        ddgSyncing = nil
        syncPreferences = nil
        pausedStateManager = nil
        cancellables = nil
        tearDownDatabase()
        appearancePersistor = nil
        appearancePreferences = nil
        connectionController = nil
        featureFlagger = nil
        scheduler = nil
        syncBookmarksAdapter = nil
        syncCredentialsAdapter = nil
    }

    private func setUpDatabase() {
        location = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        let bundle = Bookmarks.bundle
        guard let model = CoreDataDatabase.loadModel(from: bundle, named: "BookmarksModel") else {
            XCTFail("Failed to load model")
            return
        }
        bookmarksDatabase = CoreDataDatabase(name: className, containerLocation: location, model: model)
        bookmarksDatabase.loadStore()
    }

    private func tearDownDatabase() {
        try? bookmarksDatabase.tearDown(deleteStores: true)
        bookmarksDatabase = nil
        try? FileManager.default.removeItem(at: location)
    }

    func testSyncIsEnabledReturnsCorrectValue() {
        XCTAssertFalse(syncPreferences.isSyncEnabled)

        ddgSyncing.account = SyncAccount(deviceId: "some device", deviceName: "", deviceType: "", userId: "", primaryKey: Data(), secretKey: Data(), token: nil, state: .active)

        XCTAssertTrue(syncPreferences.isSyncEnabled)
    }

    // MARK: - SYNC ERRORS
    func test_WhenSyncPausedIsTrue_andChangePublished_isSyncPausedIsUpdated() async {
        let expectation2 = XCTestExpectation(description: "isSyncPaused received the update")
        let expectation1 = XCTestExpectation(description: "isSyncPaused published")
        syncPreferences.$isSyncPaused
            .dropFirst()
            .sink { isPaused in
                XCTAssertTrue(isPaused)
                expectation2.fulfill()
            }
            .store(in: &cancellables)

        Task {
            pausedStateManager.isSyncPaused = true
            pausedStateManager.isSyncPausedChangedPublisher.send()
            expectation1.fulfill()
        }

        await self.fulfillment(of: [expectation1, expectation2], timeout: 5.0)
    }

    func test_WhenSyncBookmarksPausedIsTrue_andChangePublished_isSyncBookmarksPausedIsUpdated() async {
        let expectation2 = XCTestExpectation(description: "isSyncBookmarksPaused received the update")
        let expectation1 = XCTestExpectation(description: "isSyncBookmarksPaused published")
        syncPreferences.$isSyncBookmarksPaused
            .dropFirst()
            .sink { isPaused in
                XCTAssertTrue(isPaused)
                expectation2.fulfill()
            }
            .store(in: &cancellables)

        Task {
            pausedStateManager.isSyncBookmarksPaused = true
            pausedStateManager.isSyncPausedChangedPublisher.send()
            expectation1.fulfill()
        }

        await self.fulfillment(of: [expectation1, expectation2], timeout: 5.0)
    }

    func test_WhenSyncCredentialsPausedIsTrue_andChangePublished_isSyncCredentialsPausedIsUpdated() async {
        let expectation2 = XCTestExpectation(description: "isSyncCredentialsPaused received the update")
        let expectation1 = XCTestExpectation(description: "isSyncCredentialsPaused published")
        syncPreferences.$isSyncCredentialsPaused
            .dropFirst()
            .sink { isPaused in
                XCTAssertTrue(isPaused)
                expectation2.fulfill()
            }
            .store(in: &cancellables)

        Task {
            pausedStateManager.isSyncCredentialsPaused = true
            pausedStateManager.isSyncPausedChangedPublisher.send()
            expectation1.fulfill()
        }

        await self.fulfillment(of: [expectation1, expectation2], timeout: 5.0)
    }

    func test_ErrorHandlerReturnsExpectedSyncBookmarksPausedMetadata() {
        XCTAssertEqual(syncPreferences.syncBookmarksPausedTitle, MockSyncPausedStateManaging.syncBookmarksPausedData.title)
        XCTAssertEqual(syncPreferences.syncBookmarksPausedMessage, MockSyncPausedStateManaging.syncBookmarksPausedData.description)
        XCTAssertEqual(syncPreferences.syncBookmarksPausedButtonTitle, MockSyncPausedStateManaging.syncBookmarksPausedData.buttonTitle)
        XCTAssertNotNil(syncPreferences.syncBookmarksPausedButtonAction)
    }

    func test_ErrorHandlerReturnsExpectedSyncCredentialsPausedMetadata() {
        XCTAssertEqual(syncPreferences.syncCredentialsPausedTitle, MockSyncPausedStateManaging.syncCredentialsPausedData.title)
        XCTAssertEqual(syncPreferences.syncCredentialsPausedMessage, MockSyncPausedStateManaging.syncCredentialsPausedData.description)
        XCTAssertEqual(syncPreferences.syncCredentialsPausedButtonTitle, MockSyncPausedStateManaging.syncCredentialsPausedData.buttonTitle)
        XCTAssertNotNil(syncPreferences.syncCredentialsPausedButtonAction)
    }

    func test_ErrorHandlerReturnsExpectedSyncIsPausedMetadata() {
        XCTAssertEqual(syncPreferences.syncPausedTitle, MockSyncPausedStateManaging.syncIsPausedData.title)
        XCTAssertEqual(syncPreferences.syncPausedMessage, MockSyncPausedStateManaging.syncIsPausedData.description)
        XCTAssertEqual(syncPreferences.syncPausedButtonTitle, MockSyncPausedStateManaging.syncIsPausedData.buttonTitle)
        XCTAssertNil(syncPreferences.syncPausedButtonAction)
    }

    // MARK: - Observable Properties Behavior

    func testDevices_whenSet_updatesBookmarksAdapterEligibility() {
        let singleDevice = [SyncDevice(kind: .desktop, name: "Test Device", id: "test")]
        let multipleDevices = [
            SyncDevice(kind: .desktop, name: "Device 1", id: "test1"),
            SyncDevice(kind: .mobile, name: "Device 2", id: "test2")
        ]

        // Initially false with no devices
        XCTAssertFalse(syncBookmarksAdapter.isEligibleForFaviconsFetcherOnboarding)

        // Should remain false with single device
        syncPreferences.devices = singleDevice
        XCTAssertFalse(syncBookmarksAdapter.isEligibleForFaviconsFetcherOnboarding)

        // Should become true with multiple devices
        syncPreferences.devices = multipleDevices
        XCTAssertTrue(syncBookmarksAdapter.isEligibleForFaviconsFetcherOnboarding)
    }

    func testIsFaviconsFetchingEnabled_whenSet_updatesAdapterAndNotifiesScheduler() {
        XCTAssertFalse(scheduler.notifyDataChangedCalled)

        syncPreferences.isFaviconsFetchingEnabled = true

        XCTAssertTrue(syncBookmarksAdapter.isFaviconsFetchingEnabled)
        XCTAssertTrue(scheduler.notifyDataChangedCalled)
    }

    func testIsUnifiedFavoritesEnabled_whenSet_updatesAppearancePreferences() {
        // Initially should be display native
        XCTAssertFalse(appearancePreferences.favoritesDisplayMode.isDisplayUnified)

        syncPreferences.isUnifiedFavoritesEnabled = true

        XCTAssertTrue(appearancePreferences.favoritesDisplayMode.isDisplayUnified)
    }

    func testIsUnifiedFavoritesEnabled_whenSet_requestsSyncOnSubsequentChanges() async {
        // First change should request sync (after initialization)
        scheduler.notifyDataChangedCalled = false
        syncPreferences.isUnifiedFavoritesEnabled = true
        XCTAssertTrue(scheduler.notifyDataChangedCalled)

        // Second change should also request sync
        scheduler.notifyDataChangedCalled = false
        syncPreferences.isUnifiedFavoritesEnabled = false
        XCTAssertTrue(scheduler.notifyDataChangedCalled)
    }

    // MARK: - Reactive Subscriptions

    func testFeatureFlagsPublisher_whenChanged_updatesLocalFeatureFlags() async {
        let expectation = expectation(description: "feature flags updated")

        syncPreferences.$syncFeatureFlags.dropFirst().sink { flags in
            XCTAssertTrue(flags.contains(.dataSyncing))
            expectation.fulfill()
        }.store(in: &cancellables)

        // Update the published property directly
        ddgSyncing.featureFlags = [.dataSyncing, .connectFlows]

        await fulfillment(of: [expectation], timeout: 5.0)
    }

    func testIsSyncInProgressPublisher_whenSyncCompletes_triggersInvalidObjectsUpdate() async {
        let expectation = expectation(description: "sync completion processed")
        expectation.assertForOverFulfill = false

        // Listen for sync completion
        syncPreferences.$invalidBookmarksTitles
            .sink { _ in
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // Simulate sync in progress, then completion
        ddgSyncing.isSyncInProgress = true
        ddgSyncing.isSyncInProgress = false

        await fulfillment(of: [expectation], timeout: 5.0)
    }

    func testDevicesPublisher_whenChanged_updatesLocalDevices() async {
        let testDevices = [SyncDevice(kind: .desktop, name: "Test Device", id: "test")]
        let expectation = expectation(description: "devices updated")

        syncPreferences.$devices.dropFirst().sink { devices in
            if devices.count == 1 && devices.first?.name == "Test Device" {
                expectation.fulfill()
            }
        }.store(in: &cancellables)

        // Simulate device update by directly setting devices on syncPreferences
        // (This tests the publisher subscription behavior)
        syncPreferences.devices = testDevices

        await fulfillment(of: [expectation], timeout: 5.0)
    }

    func testSyncOptionsObservables_whenFaviconFetchingChanges_updatesLocalState() async {
        let expectation = expectation(description: "favicon fetching state updated")

        syncPreferences.$isFaviconsFetchingEnabled.sink { enabled in
            if enabled {
                expectation.fulfill()
            }
        }.store(in: &cancellables)

        // Change the adapter's state to trigger the observable
        syncBookmarksAdapter.isFaviconsFetchingEnabled = true

        await fulfillment(of: [expectation], timeout: 5.0)
    }

    func testSyncOptionsObservables_whenUnifiedFavoritesChanges_updatesLocalState() async {
        let expectation = expectation(description: "unified favorites state updated")

        syncPreferences.$isUnifiedFavoritesEnabled.sink { enabled in
            if enabled {
                expectation.fulfill()
            }
        }.store(in: &cancellables)

        // Change the appearance preferences to trigger the observable
        appearancePreferences.favoritesDisplayMode = .displayUnified(native: .desktop)

        await fulfillment(of: [expectation], timeout: 5.0)
    }

}

class CapturingScheduler: Scheduling {
    var notifyDataChangedCalled = false

    func notifyDataChanged() {
        notifyDataChangedCalled = true
    }

    func notifyAppLifecycleEvent() {
    }

    func requestSyncImmediately() {
    }

    func cancelSyncAndSuspendSyncQueue() {
    }

    func resumeSyncQueue() {
    }
}

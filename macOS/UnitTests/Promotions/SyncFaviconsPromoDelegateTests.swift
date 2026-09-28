//
//  SyncFaviconsPromoDelegateTests.swift
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

import Bookmarks
import Combine
@testable import DDGSync
@_spi(Testing) import Persistence
import PrivacyConfig
import PrivacyConfigTestsUtils
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class SyncFaviconsPromoDelegateTests: XCTestCase {

    private var featureFlagger: MockFeatureFlagger!
    private var ddgSyncing: MockDDGSyncing!
    private var syncBookmarksAdapter: SyncBookmarksAdapter!
    private var windowControllersManager: WindowControllersManagerMock!
    private var storage: KeyedStorage<SyncFaviconsPromoSettings>!
    private var sut: SyncFaviconsPromoDelegate!

    private var bookmarksDatabase: CoreDataDatabase!
    private var location: URL!

    override func setUp() {
        super.setUp()
        setUpDatabase()
        featureFlagger = MockFeatureFlagger()
        featureFlagger.enabledFeatureFlags = [.promoQueueSyncFaviconsPromo]
        ddgSyncing = MockDDGSyncing(authState: .inactive, isSyncInProgress: false)
        syncBookmarksAdapter = SyncBookmarksAdapter(database: bookmarksDatabase,
                                                    bookmarkManager: MockBookmarkManager(),
                                                    appearancePreferences: AppearancePreferences(
                                                        persistor: MockAppearancePreferencesPersistor(),
                                                        privacyConfigurationManager: MockPrivacyConfigurationManager(),
                                                        featureFlagger: MockFeatureFlagger(),
                                                        aiChatMenuConfig: MockAIChatConfig()
                                                    ),
                                                    syncErrorHandler: SyncErrorHandler())
        syncBookmarksAdapter.isEligibleForFaviconsFetcherOnboarding = true
        windowControllersManager = WindowControllersManagerMock()
        storage = KeyedStorage(storage: InMemoryKeyValueStore())
        sut = makeSUT()
    }

    override func tearDown() {
        sut = nil
        storage = nil
        windowControllersManager = nil
        syncBookmarksAdapter = nil
        ddgSyncing = nil
        featureFlagger = nil
        tearDownDatabase()
        UserDefaultsWrapper<Bool>.sharedDefaults.removeObject(forKey: UserDefaultsWrapper<Any>.Key.syncIsEligibleForFaviconsFetcherOnboarding.rawValue)
        UserDefaultsWrapper<Bool>.sharedDefaults.removeObject(forKey: UserDefaultsWrapper<Any>.Key.syncIsFaviconsFetcherEnabled.rawValue)
        super.tearDown()
    }

    private func makeSUT() -> SyncFaviconsPromoDelegate {
        SyncFaviconsPromoDelegate(featureFlagger: featureFlagger,
                                  syncService: ddgSyncing,
                                  syncBookmarksAdapter: syncBookmarksAdapter,
                                  windowControllersManager: windowControllersManager,
                                  storage: storage)
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

    // MARK: - Eligibility

    func testWhenAllConditionsMetThenEligible() {
        XCTAssertTrue(sut.isEligible)
    }

    func testWhenPromoFeatureFlagOffThenNotEligible() {
        featureFlagger.enabledFeatureFlags = []

        XCTAssertFalse(sut.isEligible)
    }

    func testWhenSyncUIFeatureFlagOffThenNotEligible() {
        ddgSyncing.featureFlags = []

        XCTAssertFalse(sut.isEligible)
    }

    func testWhenFaviconsFetchingAlreadyEnabledThenNotEligible() {
        syncBookmarksAdapter.isFaviconsFetchingEnabled = true

        XCTAssertFalse(sut.isEligible)
    }

    func testWhenNotEligibleForFaviconsFetcherOnboardingThenNotEligible() {
        syncBookmarksAdapter.isEligibleForFaviconsFetcherOnboarding = false

        XCTAssertFalse(sut.isEligible)
    }

    func testWhenSyncServiceIsNilThenNotEligible() {
        sut = SyncFaviconsPromoDelegate(featureFlagger: featureFlagger, syncService: nil, syncBookmarksAdapter: syncBookmarksAdapter, windowControllersManager: windowControllersManager, storage: storage)

        XCTAssertFalse(sut.isEligible)
    }

    func testWhenSyncBookmarksAdapterIsNilThenNotEligible() {
        sut = SyncFaviconsPromoDelegate(featureFlagger: featureFlagger, syncService: ddgSyncing, syncBookmarksAdapter: nil, windowControllersManager: windowControllersManager, storage: storage)

        XCTAssertFalse(sut.isEligible)
    }

    func testEligiblePublisherReplaysCurrentValueAndEmitsOnRefresh() {
        var received: [Bool] = []
        let cancellable = sut.isEligiblePublisher.sink { received.append($0) }

        syncBookmarksAdapter.isFaviconsFetchingEnabled = true
        sut.refreshEligibility()
        syncBookmarksAdapter.isFaviconsFetchingEnabled = false
        sut.refreshEligibility()

        cancellable.cancel()
        XCTAssertEqual(received, [true, false, true])
    }

    // MARK: - show()

    func testWhenThereIsNoKeyWindowThenShowReturnsNoChange() async {
        let result = await sut.show(history: PromoHistoryRecord(id: PromoServiceFactory.syncFaviconsPromoID), force: false)

        XCTAssertEqual(result, .noChange)
    }

    func testWhenLegacyDialogWasAlreadyShownThenShowRetiresThePromo() async {
        storage.didPresentLegacyDialog = true

        let result = await sut.show(history: PromoHistoryRecord(id: PromoServiceFactory.syncFaviconsPromoID), force: false)

        XCTAssertEqual(result, .retired)
    }

    // MARK: - hide()

    func testHideBeforeShowingDoesNothing() {
        sut.hide()
        sut.hide()
    }

    // MARK: - Resolution paths

    func testDismissResult_whenNotEnablingFaviconsFetching_returnsBareIgnoredAndDoesNotEnableFetching() {
        let result = sut.dismissResult(enableFaviconsFetching: false)

        XCTAssertEqual(result, .ignored())
        XCTAssertFalse(syncBookmarksAdapter.isFaviconsFetchingEnabled)
    }

    func testDismissResult_whenEnablingFaviconsFetching_returnsActionedAndEnablesFetchingAndNotifiesScheduler() {
        let scheduler = CapturingScheduler()
        ddgSyncing = MockDDGSyncing(authState: .inactive, scheduler: scheduler, isSyncInProgress: false)
        sut = makeSUT()

        let result = sut.dismissResult(enableFaviconsFetching: true)

        XCTAssertEqual(result, .actioned)
        XCTAssertTrue(syncBookmarksAdapter.isFaviconsFetchingEnabled)
        XCTAssertTrue(scheduler.notifyDataChangedCalled)
    }

    func testDismissResult_whenDependenciesAreNil_stillReturnsCorrectResultWithoutCrashing() {
        sut = SyncFaviconsPromoDelegate(featureFlagger: featureFlagger, syncService: nil, syncBookmarksAdapter: nil, windowControllersManager: windowControllersManager, storage: storage)

        XCTAssertEqual(sut.dismissResult(enableFaviconsFetching: false), .ignored())
        XCTAssertEqual(sut.dismissResult(enableFaviconsFetching: true), .actioned)
    }

    // MARK: - Trigger wiring

    func testWhenMissingBookmarkFaviconEncounteredNotificationPosted_thenPromoTriggerFires() {
        let expectation = expectation(description: "trigger fired")
        let cancellable = PromoTrigger.triggerPublisher
            .filter { $0 == .missingBookmarkFaviconEncountered }
            .sink { _ in expectation.fulfill() }

        NotificationCenter.default.post(name: .missingBookmarkFaviconEncountered, object: nil)

        waitForExpectations(timeout: 1)
        cancellable.cancel()
    }
}

//
//  SyncPromoManagerTests.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import PrivacyConfig
@testable import Core
@testable import DDGSync
@testable import DuckDuckGo

final class SyncPromoManagerTests: XCTestCase {

    let testGroupName = "test"
    var customSuite: UserDefaults!
    var syncService: MockDDGSyncing!

    override func setUpWithError() throws {
        try super.setUpWithError()

        PixelFiringMock.tearDown()
        customSuite = UserDefaults(suiteName: testGroupName)
        customSuite.removePersistentDomain(forName: testGroupName)
        syncService = MockDDGSyncing(authState: .inactive, scheduler: CapturingScheduler(), isSyncInProgress: false)
        UserDefaults.app = customSuite
    }

    override func tearDownWithError() throws {
        PixelFiringMock.tearDown()
        UserDefaults.app = .standard
        syncService = nil

        super.tearDown()
    }

    func testWhenAllConditionsMetThenShouldPresentPromoForBookmarks() {
        let featureFlagger = createFeatureFlagger(withFeatureFlagsEnabled: [.syncPromotionBookmarks, .sync])
        syncService.authState = .inactive

        let syncPromoManager = SyncPromoManager(syncService: syncService, featureFlagger: featureFlagger)
        syncPromoManager.resetPromos()

        XCTAssertTrue(syncPromoManager.shouldPresentPromoFor(.bookmarks, count: 1))
    }


    func testWhenSyncPromotionBookmarksFeatureFlagDisabledThenShouldNotPresentPromoForBookmarks() {
        let featureFlagger = createFeatureFlagger(withFeatureFlagsEnabled: [.sync])
        syncService.authState = .inactive

        let syncPromoManager = SyncPromoManager(syncService: syncService, featureFlagger: featureFlagger)
        syncPromoManager.resetPromos()

        XCTAssertFalse(syncPromoManager.shouldPresentPromoFor(.bookmarks, count: 1))
    }

    func testWhenSyncFeatureFlagDisabledThenShouldNotPresentPromoForBookmarks() {
        let featureFlagger = createFeatureFlagger(withFeatureFlagsEnabled: [.syncPromotionBookmarks])
        syncService.authState = .inactive

        let syncPromoManager = SyncPromoManager(syncService: syncService, featureFlagger: featureFlagger)
        syncPromoManager.resetPromos()

        XCTAssertFalse(syncPromoManager.shouldPresentPromoFor(.bookmarks, count: 1))
    }

    func testWhenSyncServiceAuthStateActiveThenShouldNotPresentPromoForBookmarks() {
        let featureFlagger = createFeatureFlagger(withFeatureFlagsEnabled: [.syncPromotionBookmarks, .sync])
        syncService.authState = .active

        let syncPromoManager = SyncPromoManager(syncService: syncService, featureFlagger: featureFlagger)
        syncPromoManager.resetPromos()

        XCTAssertFalse(syncPromoManager.shouldPresentPromoFor(.bookmarks, count: 1))
    }

    func testWhenSyncPromoBookmarksDismissedThenShouldNotPresentPromoForBookmarks() {
        let featureFlagger = createFeatureFlagger(withFeatureFlagsEnabled: [.syncPromotionBookmarks, .sync])
        syncService.authState = .inactive

        let syncPromoManager = SyncPromoManager(syncService: syncService, featureFlagger: featureFlagger)
        syncPromoManager.resetPromos()
        syncPromoManager.dismissPromoFor(.bookmarks, reason: .userTapped)

        XCTAssertFalse(syncPromoManager.shouldPresentPromoFor(.bookmarks, count: 1))
    }

    func testWhenBookmarksCountIsZeroThenShouldNotPresentPromoForBookmarks() {
        let featureFlagger = createFeatureFlagger(withFeatureFlagsEnabled: [.syncPromotionBookmarks, .sync])
        syncService.authState = .inactive

        let syncPromoManager = SyncPromoManager(syncService: syncService, featureFlagger: featureFlagger)
        syncPromoManager.resetPromos()

        XCTAssertFalse(syncPromoManager.shouldPresentPromoFor(.bookmarks, count: 0))
    }

    func testWhenAllConditionsMetThenShouldPresentPromoForPasswords() {
        let featureFlagger = createFeatureFlagger(withFeatureFlagsEnabled: [.syncPromotionPasswords, .sync])
        syncService.authState = .inactive

        let syncPromoManager = SyncPromoManager(syncService: syncService, featureFlagger: featureFlagger)
        syncPromoManager.resetPromos()

        XCTAssertTrue(syncPromoManager.shouldPresentPromoFor(.passwords, count: 1))
    }

    func testWhenSyncPromotionPasswordsFeatureFlagDisabledThenShouldNotPresentPromoForPasswords() {
        let featureFlagger = createFeatureFlagger(withFeatureFlagsEnabled: [.sync])
        syncService.authState = .inactive

        let syncPromoManager = SyncPromoManager(syncService: syncService, featureFlagger: featureFlagger)
        syncPromoManager.resetPromos()

        XCTAssertFalse(syncPromoManager.shouldPresentPromoFor(.passwords, count: 1))
    }

    func testWhenSyncFeatureFlagDisabledThenShouldNotPresentPromoForPasswords() {
        let featureFlagger = createFeatureFlagger(withFeatureFlagsEnabled: [.syncPromotionPasswords])
        syncService.authState = .inactive

        let syncPromoManager = SyncPromoManager(syncService: syncService, featureFlagger: featureFlagger)
        syncPromoManager.resetPromos()

        XCTAssertFalse(syncPromoManager.shouldPresentPromoFor(.passwords, count: 1))
    }

    func testWhenSyncServiceAuthStateActiveThenShouldNotPresentPromoForPasswords() {
        let featureFlagger = createFeatureFlagger(withFeatureFlagsEnabled: [.syncPromotionPasswords, .sync])
        syncService.authState = .active

        let syncPromoManager = SyncPromoManager(syncService: syncService, featureFlagger: featureFlagger)
        syncPromoManager.resetPromos()

        XCTAssertFalse(syncPromoManager.shouldPresentPromoFor(.passwords, count: 1))
    }

    func testWhenSyncPromoPasswordsDismissedThenShouldNotPresentPromoForPasswords() {
        let featureFlagger = createFeatureFlagger(withFeatureFlagsEnabled: [.syncPromotionPasswords, .sync])
        syncService.authState = .inactive

        let syncPromoManager = SyncPromoManager(syncService: syncService, featureFlagger: featureFlagger)
        syncPromoManager.resetPromos()
        syncPromoManager.dismissPromoFor(.passwords, reason: .userTapped)

        XCTAssertFalse(syncPromoManager.shouldPresentPromoFor(.passwords, count: 1))
    }

    func testWhenPasswordsCountIsZeroThenShouldNotPresentPromoForPasswords() {
        let featureFlagger = createFeatureFlagger(withFeatureFlagsEnabled: [.syncPromotionPasswords, .sync])
        syncService.authState = .inactive

        let syncPromoManager = SyncPromoManager(syncService: syncService, featureFlagger: featureFlagger)
        syncPromoManager.resetPromos()

        XCTAssertFalse(syncPromoManager.shouldPresentPromoFor(.passwords, count: 0))
    }

    // MARK: - Data Import Tests

    func testWhenAllConditionsMetThenShouldPresentPromoForDataImport() {
        let featureFlagger = createFeatureFlagger(withFeatureFlagsEnabled: [.dataImportSummarySyncPromotion])
        syncService.authState = .inactive

        let syncPromoManager = SyncPromoManager(syncService: syncService, featureFlagger: featureFlagger)
        syncPromoManager.resetPromos()

        XCTAssertTrue(syncPromoManager.shouldPresentPromoFor(.dataImport, count: 1))
    }

    func testWhenDataImportSummarySyncPromotionFeatureFlagDisabledThenShouldNotPresentPromoForDataImport() {
        let featureFlagger = createFeatureFlagger(withFeatureFlagsEnabled: [])
        syncService.authState = .inactive

        let syncPromoManager = SyncPromoManager(syncService: syncService, featureFlagger: featureFlagger)
        syncPromoManager.resetPromos()

        XCTAssertFalse(syncPromoManager.shouldPresentPromoFor(.dataImport, count: 1))
    }

    func testWhenSyncServiceAuthStateActiveThenShouldNotPresentPromoForDataImport() {
        let featureFlagger = createFeatureFlagger(withFeatureFlagsEnabled: [.dataImportSummarySyncPromotion])
        syncService.authState = .active

        let syncPromoManager = SyncPromoManager(syncService: syncService, featureFlagger: featureFlagger)
        syncPromoManager.resetPromos()

        XCTAssertFalse(syncPromoManager.shouldPresentPromoFor(.dataImport, count: 1))
    }

    func testWhenSyncPromoDataImportDismissedThenShouldNotPresentPromoForDataImport() {
        let featureFlagger = createFeatureFlagger(withFeatureFlagsEnabled: [.dataImportSummarySyncPromotion])
        syncService.authState = .inactive

        let syncPromoManager = SyncPromoManager(syncService: syncService, featureFlagger: featureFlagger)
        syncPromoManager.resetPromos()
        syncPromoManager.dismissPromoFor(.dataImport, reason: .userTapped)

        XCTAssertFalse(syncPromoManager.shouldPresentPromoFor(.dataImport, count: 1))
    }

    func testWhenDataImportCountIsZeroThenShouldNotPresentPromoForDataImport() {
        let featureFlagger = createFeatureFlagger(withFeatureFlagsEnabled: [.dataImportSummarySyncPromotion])
        syncService.authState = .inactive

        let syncPromoManager = SyncPromoManager(syncService: syncService, featureFlagger: featureFlagger)
        syncPromoManager.resetPromos()

        XCTAssertFalse(syncPromoManager.shouldPresentPromoFor(.dataImport, count: 0))
    }

    // MARK: - AI Chat Tests

    func testWhenAllConditionsMetThenShouldPresentPromoForAIChat() {
        let featureFlagger = createFeatureFlagger(withFeatureFlagsEnabled: [.sync, .aiChatSync, .aiChatSyncPromo])
        syncService.authState = .inactive

        let syncPromoManager = SyncPromoManager(syncService: syncService,
                                                featureFlagger: featureFlagger,
                                                privacyConfigurationManager: makePrivacyConfigManager(historyEnabled: true))
        syncPromoManager.resetPromos()

        XCTAssertTrue(syncPromoManager.shouldPresentPromoFor(.aiChat, count: 1))
    }

    func testWhenSyncFeatureFlagDisabledThenShouldNotPresentPromoForAIChat() {
        let featureFlagger = createFeatureFlagger(withFeatureFlagsEnabled: [.aiChatSync, .aiChatSyncPromo])
        syncService.authState = .inactive

        let syncPromoManager = SyncPromoManager(syncService: syncService,
                                                featureFlagger: featureFlagger,
                                                privacyConfigurationManager: makePrivacyConfigManager(historyEnabled: true))
        syncPromoManager.resetPromos()

        XCTAssertFalse(syncPromoManager.shouldPresentPromoFor(.aiChat, count: 1))
    }

    func testWhenAIChatHistoryIsEmptyThenShouldNotPresentPromoForAIChat() {
        let featureFlagger = createFeatureFlagger(withFeatureFlagsEnabled: [.sync, .aiChatSync, .aiChatSyncPromo])
        syncService.authState = .inactive

        let syncPromoManager = SyncPromoManager(syncService: syncService,
                                                featureFlagger: featureFlagger,
                                                privacyConfigurationManager: makePrivacyConfigManager(historyEnabled: true))
        syncPromoManager.resetPromos()

        XCTAssertFalse(syncPromoManager.shouldPresentPromoFor(.aiChat, count: 0))
    }

    func testWhenAIChatSyncPromoFeatureFlagDisabledThenShouldNotPresentPromoForAIChat() {
        let featureFlagger = createFeatureFlagger(withFeatureFlagsEnabled: [.sync, .aiChatSync])
        syncService.authState = .inactive

        let syncPromoManager = SyncPromoManager(syncService: syncService,
                                                featureFlagger: featureFlagger,
                                                privacyConfigurationManager: makePrivacyConfigManager(historyEnabled: true))
        syncPromoManager.resetPromos()

        XCTAssertFalse(syncPromoManager.shouldPresentPromoFor(.aiChat, count: 1))
    }

    func testWhenAIChatSyncFeatureFlagDisabledThenShouldNotPresentPromoForAIChat() {
        let featureFlagger = createFeatureFlagger(withFeatureFlagsEnabled: [.sync, .aiChatSyncPromo])
        syncService.authState = .inactive

        let syncPromoManager = SyncPromoManager(syncService: syncService,
                                                featureFlagger: featureFlagger,
                                                privacyConfigurationManager: makePrivacyConfigManager(historyEnabled: true))
        syncPromoManager.resetPromos()

        XCTAssertFalse(syncPromoManager.shouldPresentPromoFor(.aiChat, count: 1))
    }

    func testWhenAIChatHistoryDisabledThenShouldNotPresentPromoForAIChat() {
        let featureFlagger = createFeatureFlagger(withFeatureFlagsEnabled: [.sync, .aiChatSync, .aiChatSyncPromo])
        syncService.authState = .inactive

        let syncPromoManager = SyncPromoManager(syncService: syncService,
                                                featureFlagger: featureFlagger,
                                                privacyConfigurationManager: makePrivacyConfigManager(historyEnabled: false))
        syncPromoManager.resetPromos()

        XCTAssertFalse(syncPromoManager.shouldPresentPromoFor(.aiChat, count: 1))
    }

    func testWhenSyncServiceAuthStateActiveThenShouldNotPresentPromoForAIChat() {
        let featureFlagger = createFeatureFlagger(withFeatureFlagsEnabled: [.sync, .aiChatSync, .aiChatSyncPromo])
        syncService.authState = .active

        let syncPromoManager = SyncPromoManager(syncService: syncService,
                                                featureFlagger: featureFlagger,
                                                privacyConfigurationManager: makePrivacyConfigManager(historyEnabled: true))
        syncPromoManager.resetPromos()

        XCTAssertFalse(syncPromoManager.shouldPresentPromoFor(.aiChat, count: 1))
    }

    func testWhenSyncPromoAIChatDismissedThenShouldNotPresentPromoForAIChat() {
        let featureFlagger = createFeatureFlagger(withFeatureFlagsEnabled: [.sync, .aiChatSync, .aiChatSyncPromo])
        syncService.authState = .inactive

        let syncPromoManager = SyncPromoManager(syncService: syncService,
                                                featureFlagger: featureFlagger,
                                                privacyConfigurationManager: makePrivacyConfigManager(historyEnabled: true))
        syncPromoManager.resetPromos()
        syncPromoManager.dismissPromoFor(.aiChat, reason: .userTapped)

        XCTAssertFalse(syncPromoManager.shouldPresentPromoFor(.aiChat, count: 1))
    }

    func testWhenImpressionsBelowCapThenShouldPresentPromoForAIChat() {
        let featureFlagger = createFeatureFlagger(withFeatureFlagsEnabled: [.sync, .aiChatSync, .aiChatSyncPromo])
        syncService.authState = .inactive

        let syncPromoManager = SyncPromoManager(syncService: syncService,
                                                featureFlagger: featureFlagger,
                                                privacyConfigurationManager: makePrivacyConfigManager(historyEnabled: true))
        syncPromoManager.resetPromos()

        syncPromoManager.recordImpressionFor(.aiChat)
        syncPromoManager.recordImpressionFor(.aiChat)

        XCTAssertTrue(syncPromoManager.shouldPresentPromoFor(.aiChat, count: 1))
    }

    func testWhenImpressionsReachCapThenShouldNotPresentPromoForAIChat() {
        let featureFlagger = createFeatureFlagger(withFeatureFlagsEnabled: [.sync, .aiChatSync, .aiChatSyncPromo])
        syncService.authState = .inactive

        let syncPromoManager = SyncPromoManager(syncService: syncService,
                                                featureFlagger: featureFlagger,
                                                privacyConfigurationManager: makePrivacyConfigManager(historyEnabled: true))
        syncPromoManager.resetPromos()

        for _ in 0..<SyncPromoManager.aiChatImpressionCap {
            syncPromoManager.recordImpressionFor(.aiChat)
        }

        XCTAssertFalse(syncPromoManager.shouldPresentPromoFor(.aiChat, count: 1))
    }

    func testWhenResetPromosThenAIChatImpressionsAreCleared() {
        let featureFlagger = createFeatureFlagger(withFeatureFlagsEnabled: [.sync, .aiChatSync, .aiChatSyncPromo])
        syncService.authState = .inactive

        let syncPromoManager = SyncPromoManager(syncService: syncService,
                                                featureFlagger: featureFlagger,
                                                privacyConfigurationManager: makePrivacyConfigManager(historyEnabled: true))
        syncPromoManager.resetPromos()

        for _ in 0..<SyncPromoManager.aiChatImpressionCap {
            syncPromoManager.recordImpressionFor(.aiChat)
        }
        XCTAssertFalse(syncPromoManager.shouldPresentPromoFor(.aiChat, count: 1))

        syncPromoManager.resetPromos()

        XCTAssertTrue(syncPromoManager.shouldPresentPromoFor(.aiChat, count: 1))
    }

    func testRecordImpressionIsNoOpForUncappedTouchpoints() {
        let featureFlagger = createFeatureFlagger(withFeatureFlagsEnabled: [.syncPromotionBookmarks, .sync])
        syncService.authState = .inactive

        let syncPromoManager = SyncPromoManager(syncService: syncService,
                                                featureFlagger: featureFlagger,
                                                privacyConfigurationManager: makePrivacyConfigManager(historyEnabled: true))
        syncPromoManager.resetPromos()

        for _ in 0..<10 {
            syncPromoManager.recordImpressionFor(.bookmarks)
        }

        XCTAssertTrue(syncPromoManager.shouldPresentPromoFor(.bookmarks, count: 1))
    }

    // MARK: - Pixels

    func testDismissPromoFiresDismissedPixelWithTouchpointAndReason() {
        let syncPromoManager = SyncPromoManager(syncService: syncService,
                                                pixelFiring: PixelFiringMock.self)

        for touchpoint in [SyncPromoManager.Touchpoint.bookmarks, .passwords, .dataImport, .aiChat] {
            PixelFiringMock.tearDown()

            syncPromoManager.dismissPromoFor(touchpoint, reason: .userTapped)

            XCTAssertEqual(PixelFiringMock.allPixelsFired.count, 1)
            XCTAssertEqual(PixelFiringMock.lastPixelName, Pixel.Event.syncPromoDismissed.name)
            XCTAssertEqual(PixelFiringMock.lastParams, [
                "source": touchpoint.rawValue,
                "reason": SyncPromoManager.DismissalReason.userTapped.rawValue
            ])
        }
    }

    func testRecordImpressionForAIChatWhenCapReachedFiresDismissedPixelWithImpressionCapReason() {
        let featureFlagger = createFeatureFlagger(withFeatureFlagsEnabled: [.sync, .aiChatSync, .aiChatSyncPromo])
        syncService.authState = .inactive

        let syncPromoManager = SyncPromoManager(syncService: syncService,
                                                featureFlagger: featureFlagger,
                                                privacyConfigurationManager: makePrivacyConfigManager(historyEnabled: true),
                                                pixelFiring: PixelFiringMock.self)
        syncPromoManager.resetPromos()

        for _ in 0..<SyncPromoManager.aiChatImpressionCap {
            syncPromoManager.recordImpressionFor(.aiChat)
        }

        XCTAssertEqual(PixelFiringMock.allPixelsFired.count, 1)
        XCTAssertEqual(PixelFiringMock.lastPixelName, Pixel.Event.syncPromoDismissed.name)
        XCTAssertEqual(PixelFiringMock.lastParams, [
            "source": SyncPromoManager.Touchpoint.aiChat.rawValue,
            "reason": SyncPromoManager.DismissalReason.impressionCap.rawValue
        ])
    }

    // MARK: - Mock Creation

    private func createFeatureFlagger(withFeatureFlagsEnabled featureFlags: [FeatureFlag]) -> FeatureFlagger {
        let mockFeatureFlagger = MockFeatureFlagger()
        mockFeatureFlagger.enabledFeatureFlags.append(contentsOf: featureFlags)
        return mockFeatureFlagger
    }

    private func makePrivacyConfigManager(historyEnabled: Bool) -> MockPrivacyConfigurationManager {
        let manager = MockPrivacyConfigurationManager()
        let config = MockPrivacyConfiguration()
        config.isFeatureKeyEnabled = { feature, _ in
            feature == .duckAiChatHistory ? historyEnabled : true
        }
        manager.privacyConfig = config
        return manager
    }

}

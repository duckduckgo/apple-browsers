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
import FeatureFlags_iOS
@_spi(Testing) import Persistence
@testable import Core
@testable import DDGSync
@testable import DuckDuckGo
@_spi(Testing) import PixelKit

final class SyncPromoManagerTests: XCTestCase {

    let testGroupName = "test"
    var customSuite: UserDefaults!
    var syncService: MockDDGSyncing!
    var pixelKitMock: PixelKitMock!
    var anotherDeviceStorage: (any KeyedStoring<SyncPromoStorageKeys>)!

    override func setUpWithError() throws {
        try super.setUpWithError()

        pixelKitMock = PixelKitMock()
        anotherDeviceStorage = MockKeyValueStore().keyedStoring()
        customSuite = UserDefaults(suiteName: testGroupName)
        customSuite.removePersistentDomain(forName: testGroupName)
        syncService = MockDDGSyncing(authState: .inactive, scheduler: CapturingScheduler(), isSyncInProgress: false)
        UserDefaults.app = customSuite
    }

    override func tearDownWithError() throws {
        pixelKitMock = nil
        anotherDeviceStorage = nil
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
        let featureFlagger = createFeatureFlagger(withFeatureFlagsEnabled: [.sync, .aiChatSync])
        syncService.authState = .inactive

        let syncPromoManager = SyncPromoManager(syncService: syncService,
                                                featureFlagger: featureFlagger,
                                                privacyConfigurationManager: makePrivacyConfigManager(historyEnabled: true))
        syncPromoManager.resetPromos()

        XCTAssertTrue(syncPromoManager.shouldPresentPromoFor(.aiChat, count: 1))
    }

    func testWhenSyncFeatureFlagDisabledThenShouldNotPresentPromoForAIChat() {
        let featureFlagger = createFeatureFlagger(withFeatureFlagsEnabled: [.aiChatSync])
        syncService.authState = .inactive

        let syncPromoManager = SyncPromoManager(syncService: syncService,
                                                featureFlagger: featureFlagger,
                                                privacyConfigurationManager: makePrivacyConfigManager(historyEnabled: true))
        syncPromoManager.resetPromos()

        XCTAssertFalse(syncPromoManager.shouldPresentPromoFor(.aiChat, count: 1))
    }

    func testWhenAIChatHistoryIsEmptyThenShouldNotPresentPromoForAIChat() {
        let featureFlagger = createFeatureFlagger(withFeatureFlagsEnabled: [.sync, .aiChatSync])
        syncService.authState = .inactive

        let syncPromoManager = SyncPromoManager(syncService: syncService,
                                                featureFlagger: featureFlagger,
                                                privacyConfigurationManager: makePrivacyConfigManager(historyEnabled: true))
        syncPromoManager.resetPromos()

        XCTAssertFalse(syncPromoManager.shouldPresentPromoFor(.aiChat, count: 0))
    }

    func testWhenAIChatSyncFeatureFlagDisabledThenShouldNotPresentPromoForAIChat() {
        let featureFlagger = createFeatureFlagger(withFeatureFlagsEnabled: [.sync])
        syncService.authState = .inactive

        let syncPromoManager = SyncPromoManager(syncService: syncService,
                                                featureFlagger: featureFlagger,
                                                privacyConfigurationManager: makePrivacyConfigManager(historyEnabled: true))
        syncPromoManager.resetPromos()

        XCTAssertFalse(syncPromoManager.shouldPresentPromoFor(.aiChat, count: 1))
    }

    func testWhenAIChatHistoryDisabledThenShouldNotPresentPromoForAIChat() {
        let featureFlagger = createFeatureFlagger(withFeatureFlagsEnabled: [.sync, .aiChatSync])
        syncService.authState = .inactive

        let syncPromoManager = SyncPromoManager(syncService: syncService,
                                                featureFlagger: featureFlagger,
                                                privacyConfigurationManager: makePrivacyConfigManager(historyEnabled: false))
        syncPromoManager.resetPromos()

        XCTAssertFalse(syncPromoManager.shouldPresentPromoFor(.aiChat, count: 1))
    }

    func testWhenSyncServiceAuthStateActiveThenShouldNotPresentPromoForAIChat() {
        let featureFlagger = createFeatureFlagger(withFeatureFlagsEnabled: [.sync, .aiChatSync])
        syncService.authState = .active

        let syncPromoManager = SyncPromoManager(syncService: syncService,
                                                featureFlagger: featureFlagger,
                                                privacyConfigurationManager: makePrivacyConfigManager(historyEnabled: true))
        syncPromoManager.resetPromos()

        XCTAssertFalse(syncPromoManager.shouldPresentPromoFor(.aiChat, count: 1))
    }

    func testWhenSyncPromoAIChatDismissedThenShouldNotPresentPromoForAIChat() {
        let featureFlagger = createFeatureFlagger(withFeatureFlagsEnabled: [.sync, .aiChatSync])
        syncService.authState = .inactive

        let syncPromoManager = SyncPromoManager(syncService: syncService,
                                                featureFlagger: featureFlagger,
                                                privacyConfigurationManager: makePrivacyConfigManager(historyEnabled: true))
        syncPromoManager.resetPromos()
        syncPromoManager.dismissPromoFor(.aiChat, reason: .userTapped)

        XCTAssertFalse(syncPromoManager.shouldPresentPromoFor(.aiChat, count: 1))
    }

    func testWhenImpressionsBelowCapThenShouldPresentPromoForAIChat() {
        let featureFlagger = createFeatureFlagger(withFeatureFlagsEnabled: [.sync, .aiChatSync])
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
        let featureFlagger = createFeatureFlagger(withFeatureFlagsEnabled: [.sync, .aiChatSync])
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
        let featureFlagger = createFeatureFlagger(withFeatureFlagsEnabled: [.sync, .aiChatSync])
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
                                                pixelFiring: pixelKitMock)

        for touchpoint in [SyncPromoManager.Touchpoint.bookmarks, .passwords, .dataImport, .aiChat, .bookmarksAnotherDevice, .passwordsAnotherDevice] {
            let countBefore = pixelKitMock.actualFireCalls.count

            syncPromoManager.dismissPromoFor(touchpoint, reason: .userTapped)

            XCTAssertEqual(pixelKitMock.actualFireCalls.count, countBefore + 1)
            XCTAssertEqual(pixelKitMock.actualFireCalls.last?.pixel.name, Pixel.Event.syncPromoDismissed.name)
            XCTAssertEqual(pixelKitMock.actualFireCalls.last?.additionalParameters, [
                "source": touchpoint.rawValue,
                "reason": SyncPromoManager.DismissalReason.userTapped.rawValue
            ])
        }
    }

    func testRecordImpressionForAIChatWhenCapReachedFiresDismissedPixelWithImpressionCapReason() {
        let featureFlagger = createFeatureFlagger(withFeatureFlagsEnabled: [.sync, .aiChatSync])
        syncService.authState = .inactive

        let syncPromoManager = SyncPromoManager(syncService: syncService,
                                                featureFlagger: featureFlagger,
                                                privacyConfigurationManager: makePrivacyConfigManager(historyEnabled: true),
                                                pixelFiring: pixelKitMock)
        syncPromoManager.resetPromos()

        for _ in 0..<SyncPromoManager.aiChatImpressionCap {
            syncPromoManager.recordImpressionFor(.aiChat)
        }

        XCTAssertEqual(pixelKitMock.actualFireCalls.count, 1)
        XCTAssertEqual(pixelKitMock.actualFireCalls.last?.pixel.name, Pixel.Event.syncPromoDismissed.name)
        XCTAssertEqual(pixelKitMock.actualFireCalls.last?.additionalParameters, [
            "source": SyncPromoManager.Touchpoint.aiChat.rawValue,
            "reason": SyncPromoManager.DismissalReason.impressionCap.rawValue
        ])
    }

    // MARK: - Mock Creation

    func testWhenRedesignFlagOnAndInstalledMoreThanThreeDaysAgoThenBookmarksDesignIsRedesigned() {
        let syncPromoManager = makeManager(featureFlags: [.syncPromotionRedesign], installedDaysAgo: 4)

        XCTAssertEqual(syncPromoManager.designFor(.bookmarks), .redesigned)
    }

    func testWhenRedesignFlagOnAndInstalledThreeDaysAgoThenBookmarksDesignIsStandard() {
        let syncPromoManager = makeManager(featureFlags: [.syncPromotionRedesign], installedDaysAgo: 3)

        XCTAssertEqual(syncPromoManager.designFor(.bookmarks), .standard)
    }

    func testWhenRedesignFlagOffThenBookmarksDesignIsStandard() {
        let syncPromoManager = makeManager(featureFlags: [], installedDaysAgo: 30)

        XCTAssertEqual(syncPromoManager.designFor(.bookmarks), .standard)
    }

    func testWhenInstallDateUnknownThenBookmarksDesignIsStandard() {
        let syncPromoManager = makeManager(featureFlags: [.syncPromotionRedesign], installedDaysAgo: nil)

        XCTAssertEqual(syncPromoManager.designFor(.bookmarks), .standard)
    }

    func testWhenRedesignFlagOnAndInstalledMoreThanThreeDaysAgoThenPasswordsDesignIsRedesigned() {
        let syncPromoManager = makeManager(featureFlags: [.syncPromotionRedesign], installedDaysAgo: 4)

        XCTAssertEqual(syncPromoManager.designFor(.passwords), .redesigned)
    }

    func testWhenRedesignFlagOnAndInstalledThreeDaysAgoThenPasswordsDesignIsStandard() {
        let syncPromoManager = makeManager(featureFlags: [.syncPromotionRedesign], installedDaysAgo: 3)

        XCTAssertEqual(syncPromoManager.designFor(.passwords), .standard)
    }

    func testWhenRedesignFlagOffThenPasswordsDesignIsStandard() {
        let syncPromoManager = makeManager(featureFlags: [], installedDaysAgo: 30)

        XCTAssertEqual(syncPromoManager.designFor(.passwords), .standard)
    }

    func testWhenRedesignFlagOnThenAIChatDesignIsStandard() {
        let syncPromoManager = makeManager(featureFlags: [.syncPromotionRedesign], installedDaysAgo: 30)

        XCTAssertEqual(syncPromoManager.designFor(.aiChat), .standard)
    }

    func testWhenPasswordsDesignIsRedesignedThenPromoHasRedesignedPasswordsCopy() {
        let passwords = SyncPromoViewModel(touchpointType: .passwords, design: .redesigned)

        XCTAssertNil(passwords.secondaryButtonTitle)
        XCTAssertEqual(passwords.toggleTitle, UserText.syncPromoToggleTitle)
        XCTAssertEqual(passwords.title, UserText.syncPromoPasswordsTitle)
        XCTAssertEqual(passwords.subtitle, UserText.syncPromoPasswordsRedesignMessage)
    }

    func testWhenPasswordsDesignIsStandardThenPromoKeepsPasswordsCopy() {
        let passwords = SyncPromoViewModel(touchpointType: .passwords, design: .standard)

        XCTAssertEqual(passwords.secondaryButtonTitle, UserText.syncPromoDismissAction)
        XCTAssertEqual(passwords.primaryButtonTitle, UserText.syncPromoConfirmAction)
        XCTAssertEqual(passwords.title, UserText.syncPromoPasswordsTitle)
        XCTAssertEqual(passwords.subtitle, UserText.syncPromoPasswordsMessage)
    }

    func testWhenDesignIsRedesignedThenPromoHasNoDismissButtonAndRedesignCopy() {
        let viewModel = SyncPromoViewModel(touchpointType: .bookmarks, design: .redesigned)

        XCTAssertNil(viewModel.secondaryButtonTitle)
        XCTAssertEqual(viewModel.toggleTitle, UserText.syncPromoToggleTitle)
        XCTAssertEqual(viewModel.title, UserText.syncPromoBookmarksTitle)
        XCTAssertEqual(viewModel.subtitle, UserText.syncPromoBookmarksRedesignMessage)
    }

    func testWhenDesignIsStandardThenPromoKeepsDismissButtonAndSetUpSyncCopy() {
        let viewModel = SyncPromoViewModel(touchpointType: .bookmarks, design: .standard)

        XCTAssertEqual(viewModel.secondaryButtonTitle, UserText.syncPromoDismissAction)
        XCTAssertEqual(viewModel.primaryButtonTitle, UserText.syncPromoConfirmAction)
        XCTAssertEqual(viewModel.subtitle, UserText.syncPromoBookmarksMessage)
    }

    // MARK: - Bookmarks Another Device

    func testWhenAllConditionsMetThenShouldPresentAnotherDevicePromo() {
        let manager = makeAnotherDeviceManager()

        XCTAssertTrue(manager.shouldPresentPromoFor(.bookmarksAnotherDevice, count: 1))
    }

    func testWhenNoBookmarksThenShouldNotPresentAnotherDevicePromo() {
        let manager = makeAnotherDeviceManager()

        XCTAssertFalse(manager.shouldPresentPromoFor(.bookmarksAnotherDevice, count: 0))
    }

    func testWhenAnotherDeviceFlagOffThenShouldNotPresentAnotherDevicePromo() {
        let manager = makeAnotherDeviceManager(featureFlags: [.sync])

        XCTAssertFalse(manager.shouldPresentPromoFor(.bookmarksAnotherDevice, count: 1))
    }

    func testWhenSyncFlagOffThenShouldNotPresentAnotherDevicePromo() {
        let manager = makeAnotherDeviceManager(featureFlags: [.syncPromotionSyncAnotherDevice])

        XCTAssertFalse(manager.shouldPresentPromoFor(.bookmarksAnotherDevice, count: 1))
    }

    func testWhenSyncInactiveThenShouldNotPresentAnotherDevicePromo() {
        let manager = makeAnotherDeviceManager(authState: .inactive)

        XCTAssertFalse(manager.shouldPresentPromoFor(.bookmarksAnotherDevice, count: 1))
    }

    func testWhenAnotherDevicePromoDismissedThenShouldNotPresentIt() {
        let manager = makeAnotherDeviceManager()

        manager.dismissPromoFor(.bookmarksAnotherDevice, reason: .userTapped)

        XCTAssertFalse(manager.shouldPresentPromoFor(.bookmarksAnotherDevice, count: 1))
    }

    func testWhenInstalledExactlySevenDaysAgoThenShouldNotPresentAnotherDevicePromo() {
        let manager = makeAnotherDeviceManager(installedDaysAgo: 7)

        XCTAssertFalse(manager.shouldPresentPromoFor(.bookmarksAnotherDevice, count: 1))
    }

    func testWhenInstalledEightDaysAgoThenShouldPresentAnotherDevicePromo() {
        let manager = makeAnotherDeviceManager(installedDaysAgo: 8)

        XCTAssertTrue(manager.shouldPresentPromoFor(.bookmarksAnotherDevice, count: 1))
    }

    func testWhenInstallDateUnknownThenShouldNotPresentAnotherDevicePromo() {
        let manager = makeAnotherDeviceManager(installedDaysAgo: nil)

        XCTAssertFalse(manager.shouldPresentPromoFor(.bookmarksAnotherDevice, count: 1))
    }

    func testWhenDevicesCountNeverStoredThenShouldNotPresentAnotherDevicePromo() {
        let manager = makeAnotherDeviceManager(syncedDevicesCount: nil)

        XCTAssertFalse(manager.shouldPresentPromoFor(.bookmarksAnotherDevice, count: 1))
    }

    func testWhenOneDeviceStoredThenShouldPresentAnotherDevicePromo() {
        let manager = makeAnotherDeviceManager(syncedDevicesCount: 1)

        XCTAssertTrue(manager.shouldPresentPromoFor(.bookmarksAnotherDevice, count: 1))
    }

    func testWhenTwoDevicesStoredThenShouldNotPresentAnotherDevicePromo() {
        let manager = makeAnotherDeviceManager(syncedDevicesCount: 2)

        XCTAssertFalse(manager.shouldPresentPromoFor(.bookmarksAnotherDevice, count: 1))
    }

    func testWhenSetupPromoConfirmed23HoursAgoThenShouldNotPresentAnotherDevicePromo() {
        let manager = makeAnotherDeviceManager(setupPromoConfirmedHoursAgo: 23)

        XCTAssertFalse(manager.shouldPresentPromoFor(.bookmarksAnotherDevice, count: 1))
    }

    func testWhenSetupPromoConfirmed25HoursAgoThenShouldPresentAnotherDevicePromo() {
        let manager = makeAnotherDeviceManager(setupPromoConfirmedHoursAgo: 25)

        XCTAssertTrue(manager.shouldPresentPromoFor(.bookmarksAnotherDevice, count: 1))
    }

    func testWhenBookmarksSetupPromoConfirmedThenAnotherDevicePromoWaitsForCooldown() {
        let manager = makeAnotherDeviceManager()

        manager.recordPromoConfirmedFor(.bookmarks)

        XCTAssertFalse(manager.shouldPresentPromoFor(.bookmarksAnotherDevice, count: 1))
    }

    func testWhenPasswordsSetupPromoConfirmedThenAnotherDevicePromoWaitsForCooldown() {
        let manager = makeAnotherDeviceManager()

        manager.recordPromoConfirmedFor(.passwords)

        XCTAssertFalse(manager.shouldPresentPromoFor(.bookmarksAnotherDevice, count: 1))
    }

    func testWhenOtherPromosConfirmedThenAnotherDevicePromoIsNotDelayed() {
        let manager = makeAnotherDeviceManager()

        manager.recordPromoConfirmedFor(.aiChat)
        manager.recordPromoConfirmedFor(.dataImport)
        manager.recordPromoConfirmedFor(.bookmarksAnotherDevice)

        XCTAssertTrue(manager.shouldPresentPromoFor(.bookmarksAnotherDevice, count: 1))
    }

    func testWhenResetPromosThenAnotherDeviceDismissalAndCooldownClearButDevicesCountStays() {
        let manager = makeAnotherDeviceManager(syncedDevicesCount: 1)
        manager.dismissPromoFor(.bookmarksAnotherDevice, reason: .userTapped)
        manager.recordPromoConfirmedFor(.bookmarks)

        manager.resetPromos()

        XCTAssertEqual(anotherDeviceStorage.syncedDevicesCount, 1)
        XCTAssertTrue(manager.shouldPresentPromoFor(.bookmarksAnotherDevice, count: 1))
    }

    func testAnotherDevicePromoDesignIsStandard() {
        let manager = makeAnotherDeviceManager(featureFlags: [.syncPromotionSyncAnotherDevice, .sync, .syncPromotionRedesign])

        XCTAssertEqual(manager.designFor(.bookmarksAnotherDevice), .standard)
        XCTAssertEqual(manager.designFor(.passwordsAnotherDevice), .standard)
    }

    // MARK: - Passwords Another Device

    func testWhenAllConditionsMetThenShouldPresentPasswordsAnotherDevicePromo() {
        let manager = makeAnotherDeviceManager()

        XCTAssertTrue(manager.shouldPresentPromoFor(.passwordsAnotherDevice, count: 1))
    }

    func testWhenNoPasswordsThenShouldNotPresentPasswordsAnotherDevicePromo() {
        let manager = makeAnotherDeviceManager()

        XCTAssertFalse(manager.shouldPresentPromoFor(.passwordsAnotherDevice, count: 0))
    }

    func testWhenTwoDevicesStoredThenShouldNotPresentPasswordsAnotherDevicePromo() {
        let manager = makeAnotherDeviceManager(syncedDevicesCount: 2)

        XCTAssertFalse(manager.shouldPresentPromoFor(.passwordsAnotherDevice, count: 1))
    }

    func testWhenSyncInactiveThenShouldNotPresentPasswordsAnotherDevicePromo() {
        let manager = makeAnotherDeviceManager(authState: .inactive)

        XCTAssertFalse(manager.shouldPresentPromoFor(.passwordsAnotherDevice, count: 1))
    }

    func testWhenInstalledExactlySevenDaysAgoThenShouldNotPresentPasswordsAnotherDevicePromo() {
        let manager = makeAnotherDeviceManager(installedDaysAgo: 7)

        XCTAssertFalse(manager.shouldPresentPromoFor(.passwordsAnotherDevice, count: 1))
    }

    func testWhenSetupPromoConfirmed23HoursAgoThenShouldNotPresentPasswordsAnotherDevicePromo() {
        let manager = makeAnotherDeviceManager(setupPromoConfirmedHoursAgo: 23)

        XCTAssertFalse(manager.shouldPresentPromoFor(.passwordsAnotherDevice, count: 1))
    }

    func testWhenPasswordsAnotherDevicePromoDismissedThenOnlyBookmarksAnotherDevicePromoShows() {
        let manager = makeAnotherDeviceManager()

        manager.markPromoHandledFor(.passwordsAnotherDevice)

        XCTAssertFalse(manager.shouldPresentPromoFor(.passwordsAnotherDevice, count: 1))
        XCTAssertTrue(manager.shouldPresentPromoFor(.bookmarksAnotherDevice, count: 1))
    }

    func testWhenBookmarksAnotherDevicePromoDismissedThenOnlyPasswordsAnotherDevicePromoShows() {
        let manager = makeAnotherDeviceManager()

        manager.markPromoHandledFor(.bookmarksAnotherDevice)

        XCTAssertFalse(manager.shouldPresentPromoFor(.bookmarksAnotherDevice, count: 1))
        XCTAssertTrue(manager.shouldPresentPromoFor(.passwordsAnotherDevice, count: 1))
    }

    func testWhenResetPromosThenPasswordsAnotherDeviceDismissalClears() {
        let manager = makeAnotherDeviceManager()
        manager.markPromoHandledFor(.passwordsAnotherDevice)

        manager.resetPromos()

        XCTAssertTrue(manager.shouldPresentPromoFor(.passwordsAnotherDevice, count: 1))
    }

    // MARK: - Synced Devices Count Refresh

    func testWhenRefreshingSyncedDevicesCountThenFetchesDevicesAndStoresCount() async {
        syncService.registeredDevices = twoRegisteredDevices
        let manager = makeAnotherDeviceManager()

        await manager.refreshSyncedDevicesCount()

        XCTAssertEqual(syncService.fetchDevicesCallCount, 1)
        XCTAssertEqual(anotherDeviceStorage.syncedDevicesCount, 2)
    }

    func testWhenAnotherDeviceFlagOffThenRefreshDoesNotFetchDevices() async {
        syncService.registeredDevices = twoRegisteredDevices
        let manager = makeAnotherDeviceManager(featureFlags: [.sync])

        await manager.refreshSyncedDevicesCount()

        XCTAssertEqual(syncService.fetchDevicesCallCount, 0)
        XCTAssertEqual(anotherDeviceStorage.syncedDevicesCount, 1)
    }

    func testWhenSyncInactiveThenRefreshDoesNotFetchDevices() async {
        syncService.registeredDevices = twoRegisteredDevices
        let manager = makeAnotherDeviceManager(authState: .inactive)

        await manager.refreshSyncedDevicesCount()

        XCTAssertEqual(syncService.fetchDevicesCallCount, 0)
        XCTAssertEqual(anotherDeviceStorage.syncedDevicesCount, 1)
    }

    func testWhenOnlyOneAnotherDevicePromoDismissedThenRefreshStillFetchesDevices() async {
        syncService.registeredDevices = twoRegisteredDevices
        let manager = makeAnotherDeviceManager()
        manager.markPromoHandledFor(.bookmarksAnotherDevice)

        await manager.refreshSyncedDevicesCount()

        XCTAssertEqual(syncService.fetchDevicesCallCount, 1)
        XCTAssertEqual(anotherDeviceStorage.syncedDevicesCount, 2)
    }

    func testWhenBothAnotherDevicePromosDismissedThenRefreshDoesNotFetchDevices() async {
        syncService.registeredDevices = twoRegisteredDevices
        let manager = makeAnotherDeviceManager()
        manager.markPromoHandledFor(.bookmarksAnotherDevice)
        manager.markPromoHandledFor(.passwordsAnotherDevice)

        await manager.refreshSyncedDevicesCount()

        XCTAssertEqual(syncService.fetchDevicesCallCount, 0)
        XCTAssertEqual(anotherDeviceStorage.syncedDevicesCount, 1)
    }

    func testWhenFetchingDevicesFailsThenRefreshKeepsPreviousCount() async {
        syncService.fetchDevicesError = FetchDevicesError()
        let manager = makeAnotherDeviceManager()

        await manager.refreshSyncedDevicesCount()

        XCTAssertEqual(syncService.fetchDevicesCallCount, 1)
        XCTAssertEqual(anotherDeviceStorage.syncedDevicesCount, 1)
    }

    private struct FetchDevicesError: Error {}

    private let twoRegisteredDevices = [
        RegisteredDevice(id: "1", name: "iPhone", type: "phone"),
        RegisteredDevice(id: "2", name: "Mac", type: "desktop")
    ]

    private func makeAnotherDeviceManager(featureFlags: [FeatureFlag] = [.syncPromotionSyncAnotherDevice, .sync],
                                          authState: SyncAuthState = .active,
                                          installedDaysAgo: Int? = 8,
                                          syncedDevicesCount: Int? = 1,
                                          setupPromoConfirmedHoursAgo: Int? = nil) -> SyncPromoManager {
        let now = Date()
        let installDate = installedDaysAgo.flatMap { Calendar.current.date(byAdding: .day, value: -$0, to: now) }
        syncService.authState = authState
        anotherDeviceStorage.syncedDevicesCount = syncedDevicesCount
        anotherDeviceStorage.setupPromoConfirmed = setupPromoConfirmedHoursAgo.map { now.addingTimeInterval(-Double($0) * 60 * 60) }
        return SyncPromoManager(syncService: syncService,
                                featureFlagger: createFeatureFlagger(withFeatureFlagsEnabled: featureFlags),
                                storage: anotherDeviceStorage,
                                pixelFiring: nil,
                                installDateProvider: { installDate },
                                currentDateProvider: { now })
    }

    private func makeManager(featureFlags: [FeatureFlag], installedDaysAgo: Int?) -> SyncPromoManager {
        let now = Date()
        let installDate = installedDaysAgo.flatMap { Calendar.current.date(byAdding: .day, value: -$0, to: now) }
        return SyncPromoManager(syncService: syncService,
                                featureFlagger: createFeatureFlagger(withFeatureFlagsEnabled: featureFlags),
                                installDateProvider: { installDate },
                                currentDateProvider: { now })
    }

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

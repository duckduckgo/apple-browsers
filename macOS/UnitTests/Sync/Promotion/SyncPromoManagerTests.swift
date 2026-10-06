//
//  SyncPromoManagerTests.swift
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
import PrivacyConfigTestsUtils
@testable import BrowserServicesKit
@testable import DDGSync
@testable import DuckDuckGo_Privacy_Browser

final class SyncPromoManagerTests: XCTestCase {

    var syncService: MockDDGSyncing!
    var privacyConfigurationManager: MockPrivacyConfigurationManager! = MockPrivacyConfigurationManager()
    var config: MockPrivacyConfiguration! = MockPrivacyConfiguration()
    var featureFlagger: MockFeatureFlagger!
    var contentCount = 1
    var isDuckDuckGoPasswordManager = true
    var contentCountCallCount = 0

    override func setUpWithError() throws {
        try super.setUpWithError()

        UserDefaultsWrapper<Any>.clearAll()

        privacyConfigurationManager.privacyConfig = config
        syncService = MockDDGSyncing(authState: .inactive, scheduler: CapturingScheduler(), isSyncInProgress: false)
        featureFlagger = MockFeatureFlagger()
        featureFlagger.enabledFeatureFlags = [.promoQueueSyncSetupBookmarksPromo, .promoQueueSyncSetupAutofillPromo]
        contentCount = 1
        isDuckDuckGoPasswordManager = true
        contentCountCallCount = 0
    }

    @MainActor
    override func tearDown() {
        UserDefaultsWrapper<Any>.clearAll()
        syncService = nil
        config = nil
        privacyConfigurationManager = nil
        featureFlagger = nil
    }

    func testWhenAllConditionsMetThenShouldPresentPromoForBookmarks() {
        config.isSubfeatureEnabledCheck = { _, _ in
            return true
        }
        syncService.authState = .inactive

        let syncPromoManager = SyncPromoManager(syncService: syncService, privacyConfigurationManager: privacyConfigurationManager)
        syncPromoManager.resetPromos()

        XCTAssertTrue(syncPromoManager.shouldPresentPromoFor(.bookmarks))
    }

    func testWhenSyncPromotionBookmarksFeatureFlagDisabledThenShouldNotPresentPromoForBookmarks() {
        config.isSubfeatureEnabledCheck = { subfeature, _ in
            if subfeature.rawValue == SyncSubfeature.level0ShowSync.rawValue {
                return true
            }
            return false
        }
        syncService.authState = .inactive

        let syncPromoManager = SyncPromoManager(syncService: syncService, privacyConfigurationManager: privacyConfigurationManager)
        syncPromoManager.resetPromos()

        XCTAssertFalse(syncPromoManager.shouldPresentPromoFor(.bookmarks))
    }

    func testWhenSyncFeatureFlagDisabledThenShouldNotPresentPromoForBookmarks() {
        config.isSubfeatureEnabledCheck = { subfeature, _ in
            if subfeature.rawValue == SyncPromotionSubfeature.bookmarks.rawValue {
                return true
            }
            return false
        }
        syncService.authState = .inactive

        let syncPromoManager = SyncPromoManager(syncService: syncService, privacyConfigurationManager: privacyConfigurationManager)
        syncPromoManager.resetPromos()

        XCTAssertFalse(syncPromoManager.shouldPresentPromoFor(.bookmarks))
    }

    func testWhenSyncServiceAuthStateActiveThenShouldNotPresentPromoForBookmarks() {
        config.isSubfeatureEnabledCheck = { _, _ in
            return true
        }
        syncService.authState = .active

        let syncPromoManager = SyncPromoManager(syncService: syncService, privacyConfigurationManager: privacyConfigurationManager)
        syncPromoManager.resetPromos()

        XCTAssertFalse(syncPromoManager.shouldPresentPromoFor(.bookmarks))
    }

    func testWhenSyncPromoBookmarksDismissedThenShouldNotPresentPromoForBookmarks() {
        config.isSubfeatureEnabledCheck = { _, _ in
            return true
        }
        syncService.authState = .inactive

        let syncPromoManager = SyncPromoManager(syncService: syncService, privacyConfigurationManager: privacyConfigurationManager)
        syncPromoManager.resetPromos()
        syncPromoManager.dismissPromoFor(.bookmarks)

        XCTAssertFalse(syncPromoManager.shouldPresentPromoFor(.bookmarks))
    }

    func testWhenAllConditionsMetThenShouldPresentPromoForPasswords() {
        config.isSubfeatureEnabledCheck = { _, _ in
            return true
        }
        syncService.authState = .inactive

        let syncPromoManager = SyncPromoManager(syncService: syncService, privacyConfigurationManager: privacyConfigurationManager)
        syncPromoManager.resetPromos()

        XCTAssertTrue(syncPromoManager.shouldPresentPromoFor(.passwords))
    }

    func testWhenSyncPromotionPasswordsFeatureFlagDisabledThenShouldNotPresentPromoForPasswords() {
        config.isSubfeatureEnabledCheck = { subfeature, _ in
            if subfeature.rawValue == SyncPromotionSubfeature.passwords.rawValue {
                return false
            }
            return true
        }
        syncService.authState = .inactive

        let syncPromoManager = SyncPromoManager(syncService: syncService, privacyConfigurationManager: privacyConfigurationManager)
        syncPromoManager.resetPromos()

        XCTAssertFalse(syncPromoManager.shouldPresentPromoFor(.passwords))
    }

    func testWhenSyncFeatureFlagDisabledThenShouldNotPresentPromoForPasswords() {
        config.isSubfeatureEnabledCheck = { subfeature, _ in
            if subfeature.rawValue == SyncSubfeature.level0ShowSync.rawValue {
                return false
            }
            return true
        }
        syncService.authState = .inactive

        let syncPromoManager = SyncPromoManager(syncService: syncService, privacyConfigurationManager: privacyConfigurationManager)
        syncPromoManager.resetPromos()

        XCTAssertFalse(syncPromoManager.shouldPresentPromoFor(.passwords))
    }

    func testWhenSyncServiceAuthStateActiveThenShouldNotPresentPromoForPasswords() {
        config.isSubfeatureEnabledCheck = { _, _ in
            return true
        }
        syncService.authState = .active

        let syncPromoManager = SyncPromoManager(syncService: syncService, privacyConfigurationManager: privacyConfigurationManager)
        syncPromoManager.resetPromos()

        XCTAssertFalse(syncPromoManager.shouldPresentPromoFor(.passwords))
    }

    func testWhenSyncPromoPasswordsDismissedThenShouldNotPresentPromoForPasswords() {
        config.isSubfeatureEnabledCheck = { _, _ in
            return true
        }
        syncService.authState = .inactive

        let syncPromoManager = SyncPromoManager(syncService: syncService, privacyConfigurationManager: privacyConfigurationManager)
        syncPromoManager.resetPromos()
        syncPromoManager.dismissPromoFor(.passwords)

        XCTAssertFalse(syncPromoManager.shouldPresentPromoFor(.passwords))
    }

    // MARK: - Promo queue eligibility

    /// Refreshes eligibility once, as `PromoService` does before reading it.
    private func makePromoManager(_ content: SyncPromoContent, hasSyncService: Bool = true) -> SyncPromoManager {
        let promoManager = SyncPromoManager(
            content: content,
            featureFlagger: featureFlagger,
            privacyConfigurationManager: privacyConfigurationManager,
            syncService: hasSyncService ? syncService : nil,
            contentCountProvider: { [unowned self] in
                contentCountCallCount += 1
                return contentCount
            },
            isDuckDuckGoPasswordManager: { [unowned self] in isDuckDuckGoPasswordManager }
        )
        promoManager.refreshEligibility()
        return promoManager
    }

    private func enableAllSubfeatures(except disabled: [any PrivacySubfeature] = []) {
        config.isSubfeatureEnabledCheck = { subfeature, _ in
            !disabled.contains { $0.parent == subfeature.parent && $0.rawValue == subfeature.rawValue }
        }
    }

    private func waitForEligibility(_ sut: SyncPromoManager, toBecome value: Bool) {
        let eligibilityExpectation = expectation(description: "eligibility is \(value)")
        let cancellable = sut.isEligiblePublisher
            .first(where: { $0 == value })
            .sink { _ in eligibilityExpectation.fulfill() }
        wait(for: [eligibilityExpectation], timeout: 1)
        cancellable.cancel()
    }

    func testWhenCreatedThenContentIsNotCountedUntilEligibilityIsRefreshed() {
        enableAllSubfeatures()

        let sut = SyncPromoManager(
            content: .autofill,
            featureFlagger: featureFlagger,
            privacyConfigurationManager: privacyConfigurationManager,
            syncService: syncService,
            contentCountProvider: { [unowned self] in
                contentCountCallCount += 1
                return contentCount
            },
            isDuckDuckGoPasswordManager: { true }
        )

        XCTAssertFalse(sut.isEligible)
        XCTAssertEqual(contentCountCallCount, 0)

        sut.refreshEligibility()

        XCTAssertTrue(sut.isEligible)
        XCTAssertEqual(contentCountCallCount, 1)
    }

    func testWhenAllConditionsMetThenBothPromosAreEligible() {
        enableAllSubfeatures()

        XCTAssertTrue(makePromoManager(.bookmarks).isEligible)
        XCTAssertTrue(makePromoManager(.autofill).isEligible)
    }

    func testWhenPromoFlagIsOffThenOnlyThatPromoIsNotEligible() {
        enableAllSubfeatures()
        featureFlagger.enabledFeatureFlags = [.promoQueueSyncSetupAutofillPromo]

        XCTAssertFalse(makePromoManager(.bookmarks).isEligible)
        XCTAssertTrue(makePromoManager(.autofill).isEligible)

        featureFlagger.enabledFeatureFlags = [.promoQueueSyncSetupBookmarksPromo]

        XCTAssertTrue(makePromoManager(.bookmarks).isEligible)
        XCTAssertFalse(makePromoManager(.autofill).isEligible)
    }

    func testWhenPromotionSubfeatureIsDisabledThenOnlyThatPromoIsNotEligible() {
        enableAllSubfeatures(except: [SyncPromotionSubfeature.bookmarks])

        XCTAssertFalse(makePromoManager(.bookmarks).isEligible)
        XCTAssertTrue(makePromoManager(.autofill).isEligible)

        enableAllSubfeatures(except: [SyncPromotionSubfeature.passwords])

        XCTAssertTrue(makePromoManager(.bookmarks).isEligible)
        XCTAssertFalse(makePromoManager(.autofill).isEligible)
    }

    func testWhenSyncIsNotOfferedThenNeitherPromoIsEligible() {
        enableAllSubfeatures(except: [SyncSubfeature.level0ShowSync])

        XCTAssertFalse(makePromoManager(.bookmarks).isEligible)
        XCTAssertFalse(makePromoManager(.autofill).isEligible)

        enableAllSubfeatures()

        XCTAssertFalse(makePromoManager(.bookmarks, hasSyncService: false).isEligible)
        XCTAssertFalse(makePromoManager(.autofill, hasSyncService: false).isEligible)
    }

    func testWhenSyncIsActiveThenNeitherPromoIsEligible() {
        enableAllSubfeatures()
        syncService.authState = .active

        XCTAssertFalse(makePromoManager(.bookmarks).isEligible)
        XCTAssertFalse(makePromoManager(.autofill).isEligible)
    }

    func testWhenUserHasNoContentThenNeitherPromoIsEligible() {
        enableAllSubfeatures()
        contentCount = 0

        XCTAssertFalse(makePromoManager(.bookmarks).isEligible)
        XCTAssertFalse(makePromoManager(.autofill).isEligible)
    }

    func testWhenDuckDuckGoIsNotThePasswordManagerThenOnlyAutofillPromoIsNotEligible() {
        enableAllSubfeatures()
        isDuckDuckGoPasswordManager = false

        XCTAssertTrue(makePromoManager(.bookmarks).isEligible)
        XCTAssertFalse(makePromoManager(.autofill).isEligible)
    }

    func testWhenContentIsAddedThenRefreshEligibilityMakesPromoEligible() {
        enableAllSubfeatures()
        contentCount = 0
        let sut = makePromoManager(.bookmarks)
        XCTAssertFalse(sut.isEligible)

        contentCount = 1
        sut.refreshEligibility()

        XCTAssertTrue(sut.isEligible)
    }

    func testWhenPromoFlagTurnsOffThenPromoBecomesNotEligible() {
        enableAllSubfeatures()
        let sut = makePromoManager(.bookmarks)
        XCTAssertTrue(sut.isEligible)

        featureFlagger.enabledFeatureFlags = []
        featureFlagger.triggerUpdate()

        waitForEligibility(sut, toBecome: false)
    }

    func testWhenPrivacyConfigurationUpdatesThenEligibilityIsRecomputed() {
        enableAllSubfeatures()
        let sut = makePromoManager(.autofill)
        XCTAssertTrue(sut.isEligible)

        enableAllSubfeatures(except: [SyncPromotionSubfeature.passwords])
        privacyConfigurationManager.updatesSubject.send()

        waitForEligibility(sut, toBecome: false)
    }

    func testWhenSyncTurnsOnThenPromoBecomesNotEligible() {
        enableAllSubfeatures()
        let sut = makePromoManager(.bookmarks)
        XCTAssertTrue(sut.isEligible)

        syncService.authState = .active

        waitForEligibility(sut, toBecome: false)
    }

    // MARK: - Trigger wiring

    func testWhenSurfaceOpenedNotificationPostedThenPromoTriggerFires() {
        let notificationTriggers: [(Notification.Name, PromoTrigger)] = [
            (.bookmarksPanelOpened, .bookmarksPanelOpened),
            (.bookmarksManagerOpened, .bookmarksManagerOpened),
            (.passwordsPanelOpened, .passwordsPanelOpened),
            (.autofillSettingsOpened, .autofillSettingsOpened)
        ]

        for (name, trigger) in notificationTriggers {
            let triggerExpectation = expectation(description: "\(trigger) fired")
            let cancellable = PromoTrigger.triggerPublisher
                .filter { $0 == trigger }
                .sink { _ in triggerExpectation.fulfill() }

            NotificationCenter.default.post(name: name, object: nil)

            wait(for: [triggerExpectation], timeout: 1)
            cancellable.cancel()
        }
    }
}

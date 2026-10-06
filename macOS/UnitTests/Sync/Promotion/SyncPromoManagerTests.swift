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

import Combine
import XCTest
@_spi(Testing) import Persistence
import PrivacyConfig
import PrivacyConfigTestsUtils
@testable import BrowserServicesKit
@testable import DDGSync
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class SyncPromoManagerTests: XCTestCase {

    var syncService: MockDDGSyncing!
    var privacyConfigurationManager: MockPrivacyConfigurationManager! = MockPrivacyConfigurationManager()
    var config: MockPrivacyConfiguration! = MockPrivacyConfiguration()
    var featureFlagger: MockFeatureFlagger!
    var contentCount = 1
    var isDuckDuckGoPasswordManager = true
    var contentCountCallCount = 0
    var legacyStorage: KeyedStorage<SyncPromoLegacySettings>!
    var openSyncSettingsCallCount = 0
    var recordedResults: [PromoResult] = []

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
        legacyStorage = KeyedStorage(storage: InMemoryKeyValueStore())
        openSyncSettingsCallCount = 0
        recordedResults = []
    }

    @MainActor
    override func tearDown() {
        UserDefaultsWrapper<Any>.clearAll()
        syncService = nil
        config = nil
        privacyConfigurationManager = nil
        featureFlagger = nil
        legacyStorage = nil
        recordedResults = []
        customAssert = nil
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
            isDuckDuckGoPasswordManager: { [unowned self] in isDuckDuckGoPasswordManager },
            legacyStorage: legacyStorage,
            openSyncSettings: { [unowned self] in openSyncSettingsCallCount += 1 },
            recordResult: { [unowned self] in recordedResults.append($1) }
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
            isDuckDuckGoPasswordManager: { true },
            legacyStorage: legacyStorage,
            openSyncSettings: { },
            recordResult: { _, _ in }
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

    // MARK: - Promo queue display

    /// Starts `show()` and returns once the promo is active, so the caller can resolve it.
    private func startShowing(_ sut: SyncPromoManager, force: Bool = false) async -> Task<PromoResult, Never> {
        let activeExpectation = expectation(description: "promo active")
        let cancellable = sut.isPromoActivePublisher
            .first(where: { $0 })
            .sink { _ in activeExpectation.fulfill() }
        let task = Task { await sut.show(history: PromoHistoryRecord(id: "sync-promo"), force: force) }
        await fulfillment(of: [activeExpectation], timeout: 1)
        cancellable.cancel()
        return task
    }

    private func eligibility(of sut: SyncPromoManager, becomes value: Bool) async {
        let eligibilityExpectation = expectation(description: "eligibility is \(value)")
        let cancellable = sut.isEligiblePublisher
            .first(where: { $0 == value })
            .sink { _ in eligibilityExpectation.fulfill() }
        await fulfillment(of: [eligibilityExpectation], timeout: 1)
        cancellable.cancel()
    }

    func testWhenLegacyPromoWasDismissedThenShowRetiresThatPromo() async {
        enableAllSubfeatures()
        legacyStorage.bookmarksDismissedDate = Date()

        let bookmarksResult = await makePromoManager(.bookmarks).show(history: PromoHistoryRecord(id: "sync-promo"), force: false)
        XCTAssertEqual(bookmarksResult, .retired)

        legacyStorage.bookmarksDismissedDate = nil
        legacyStorage.passwordsDismissedDate = Date()

        let autofillResult = await makePromoManager(.autofill).show(history: PromoHistoryRecord(id: "sync-promo"), force: false)
        XCTAssertEqual(autofillResult, .retired)
    }

    func testWhenLegacyPromoWasDismissedThenForceShowBypassesRetirement() async {
        enableAllSubfeatures()
        legacyStorage.bookmarksDismissedDate = Date()
        let sut = makePromoManager(.bookmarks)

        let showTask = await startShowing(sut, force: true)

        XCTAssertTrue(sut.isPromoActive)
        sut.hide()
        let result = await showTask.value
        XCTAssertEqual(result, .noChange)
    }

    func testWhenPromoIsDismissedThenShowReturnsIgnored() async {
        enableAllSubfeatures()
        let sut = makePromoManager(.bookmarks)
        let showTask = await startShowing(sut)

        sut.promoDismissed()

        let result = await showTask.value
        XCTAssertEqual(result, .ignored())
        XCTAssertFalse(sut.isPromoActive)
    }

    private func recordedResults(become expected: [PromoResult]) async {
        let deadline = Date().addingTimeInterval(1)
        while recordedResults != expected, Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(recordedResults, expected)
    }

    func testWhenCTATappedAndSyncTurnsOnThenActionedIsRecorded() async {
        enableAllSubfeatures()
        let sut = makePromoManager(.autofill)
        _ = await startShowing(sut)

        sut.goToSyncSettings(for: .passwords)
        XCTAssertEqual(openSyncSettingsCallCount, 1)
        XCTAssertTrue(sut.isPromoActive, "Tapping the CTA alone doesn't resolve the promo")
        syncService.authState = .active

        await recordedResults(become: [.actioned])
        await eligibility(of: sut, becomes: false)
    }

    func testWhenCTATappedAndSyncIsSetUpWithAnExistingAccountThenActionedIsRecorded() async {
        enableAllSubfeatures()
        let sut = makePromoManager(.bookmarks)
        _ = await startShowing(sut)

        sut.goToSyncSettings(for: .bookmarks)
        syncService.authState = .addingNewDevice

        await recordedResults(become: [.actioned])
    }

    func testWhenPromoIsHiddenBecauseSyncTurnedOnAfterCTATapThenActionedIsStillRecorded() async {
        enableAllSubfeatures()
        let sut = makePromoManager(.bookmarks)
        let showTask = await startShowing(sut)
        sut.goToSyncSettings(for: .bookmarks)

        syncService.authState = .active
        sut.hide()

        let result = await showTask.value
        XCTAssertEqual(result, .noChange)
        await recordedResults(become: [.actioned])
    }

    func testWhenSyncTurnsOnWithoutTappingTheCTAThenNothingIsRecorded() async {
        enableAllSubfeatures()
        let sut = makePromoManager(.bookmarks)
        let showTask = await startShowing(sut)

        syncService.authState = .active

        await eligibility(of: sut, becomes: false)
        XCTAssertTrue(sut.isPromoActive, "Only the queue retracts the promo when eligibility is lost")
        sut.hide()
        let result = await showTask.value
        XCTAssertEqual(result, .noChange)
        XCTAssertEqual(recordedResults, [])
    }

    func testWhenPromoWasHiddenAfterCTATapThenSyncTurningOnLaterIsNotActioned() async {
        enableAllSubfeatures()
        let sut = makePromoManager(.bookmarks)
        let showTask = await startShowing(sut)
        sut.goToSyncSettings(for: .bookmarks)
        sut.hide()
        _ = await showTask.value

        syncService.authState = .active

        await eligibility(of: sut, becomes: false)
        XCTAssertEqual(recordedResults, [])
    }

    func testWhenCTAWasTappedInAnEarlierShowingThenSyncTurningOnDoesNotActionTheNextOne() async {
        enableAllSubfeatures()
        let sut = makePromoManager(.bookmarks)
        let firstShowTask = await startShowing(sut)
        sut.goToSyncSettings(for: .bookmarks)
        sut.hide()
        _ = await firstShowTask.value

        let secondShowTask = await startShowing(sut)
        syncService.authState = .active

        await eligibility(of: sut, becomes: false)
        sut.hide()
        let result = await secondShowTask.value
        XCTAssertEqual(result, .noChange)
        XCTAssertEqual(recordedResults, [])
    }

    func testWhenShownAgainBeforeBeingHiddenThenThePreviousShowingReturnsNoChange() async {
        enableAllSubfeatures()
        let sut = makePromoManager(.bookmarks)
        let firstShowTask = await startShowing(sut)

        let secondShowTask = Task { await sut.show(history: PromoHistoryRecord(id: "sync-promo"), force: false) }

        let firstResult = await firstShowTask.value
        XCTAssertEqual(firstResult, .noChange)
        sut.promoDismissed()
        let secondResult = await secondShowTask.value
        XCTAssertEqual(secondResult, .ignored())
    }

    func testWhenSyncTurnsOnAfterCTATapThenTheQueueRecordsActioned() async throws {
        enableAllSubfeatures()
        let historyStore = MockPromoHistoryStore()
        let stateQueue = DispatchQueue(label: "test.promoService")
        let triggerSubject = PassthroughSubject<PromoTrigger, Never>()
        let promoID = SyncPromoContent.bookmarks.promoID
        var promoService: PromoService?
        let sut = SyncPromoManager(
            content: .bookmarks,
            featureFlagger: featureFlagger,
            privacyConfigurationManager: privacyConfigurationManager,
            syncService: syncService,
            contentCountProvider: { 1 },
            isDuckDuckGoPasswordManager: { true },
            legacyStorage: legacyStorage,
            openSyncSettings: { },
            recordResult: { promoService?.dismiss(promoId: $0, result: $1) }
        )
        promoService = PromoService(
            promos: [PromoTestHelpers.makePromo(id: promoID, triggers: [.bookmarksPanelOpened], promoType: PromoType(.inlineTip), delegate: sut)],
            historyStore: historyStore,
            triggerPublisher: triggerSubject.eraseToAnyPublisher(),
            initialExternalActivation: false,
            isOnboardingCompletedProvider: { true },
            stateQueue: stateQueue,
            evaluationDeferralWindow: 0,
            registrationFallbackTimeout: 0,
            externalActivationWindow: 0,
            dateProvider: Date.init
        )
        let service = try XCTUnwrap(promoService)
        service.applicationDidBecomeActive()
        triggerSubject.send(.bookmarksPanelOpened)
        let activeExpectation = expectation(description: "promo active")
        let cancellable = sut.isPromoActivePublisher.first(where: { $0 }).sink { _ in activeExpectation.fulfill() }
        await fulfillment(of: [activeExpectation], timeout: 5)
        cancellable.cancel()

        sut.goToSyncSettings(for: .bookmarks)
        syncService.authState = .active

        let deadline = Date().addingTimeInterval(5)
        var record = stateQueue.sync { historyStore.record(for: promoID) }
        while !record.actioned, Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
            record = stateQueue.sync { historyStore.record(for: promoID) }
        }
        XCTAssertTrue(record.actioned)
        XCTAssertEqual(record.nextEligibleDate, .distantFuture)
    }

    func testWhenPasswordManagerChangesWhileShowingThenPromoStaysEligibleUntilHidden() async {
        enableAllSubfeatures()
        let sut = makePromoManager(.autofill)
        let showTask = await startShowing(sut)

        isDuckDuckGoPasswordManager = false
        sut.refreshEligibility()
        XCTAssertTrue(sut.isEligible)

        sut.hide()
        _ = await showTask.value
        sut.refreshEligibility()
        XCTAssertFalse(sut.isEligible)
    }

    func testWhenHiddenBeforeResolutionThenShowReturnsNoChange() async {
        enableAllSubfeatures()
        let sut = makePromoManager(.bookmarks)
        let showTask = await startShowing(sut)

        sut.hide()
        sut.hide()

        let result = await showTask.value
        XCTAssertEqual(result, .noChange)
        XCTAssertFalse(sut.isPromoActive)
    }

    func testWhenHiddenBeforeShowingThenNothingHappens() {
        enableAllSubfeatures()
        let sut = makePromoManager(.bookmarks)

        sut.hide()

        XCTAssertFalse(sut.isPromoActive)
    }

    func testIsPromoActivePublisherTogglesWhenPromoIsShownAndDismissed() async {
        enableAllSubfeatures()
        let sut = makePromoManager(.bookmarks)
        var received: [Bool] = []
        let inactiveAgainExpectation = expectation(description: "promo inactive again")
        let cancellable = sut.isPromoActivePublisher.sink { isActive in
            received.append(isActive)
            if received == [false, true, false] {
                inactiveAgainExpectation.fulfill()
            }
        }

        let showTask = await startShowing(sut)
        sut.promoDismissed()
        _ = await showTask.value

        await fulfillment(of: [inactiveAgainExpectation], timeout: 1)
        cancellable.cancel()
    }

    func testWhenGoToSyncSettingsReceivesATouchpointOfAnotherContentThenItAsserts() {
        enableAllSubfeatures()
        let sut = makePromoManager(.bookmarks)
        var failedAssertions = 0
        customAssert = { condition, _, _, _ in
            if !condition() { failedAssertions += 1 }
        }

        sut.goToSyncSettings(for: .passwords)

        XCTAssertEqual(failedAssertions, 1)
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

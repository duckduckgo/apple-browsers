//
//  NewTabPageMessagesModelTests.swift
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

import Core
import RemoteMessaging
import XCTest
import DDGSync

@testable import DuckDuckGo

@MainActor
final class NewTabPageMessagesModelTests: XCTestCase {
 
    private var messagesConfiguration: HomePageMessagesConfigurationMock!
    private var notificationCenter: NotificationCenter!

    private var segueToAIChatSettingsCallCount = 0
    private var segueToSettingsCallCount = 0
    private var segueToSettingsGeneralCallCount = 0
    private var segueToFeedbackCallCount = 0
    private var segueToSyncSettingsCallCount = 0
    private var segueToSettingsAppearanceCallCount = 0
    private var segueToPIRCallCount = 0

    override func setUpWithError() throws {
        messagesConfiguration = HomePageMessagesConfigurationMock(homeMessages: [])
        notificationCenter = NotificationCenter()
        segueToAIChatSettingsCallCount = 0
        segueToSettingsCallCount = 0
        segueToSettingsGeneralCallCount = 0
        segueToFeedbackCallCount = 0
        segueToSyncSettingsCallCount = 0
        segueToSettingsAppearanceCallCount = 0
        segueToPIRCallCount = 0
    }

    override func tearDownWithError() throws {
        PixelFiringMock.tearDown()
    }

    func testPromoQueuePixelReporterMapsBothEventsWithoutAdditionalParameters() {
        let sut = PromoQueuePixelReporter(dailyPixelFiring: PixelFiringMock.self)

        sut.fireModalAdmissionBlockedByRemoteMessage()

        XCTAssertEqual(
            PixelFiringMock.lastDailyPixelInfo?.pixelName,
            Pixel.Event.promoQueueModalAdmissionBlockedByRemoteMessage.name
        )
        XCTAssertEqual(PixelFiringMock.lastDailyPixelInfo?.params, [:])
        XCTAssertNil(PixelFiringMock.lastDailyPixelInfo?.error)

        sut.fireRemoteMessageAdmissionBlockedByModal()

        XCTAssertEqual(
            PixelFiringMock.lastDailyPixelInfo?.pixelName,
            Pixel.Event.promoQueueRemoteMessageAdmissionBlockedByModal.name
        )
        XCTAssertEqual(PixelFiringMock.lastDailyPixelInfo?.params, [:])
        XCTAssertNil(PixelFiringMock.lastDailyPixelInfo?.error)
    }

    func testUpdatesOnNotification() {
        let sut = createSUT()

        sut.load()

        XCTAssertTrue(sut.homeMessageViewModels.isEmpty)

        messagesConfiguration.homeMessages = [.placeholder]

        notificationCenter.post(name: RemoteMessagingStore.Notifications.remoteMessagesDidChange,
                                object: nil)

        XCTAssertEqual(sut.homeMessageViewModels.count, 1)
    }

    func testLoadIsIdempotentAndTearDownRemovesObserverAndRetryRegistration() {
        let promoCoordinator = ArbitratingNewTabPagePromoCoordinatorMock()
        let sut = createSUT(promoCoordinator: promoCoordinator)

        sut.load()
        sut.load()

        XCTAssertEqual(messagesConfiguration.refreshCallCount, 1)
        XCTAssertEqual(promoCoordinator.registrationCount, 1)

        notificationCenter.post(
            name: RemoteMessagingStore.Notifications.remoteMessagesDidChange,
            object: nil
        )
        XCTAssertEqual(messagesConfiguration.refreshCallCount, 2)

        sut.tearDown()
        notificationCenter.post(
            name: RemoteMessagingStore.Notifications.remoteMessagesDidChange,
            object: nil
        )

        XCTAssertEqual(messagesConfiguration.refreshCallCount, 2)
        XCTAssertEqual(promoCoordinator.deregistrationCount, 1)
        XCTAssertNil(promoCoordinator.retryTarget)
    }

    func testFeatureOffRecordsLegacyAppearanceEagerlyThenAgainWhenVisible() throws {
        let promoCoordinator = ArbitratingNewTabPagePromoCoordinatorMock(featureState: .disabled)
        let message = HomeMessage.mockRemote(id: "message-a", withType: .small(titleText: "Title", descriptionText: "Body"))
        messagesConfiguration.homeMessages = [message]
        let sut = createSUT(promoCoordinator: promoCoordinator)

        sut.load()

        let viewModel = try XCTUnwrap(sut.homeMessageViewModels.first)
        XCTAssertEqual(messagesConfiguration.appearanceCallCount, 1)
        XCTAssertEqual(messagesConfiguration.lastAppearedHomeMessage, message)
        XCTAssertEqual(promoCoordinator.publicAdmissionCallCount, 0)

        viewModel.onDidAppear()

        XCTAssertEqual(messagesConfiguration.appearanceCallCount, 2)
        XCTAssertEqual(messagesConfiguration.lastAppearedHomeMessage, message)
        XCTAssertEqual(promoCoordinator.publicAdmissionCallCount, 0)
    }

    func testFeatureOffMapsEveryMessageDirectlyInInputOrder() {
        let promoCoordinator = ArbitratingNewTabPagePromoCoordinatorMock(featureState: .disabled)
        let message = HomeMessage.mockRemote(id: "message-a", withType: .small(titleText: "Title", descriptionText: "Body"))
        messagesConfiguration.homeMessages = [.placeholder, message]
        let sut = createSUT(promoCoordinator: promoCoordinator)

        sut.load()

        // Collected rather than asserted item by item so the count also pins that *no* item is a coordination gate: a
        // gated remote message would publish a `remote-message-gate-` mount and drop out of this mapping.
        let directMessageIDs = sut.homeMessageRenderItems.compactMap { item -> String? in
            guard case .message(let viewModel) = item.content else {
                return nil
            }
            return viewModel.messageId
        }

        XCTAssertEqual(sut.homeMessageRenderItems.count, 2)
        XCTAssertEqual(sut.homeMessageRenderItems.map(\.id), ["local-message-0", "remote-message-message-a"])
        XCTAssertEqual(directMessageIDs, ["", "message-a"])
        XCTAssertEqual(sut.homeMessageViewModels.map(\.messageId), ["", "message-a"])
        XCTAssertEqual(messagesConfiguration.appearanceCallCount, 1)
        XCTAssertEqual(messagesConfiguration.lastAppearedHomeMessage, message)
    }

    func testFeatureOnRetainsBlockedCandidateWithoutPublishingOrRecordingRemoteCard() throws {
        let promoCoordinator = ArbitratingNewTabPagePromoCoordinatorMock(featureState: .enabled)
        promoCoordinator.acquireModalLease()
        messagesConfiguration.homeMessages = [.mockRemote(id: "message-a", withType: .small(titleText: "Title", descriptionText: "Body"))]
        let sut = createRenderableSUT(promoCoordinator: promoCoordinator)

        try appearRemoteMessageGate(in: sut, expectedMessageID: "message-a")

        XCTAssertTrue(sut.homeMessageViewModels.isEmpty)
        XCTAssertNil(try remoteRenderSession(in: sut))
        XCTAssertEqual(promoCoordinator.arbiter.snapshot.visiblePromoCount, 0)
        XCTAssertNil(messagesConfiguration.lastAppearedHomeMessage)
    }

    func testEveryRenderReadyRemoteMessageAdmissionBlockedByModalIsReportedRegardlessOfRMFMetricsSetting() throws {
        let promoCoordinator = ArbitratingNewTabPagePromoCoordinatorMock(featureState: .enabled)
        promoCoordinator.acquireModalLease()
        let promoQueuePixelReporter = MockPromoQueuePixelReporter()
        messagesConfiguration.homeMessages = [
            .mockRemote(
                id: "message-a",
                withType: .small(titleText: "Title", descriptionText: "Body"),
                isMetricsEnabled: false
            ),
        ]
        let sut = createRenderableSUT(
            promoCoordinator: promoCoordinator,
            promoQueuePixelReporter: promoQueuePixelReporter
        )

        XCTAssertEqual(promoQueuePixelReporter.remoteMessageAdmissionBlockedByModalCount, 0)
        try appearRemoteMessageGate(in: sut, expectedMessageID: "message-a")
        sut.retryVisiblePromoAdmission(using: promoCoordinator.admitVisiblePromo)
        sut.retryVisiblePromoAdmission(using: promoCoordinator.admitVisiblePromo)

        XCTAssertEqual(promoQueuePixelReporter.remoteMessageAdmissionBlockedByModalCount, 3)
        XCTAssertEqual(promoQueuePixelReporter.modalAdmissionBlockedByRemoteMessageCount, 0)
    }

    func testOccupiedSurfaceDenialIsNotReportedAsModalBlockingRemoteMessage() throws {
        let promoCoordinator = ArbitratingNewTabPagePromoCoordinatorMock(featureState: .enabled)
        let promoQueuePixelReporter = MockPromoQueuePixelReporter()
        messagesConfiguration.homeMessages = [
            .mockRemote(
                id: "message-a",
                withType: .small(titleText: "Title", descriptionText: "Body")
            ),
        ]
        let sut = createRenderableSUT(
            promoCoordinator: promoCoordinator,
            promoQueuePixelReporter: promoQueuePixelReporter
        )
        let occupiedIdentity = VisiblePromoIdentity(
            surfaceID: sut.surfaceID,
            promoType: .remoteMessage,
            promoID: "existing-message"
        )
        guard case .acquired(let occupiedLease) = promoCoordinator.arbiter.acquireVisiblePromoLease(for: occupiedIdentity) else {
            XCTFail("Expected visible promo lease acquisition")
            return
        }

        try appearRemoteMessageGate(in: sut, expectedMessageID: "message-a")

        XCTAssertEqual(promoQueuePixelReporter.remoteMessageAdmissionBlockedByModalCount, 0)
        XCTAssertEqual(promoQueuePixelReporter.modalAdmissionBlockedByRemoteMessageCount, 0)
        withExtendedLifetime(occupiedLease) {}
    }

    func testFeatureOffLegacyRemoteMessageDoesNotReportPromoQueueCollision() {
        let promoCoordinator = ArbitratingNewTabPagePromoCoordinatorMock()
        let promoQueuePixelReporter = MockPromoQueuePixelReporter()
        messagesConfiguration.homeMessages = [
            .mockRemote(
                id: "message-a",
                withType: .small(titleText: "Title", descriptionText: "Body")
            ),
        ]

        let sut = createRenderableSUT(
            promoCoordinator: promoCoordinator,
            promoQueuePixelReporter: promoQueuePixelReporter
        )

        XCTAssertEqual(sut.homeMessageViewModels.map(\.messageId), ["message-a"])
        XCTAssertEqual(promoQueuePixelReporter.remoteMessageAdmissionBlockedByModalCount, 0)
        XCTAssertEqual(promoQueuePixelReporter.modalAdmissionBlockedByRemoteMessageCount, 0)
    }

    func testFeatureOnConstructsAndPublishesRemoteCardOnlyAfterLeaseAdmission() throws {
        let promoCoordinator = ArbitratingNewTabPagePromoCoordinatorMock(featureState: .enabled)
        messagesConfiguration.homeMessages = [.mockRemote(id: "message-a", withType: .small(titleText: "Title", descriptionText: "Body"))]
        let sut = createRenderableSUT(promoCoordinator: promoCoordinator)

        XCTAssertTrue(sut.homeMessageViewModels.isEmpty)
        XCTAssertNil(try remoteRenderSession(in: sut))

        try appearRemoteMessageGate(in: sut, expectedMessageID: "message-a")

        XCTAssertEqual(sut.homeMessageViewModels.map(\.messageId), ["message-a"])
        XCTAssertNotNil(try remoteRenderSession(in: sut))
        XCTAssertEqual(promoCoordinator.arbiter.snapshot.visiblePromoCount, 1)
        XCTAssertNil(messagesConfiguration.lastAppearedHomeMessage)
    }

    func testAdmittedAppearanceIsRecordedOncePerRenderSession() throws {
        let promoCoordinator = ArbitratingNewTabPagePromoCoordinatorMock(featureState: .enabled)
        let message = HomeMessage.mockRemote(id: "message-a", withType: .small(titleText: "Title", descriptionText: "Body"))
        messagesConfiguration.homeMessages = [message]
        let sut = createRenderableSUT(promoCoordinator: promoCoordinator)
        try appearRemoteMessageGate(in: sut, expectedMessageID: "message-a")
        let session = try XCTUnwrap(try remoteRenderSession(in: sut))

        session.viewModel.onDidAppear()
        session.viewModel.onDidAppear()

        XCTAssertEqual(messagesConfiguration.appearanceCallCount, 1)
        XCTAssertEqual(messagesConfiguration.lastAppearedHomeMessage, message)
    }

    func testTwoNTPAppearancesBeforeShownStorageCompletesHaveOneUniqueWinner() async throws {
        let remoteMessage = RemoteMessageModel(
            id: "message-a",
            surfaces: .newTabPage,
            content: .small(titleText: "Title", descriptionText: "Body"),
            matchingRules: [],
            exclusionRules: [],
            isMetricsEnabled: true
        )
        let shownUpdateStarted = expectation(description: "Shown store update started")
        let shownUpdateCompleted = expectation(description: "Shown store update completed")
        let store = SuspendedShownRemoteMessagingStore(
            scheduledRemoteMessage: remoteMessage,
            onShownUpdateStarted: {
                shownUpdateStarted.fulfill()
            },
            onShownUpdateCompleted: {
                shownUpdateCompleted.fulfill()
            }
        )
        defer {
            store.completePendingShownUpdate()
        }
        let pixelReporter = HomePageMessageShownPixelReporterMock()
        let configuration = HomePageConfiguration(
            remoteMessagingStore: store,
            subscriptionDataReporter: MockSubscriptionDataReporter(),
            isStillOnboarding: { false },
            shownPixelReporter: pixelReporter
        )
        let promoCoordinator = ArbitratingNewTabPagePromoCoordinatorMock(featureState: .enabled)
        let firstNTP = createRenderableSUT(
            homePageMessagesConfiguration: configuration,
            promoCoordinator: promoCoordinator
        )
        let secondNTP = createRenderableSUT(
            homePageMessagesConfiguration: configuration,
            promoCoordinator: promoCoordinator
        )

        XCTAssertNotEqual(firstNTP.surfaceID, secondNTP.surfaceID)
        try appearRemoteMessageGate(in: firstNTP, expectedMessageID: remoteMessage.id)
        try appearRemoteMessageGate(in: secondNTP, expectedMessageID: remoteMessage.id)
        try XCTUnwrap(remoteRenderSession(in: firstNTP)).viewModel.onDidAppear()
        try XCTUnwrap(remoteRenderSession(in: secondNTP)).viewModel.onDidAppear()
        await fulfillment(of: [shownUpdateStarted], timeout: 1)

        XCTAssertEqual(pixelReporter.shownCount, 2)
        XCTAssertEqual(pixelReporter.uniqueShownCount, 1)
        XCTAssertEqual(store.shownUpdateCallCount, 1)
        XCTAssertFalse(store.hasShownRemoteMessage(withID: remoteMessage.id))

        store.completePendingShownUpdate()
        await fulfillment(of: [shownUpdateCompleted], timeout: 1)
        XCTAssertTrue(store.hasShownRemoteMessage(withID: remoteMessage.id))
    }

    func testSameIDRefreshKeepsLeaseRenderSessionAndAppearanceReservation() throws {
        let promoCoordinator = ArbitratingNewTabPagePromoCoordinatorMock(featureState: .enabled)
        messagesConfiguration.homeMessages = [.mockRemote(id: "message-a", withType: .small(titleText: "First", descriptionText: "Body"))]
        let sut = createRenderableSUT(promoCoordinator: promoCoordinator)
        let originalGate = try XCTUnwrap(try remoteMessageGate(in: sut))
        let mountID = UUID()
        sut.remoteMessageGateDidAppear(
            gateID: originalGate.id,
            messageID: originalGate.messageID,
            mountID: mountID
        )
        let originalSession = try XCTUnwrap(try remoteRenderSession(in: sut))
        originalSession.viewModel.onDidAppear()

        messagesConfiguration.homeMessages = [.mockRemote(id: "message-a", withType: .small(titleText: "Updated", descriptionText: "Body"))]
        sut.refresh()
        let refreshedGate = try XCTUnwrap(try remoteMessageGate(in: sut))
        let refreshedSession = try XCTUnwrap(try remoteRenderSession(in: sut))
        refreshedSession.viewModel.onDidAppear()

        XCTAssertEqual(refreshedGate.id, originalGate.id)
        XCTAssertEqual(refreshedSession.id, originalSession.id)
        XCTAssertEqual(refreshedSession.viewModel.title, "Updated")
        XCTAssertEqual(messagesConfiguration.appearanceCallCount, 1)
        XCTAssertEqual(promoCoordinator.arbiter.snapshot.visiblePromoCount, 1)
    }

    func testReplacementMountAppearingBeforeStaleMountDisappearsKeepsCurrentSessionAndLease() throws {
        let promoCoordinator = ArbitratingNewTabPagePromoCoordinatorMock(featureState: .enabled)
        messagesConfiguration.homeMessages = [.mockRemote(id: "message-a", withType: .small(titleText: "Title", descriptionText: "Body"))]
        let sut = createRenderableSUT(promoCoordinator: promoCoordinator)
        let gate = try XCTUnwrap(try remoteMessageGate(in: sut))
        let originalMountID = UUID()
        let replacementMountID = UUID()

        sut.remoteMessageGateDidAppear(
            gateID: gate.id,
            messageID: gate.messageID,
            mountID: originalMountID
        )
        let session = try XCTUnwrap(try remoteRenderSession(in: sut))

        sut.remoteMessageGateDidAppear(
            gateID: gate.id,
            messageID: gate.messageID,
            mountID: replacementMountID
        )
        sut.remoteMessageGateDidDisappear(
            gateID: gate.id,
            messageID: gate.messageID,
            mountID: originalMountID
        )
        sut.remoteMessageDidDisappear(
            renderSessionID: session.id,
            mountID: originalMountID
        )

        XCTAssertEqual(try remoteRenderSession(in: sut)?.id, session.id)
        XCTAssertEqual(promoCoordinator.arbiter.snapshot.visiblePromoCount, 1)
    }

    func testReplacementMountDisappearingBeforeItsGateKeepsOriginalSessionAndLease() throws {
        let promoCoordinator = ArbitratingNewTabPagePromoCoordinatorMock(featureState: .enabled)
        messagesConfiguration.homeMessages = [.mockRemote(id: "message-a", withType: .small(titleText: "Title", descriptionText: "Body"))]
        let sut = createRenderableSUT(promoCoordinator: promoCoordinator)
        let gate = try XCTUnwrap(try remoteMessageGate(in: sut))
        let originalMountID = UUID()
        let replacementMountID = UUID()

        sut.remoteMessageGateDidAppear(
            gateID: gate.id,
            messageID: gate.messageID,
            mountID: originalMountID
        )
        let session = try XCTUnwrap(try remoteRenderSession(in: sut))

        sut.remoteMessageGateDidAppear(
            gateID: gate.id,
            messageID: gate.messageID,
            mountID: replacementMountID
        )
        sut.remoteMessageDidDisappear(
            renderSessionID: session.id,
            mountID: replacementMountID
        )
        sut.remoteMessageGateDidDisappear(
            gateID: gate.id,
            messageID: gate.messageID,
            mountID: replacementMountID
        )

        XCTAssertEqual(try remoteRenderSession(in: sut)?.id, session.id)
        XCTAssertEqual(promoCoordinator.arbiter.snapshot.visiblePromoCount, 1)
    }

    func testWhenRemoteMessageIDChangesThenReplacementAdmitsAfterDeferredRelease() async throws {
        let promoCoordinator = ArbitratingNewTabPagePromoCoordinatorMock(featureState: .enabled)
        messagesConfiguration.homeMessages = [.mockRemote(id: "message-a", withType: .small(titleText: "First", descriptionText: "Body"))]
        let sut = createRenderableSUT(promoCoordinator: promoCoordinator)
        try appearRemoteMessageGate(in: sut, expectedMessageID: "message-a")
        let originalSession = try XCTUnwrap(try remoteRenderSession(in: sut))

        messagesConfiguration.homeMessages = [.mockRemote(id: "message-b", withType: .small(titleText: "Second", descriptionText: "Body"))]
        sut.refresh()
        try appearRemoteMessageGate(in: sut, expectedMessageID: "message-b")

        XCTAssertNil(try remoteRenderSession(in: sut))
        XCTAssertEqual(promoCoordinator.arbiter.snapshot.visiblePromoIdentities.map(\.promoID), ["message-a"])

        await waitForNextMainQueueTurn()
        let replacementSession = try XCTUnwrap(try remoteRenderSession(in: sut))

        XCTAssertNotEqual(replacementSession.id, originalSession.id)
        XCTAssertEqual(promoCoordinator.arbiter.snapshot.visiblePromoIdentities.map(\.promoID), ["message-b"])
    }

    func testRenderableWithdrawalReleasesLeaseOnNextTurnAndReadmitsWhenRenderableAgain() async throws {
        let promoCoordinator = ArbitratingNewTabPagePromoCoordinatorMock(featureState: .enabled)
        messagesConfiguration.homeMessages = [.mockRemote(id: "message-a", withType: .small(titleText: "Title", descriptionText: "Body"))]
        let sut = createRenderableSUT(promoCoordinator: promoCoordinator)
        try appearRemoteMessageGate(in: sut, expectedMessageID: "message-a")

        sut.setSurfaceRenderable(false)

        XCTAssertTrue(sut.homeMessageViewModels.isEmpty)
        XCTAssertEqual(promoCoordinator.arbiter.snapshot.visiblePromoCount, 1)

        await waitForNextMainQueueTurn()
        XCTAssertEqual(promoCoordinator.arbiter.snapshot.visiblePromoCount, 0)

        sut.setSurfaceRenderable(true)

        XCTAssertNotNil(try remoteRenderSession(in: sut))
        XCTAssertEqual(promoCoordinator.arbiter.snapshot.visiblePromoCount, 1)
    }

    func testOwnerTeardownReleasesLeaseOnNextTurn() async throws {
        let promoCoordinator = ArbitratingNewTabPagePromoCoordinatorMock(featureState: .enabled)
        messagesConfiguration.homeMessages = [.mockRemote(id: "message-a", withType: .small(titleText: "Title", descriptionText: "Body"))]
        let sut = createRenderableSUT(promoCoordinator: promoCoordinator)
        try appearRemoteMessageGate(in: sut, expectedMessageID: "message-a")

        sut.tearDown()
        XCTAssertEqual(promoCoordinator.arbiter.snapshot.visiblePromoCount, 1)

        await waitForNextMainQueueTurn()

        XCTAssertEqual(promoCoordinator.arbiter.snapshot.visiblePromoCount, 0)
    }

    func testConfigurationRemovalClearsBlockedCandidateWithoutAppearanceAccounting() throws {
        let promoCoordinator = ArbitratingNewTabPagePromoCoordinatorMock(featureState: .enabled)
        promoCoordinator.acquireModalLease()
        messagesConfiguration.homeMessages = [.mockRemote(id: "message-a", withType: .small(titleText: "Title", descriptionText: "Body"))]
        let sut = createRenderableSUT(promoCoordinator: promoCoordinator)
        try appearRemoteMessageGate(in: sut, expectedMessageID: "message-a")

        messagesConfiguration.homeMessages = []
        sut.refresh()

        XCTAssertTrue(sut.homeMessageRenderItems.isEmpty)
        XCTAssertTrue(sut.homeMessageViewModels.isEmpty)
        XCTAssertNil(messagesConfiguration.lastAppearedHomeMessage)
        XCTAssertNil(try remoteRenderSession(in: sut))
    }

    func testWhenRetryRefreshesBlockedCandidateThenSuppliedAdmissionHandlerIsCalledOnce() throws {
        let promoCoordinator = ArbitratingNewTabPagePromoCoordinatorMock(featureState: .enabled)
        promoCoordinator.acquireModalLease()
        messagesConfiguration.homeMessages = [.mockRemote(id: "message-a", withType: .small(titleText: "Title", descriptionText: "Body"))]
        let sut = createRenderableSUT(promoCoordinator: promoCoordinator)
        try appearRemoteMessageGate(in: sut, expectedMessageID: "message-a")
        let admissionCallCountBeforeRetry = promoCoordinator.publicAdmissionCallCount

        sut.retryVisiblePromoAdmission(using: promoCoordinator.admitVisiblePromo)

        XCTAssertEqual(promoCoordinator.publicAdmissionCallCount - admissionCallCountBeforeRetry, 1)
        XCTAssertNil(try remoteRenderSession(in: sut))
        XCTAssertEqual(promoCoordinator.arbiter.snapshot.visiblePromoCount, 0)
    }

    func testWhenLegacyCandidateChangesDuringLiveEnableThenReplacementWaitsForGateAppearance() throws {
        let promoCoordinator = ArbitratingNewTabPagePromoCoordinatorMock()
        messagesConfiguration.homeMessages = [.mockRemote(id: "message-a", withType: .small(titleText: "First", descriptionText: "Body"))]
        let sut = createRenderableSUT(promoCoordinator: promoCoordinator)

        promoCoordinator.promoQueueFeatureState = .transitioning(to: .enabled)
        sut.promoQueueWillTransition(to: .enabled)
        messagesConfiguration.homeMessages = [.mockRemote(id: "message-b", withType: .small(titleText: "Second", descriptionText: "Body"))]
        sut.promoQueueDidTransition(to: .enabled)
        sut.retryVisiblePromoAdmission(using: promoCoordinator.admitVisiblePromo)

        XCTAssertNil(try remoteRenderSession(in: sut))
        XCTAssertEqual(promoCoordinator.arbiter.snapshot.visiblePromoCount, 0)

        promoCoordinator.promoQueueFeatureState = .enabled
        try appearRemoteMessageGate(in: sut, expectedMessageID: "message-b")

        XCTAssertNotNil(try remoteRenderSession(in: sut))
        XCTAssertEqual(promoCoordinator.arbiter.snapshot.visiblePromoIdentities.map(\.promoID), ["message-b"])
    }

    func testLiveDisableReleasesCoordinatedLeaseOnNextTurnBeforeLegacyRepublish() async throws {
        let promoCoordinator = ArbitratingNewTabPagePromoCoordinatorMock(featureState: .enabled)
        messagesConfiguration.homeMessages = [.mockRemote(id: "message-a", withType: .small(titleText: "Title", descriptionText: "Body"))]
        let sut = createRenderableSUT(promoCoordinator: promoCoordinator)
        try appearRemoteMessageGate(in: sut, expectedMessageID: "message-a")
        let coordinatedSession = try XCTUnwrap(try remoteRenderSession(in: sut))
        coordinatedSession.viewModel.onDidAppear()

        promoCoordinator.promoQueueFeatureState = .transitioning(to: .disabled)
        sut.promoQueueWillTransition(to: .disabled)

        XCTAssertTrue(sut.homeMessageViewModels.isEmpty)
        XCTAssertNil(try remoteRenderSession(in: sut))
        XCTAssertEqual(promoCoordinator.arbiter.snapshot.visiblePromoCount, 1)

        await waitForNextMainQueueTurn()
        XCTAssertEqual(promoCoordinator.arbiter.snapshot.visiblePromoCount, 0)

        sut.promoQueueDidTransition(to: .disabled)

        XCTAssertEqual(sut.homeMessageViewModels.map(\.messageId), ["message-a"])
        XCTAssertEqual(messagesConfiguration.appearanceCallCount, 2)
        sut.homeMessageViewModels.first?.onDidAppear()
        XCTAssertEqual(messagesConfiguration.appearanceCallCount, 3)
    }

    func testLiveDisableBeforeShownStorageCompletesDoesNotRefireUniqueOnLegacyRepublish() async throws {
        let remoteMessage = RemoteMessageModel(
            id: "message-a",
            surfaces: .newTabPage,
            content: .small(titleText: "Title", descriptionText: "Body"),
            matchingRules: [],
            exclusionRules: [],
            isMetricsEnabled: true
        )
        let shownUpdateStarted = expectation(description: "Shown store update started")
        let shownUpdateCompleted = expectation(description: "Shown store update completed")
        let store = SuspendedShownRemoteMessagingStore(
            scheduledRemoteMessage: remoteMessage,
            onShownUpdateStarted: {
                shownUpdateStarted.fulfill()
            },
            onShownUpdateCompleted: {
                shownUpdateCompleted.fulfill()
            }
        )
        defer {
            store.completePendingShownUpdate()
        }
        let pixelReporter = HomePageMessageShownPixelReporterMock()
        let configuration = HomePageConfiguration(
            remoteMessagingStore: store,
            subscriptionDataReporter: MockSubscriptionDataReporter(),
            isStillOnboarding: { false },
            shownPixelReporter: pixelReporter
        )
        let promoCoordinator = ArbitratingNewTabPagePromoCoordinatorMock(featureState: .enabled)
        let sut = createRenderableSUT(
            homePageMessagesConfiguration: configuration,
            promoCoordinator: promoCoordinator
        )
        try appearRemoteMessageGate(in: sut, expectedMessageID: remoteMessage.id)
        try XCTUnwrap(remoteRenderSession(in: sut)).viewModel.onDidAppear()
        await fulfillment(of: [shownUpdateStarted], timeout: 1)
        XCTAssertEqual(store.shownUpdateCallCount, 1)

        promoCoordinator.promoQueueFeatureState = .transitioning(to: .disabled)
        sut.promoQueueWillTransition(to: .disabled)
        await waitForNextMainQueueTurn()
        sut.promoQueueDidTransition(to: .disabled)

        XCTAssertEqual(pixelReporter.shownCount, 2)
        XCTAssertEqual(pixelReporter.uniqueShownCount, 1)
        XCTAssertFalse(store.hasShownRemoteMessage(withID: remoteMessage.id))

        sut.homeMessageViewModels.first?.onDidAppear()

        XCTAssertEqual(pixelReporter.shownCount, 3)
        XCTAssertEqual(pixelReporter.uniqueShownCount, 1)
        XCTAssertEqual(store.shownUpdateCallCount, 1)

        store.completePendingShownUpdate()
        await fulfillment(of: [shownUpdateCompleted], timeout: 1)
        XCTAssertTrue(store.hasShownRemoteMessage(withID: remoteMessage.id))
    }

    func testRemovedAndReinsertedSameIDGetsNewGateAndIgnoresStaleGateCallbacks() async throws {
        let promoCoordinator = ArbitratingNewTabPagePromoCoordinatorMock(featureState: .enabled)
        messagesConfiguration.homeMessages = [.mockRemote(id: "message-a", withType: .small(titleText: "First", descriptionText: "Body"))]
        let sut = createRenderableSUT(promoCoordinator: promoCoordinator)
        let originalGate = try XCTUnwrap(try remoteMessageGate(in: sut))
        let originalMountID = UUID()
        sut.remoteMessageGateDidAppear(
            gateID: originalGate.id,
            messageID: originalGate.messageID,
            mountID: originalMountID
        )
        XCTAssertNotNil(try remoteRenderSession(in: sut))

        messagesConfiguration.homeMessages = []
        sut.refresh()
        await waitForNextMainQueueTurn()

        messagesConfiguration.homeMessages = [.mockRemote(id: "message-a", withType: .small(titleText: "Second", descriptionText: "Body"))]
        sut.refresh()
        let replacementGate = try XCTUnwrap(try remoteMessageGate(in: sut))

        XCTAssertNotEqual(replacementGate.id, originalGate.id)

        sut.remoteMessageGateDidAppear(
            gateID: originalGate.id,
            messageID: originalGate.messageID,
            mountID: originalMountID
        )
        XCTAssertNil(try remoteRenderSession(in: sut))

        let replacementMountID = UUID()
        sut.remoteMessageGateDidAppear(
            gateID: replacementGate.id,
            messageID: replacementGate.messageID,
            mountID: replacementMountID
        )
        let replacementSession = try XCTUnwrap(try remoteRenderSession(in: sut))

        sut.remoteMessageGateDidDisappear(
            gateID: originalGate.id,
            messageID: originalGate.messageID,
            mountID: originalMountID
        )

        XCTAssertEqual(try remoteRenderSession(in: sut)?.id, replacementSession.id)
        XCTAssertEqual(promoCoordinator.arbiter.snapshot.visiblePromoCount, 1)
    }

    func testRapidDisableEnableUsesNewGateAndIgnoresPriorGenerationCallbacks() throws {
        let promoCoordinator = ArbitratingNewTabPagePromoCoordinatorMock(featureState: .enabled)
        messagesConfiguration.homeMessages = [.mockRemote(id: "message-a", withType: .small(titleText: "Title", descriptionText: "Body"))]
        let sut = createRenderableSUT(promoCoordinator: promoCoordinator)
        let originalGate = try XCTUnwrap(try remoteMessageGate(in: sut))
        let originalMountID = UUID()
        sut.remoteMessageGateDidAppear(
            gateID: originalGate.id,
            messageID: originalGate.messageID,
            mountID: originalMountID
        )
        let originalSession = try XCTUnwrap(try remoteRenderSession(in: sut))

        promoCoordinator.promoQueueFeatureState = .transitioning(to: .disabled)
        sut.promoQueueWillTransition(to: .disabled)
        sut.remoteMessageDidDisappear(renderSessionID: originalSession.id, mountID: originalMountID)
        promoCoordinator.arbiter.invalidateAllLeases()
        sut.promoQueueDidTransition(to: .disabled)

        promoCoordinator.promoQueueFeatureState = .transitioning(to: .enabled)
        sut.promoQueueWillTransition(to: .enabled)
        sut.promoQueueDidTransition(to: .enabled)
        promoCoordinator.promoQueueFeatureState = .enabled
        let replacementGate = try XCTUnwrap(try remoteMessageGate(in: sut))

        XCTAssertNotEqual(replacementGate.id, originalGate.id)

        sut.remoteMessageGateDidAppear(
            gateID: originalGate.id,
            messageID: originalGate.messageID,
            mountID: originalMountID
        )
        sut.remoteMessageGateDidDisappear(
            gateID: originalGate.id,
            messageID: originalGate.messageID,
            mountID: originalMountID
        )
        XCTAssertNil(try remoteRenderSession(in: sut))

        let replacementMountID = UUID()
        sut.remoteMessageGateDidAppear(
            gateID: replacementGate.id,
            messageID: replacementGate.messageID,
            mountID: replacementMountID
        )

        XCTAssertNotNil(try remoteRenderSession(in: sut))
        XCTAssertEqual(promoCoordinator.arbiter.snapshot.visiblePromoCount, 1)
    }

    // MARK: Callbacks

    func testCallsDismissOnClose() async throws {
        let sut = createSUT()
        messagesConfiguration.homeMessages = [
            .mockRemote(withType: .small(titleText: "", descriptionText: "")),
        ]
        sut.load()

        let model = try XCTUnwrap(sut.homeMessageViewModels.first)

        await model.onDidClose(.close)

        XCTAssertEqual(messagesConfiguration.lastDismissedHomeMessage, messagesConfiguration.homeMessages.first)
    }

    func testCallsDismissOnAction() async throws {
        let sut = createSUT()
        messagesConfiguration.homeMessages = [
            .mockRemote(withType: .small(titleText: "", descriptionText: "")),
        ]
        sut.load()

        let model = try XCTUnwrap(sut.homeMessageViewModels.first)

        await model.onDidClose(.action(isShare: false))

        XCTAssertEqual(messagesConfiguration.lastDismissedHomeMessage, messagesConfiguration.homeMessages.first)
    }

    func testCallsDismissOnPrimaryAction() async throws {
        let sut = createSUT()
        messagesConfiguration.homeMessages = [
            .mockRemote(withType: .small(titleText: "", descriptionText: "")),
        ]
        sut.load()

        let model = try XCTUnwrap(sut.homeMessageViewModels.first)

        await model.onDidClose(.primaryAction(isShare: false))

        XCTAssertEqual(messagesConfiguration.lastDismissedHomeMessage, messagesConfiguration.homeMessages.first)
    }

    func testCallsDismissOnSecondaryAction() async throws {
        let sut = createSUT()
        messagesConfiguration.homeMessages = [
            .mockRemote(withType: .small(titleText: "", descriptionText: "")),
        ]
        sut.load()

        let model = try XCTUnwrap(sut.homeMessageViewModels.first)

        await model.onDidClose(.secondaryAction(isShare: false))

        XCTAssertEqual(messagesConfiguration.lastDismissedHomeMessage, messagesConfiguration.homeMessages.first)
    }

    func testDoesNotCallDismissWhenSharing() async throws {
        let sut = createSUT()
        messagesConfiguration.homeMessages = [
            .mockRemote(withType: .small(titleText: "", descriptionText: "")),
        ]
        sut.load()

        let model = try XCTUnwrap(sut.homeMessageViewModels.first)

        await model.onDidClose(.action(isShare: true))
        await model.onDidClose(.primaryAction(isShare: true))
        await model.onDidClose(.secondaryAction(isShare: true))

        XCTAssertNil(messagesConfiguration.lastDismissedHomeMessage)
    }

    func testMessageNavigator() async throws {

        func assertSegueCount(_ count: Int) {
            XCTAssertEqual(segueToSettingsCallCount, count)
            XCTAssertEqual(segueToSettingsGeneralCallCount, count)
            XCTAssertEqual(segueToAIChatSettingsCallCount, count)
            XCTAssertEqual(segueToFeedbackCallCount, count)
            XCTAssertEqual(segueToSettingsAppearanceCallCount, count)
            XCTAssertEqual(segueToPIRCallCount, count)
        }

        // Start state
        assertSegueCount(0)

        // Individual states
        DefaultMessageNavigator(delegate: self).navigateTo(.settings, presentationStyle: .dismissModalsAndPresentFromRoot)
        XCTAssertEqual(segueToSettingsCallCount, 1)

        DefaultMessageNavigator(delegate: self).navigateTo(.settingsGeneral, presentationStyle: .dismissModalsAndPresentFromRoot)
        XCTAssertEqual(segueToSettingsGeneralCallCount, 1)

        DefaultMessageNavigator(delegate: self).navigateTo(.duckAISettings, presentationStyle: .dismissModalsAndPresentFromRoot)
        XCTAssertEqual(segueToAIChatSettingsCallCount, 1)
        
        DefaultMessageNavigator(delegate: self).navigateTo(.feedback, presentationStyle: .dismissModalsAndPresentFromRoot)
        XCTAssertEqual(segueToFeedbackCallCount, 1)

        DefaultMessageNavigator(delegate: self).navigateTo(.appearance, presentationStyle: .dismissModalsAndPresentFromRoot)
        XCTAssertEqual(segueToSettingsAppearanceCallCount, 1)

        DefaultMessageNavigator(delegate: self).navigateTo(.personalInformationRemoval, presentationStyle: .dismissModalsAndPresentFromRoot)
        XCTAssertEqual(segueToPIRCallCount, 1)

        // End state
        assertSegueCount(1)

    }

    // MARK: Pixels

    func testFiresPixelOnClose() async throws {
        let sut = createSUT()
        messagesConfiguration.homeMessages = [
            .mockRemote(withType: .small(titleText: "", descriptionText: "")),
        ]
        sut.load()

        let model = try XCTUnwrap(sut.homeMessageViewModels.first)

        await model.onDidClose(.close)

        XCTAssertEqual(PixelFiringMock.lastPixelName, Pixel.Event.remoteMessageDismissed.name)
        XCTAssertEqual(PixelFiringMock.lastParams, [PixelParameters.message: "foo"])
    }

    func testFiresPixelOnAction() async throws {
        let sut = createSUT()
        messagesConfiguration.homeMessages = [
            .mockRemote(withType: .small(titleText: "", descriptionText: "")),
        ]
        sut.load()

        let model = try XCTUnwrap(sut.homeMessageViewModels.first)
        await model.onDidClose(.action(isShare: false))

        XCTAssertEqual(PixelFiringMock.lastPixelName, Pixel.Event.remoteMessageActionClicked.name)
        XCTAssertEqual(PixelFiringMock.lastParams, [PixelParameters.message: "foo"])
    }

    func testFiresPixelOnPrimaryAction() async throws {
        let sut = createSUT()
        messagesConfiguration.homeMessages = [
            .mockRemote(withType: .small(titleText: "", descriptionText: "")),
        ]
        sut.load()

        let model = try XCTUnwrap(sut.homeMessageViewModels.first)
        await model.onDidClose(.primaryAction(isShare: false))

        XCTAssertEqual(PixelFiringMock.lastPixelName, Pixel.Event.remoteMessagePrimaryActionClicked.name)
        XCTAssertEqual(PixelFiringMock.lastParams, [PixelParameters.message: "foo"])
    }

    func testFiresPixelOnSecondaryAction() async throws {
        let sut = createSUT()
        messagesConfiguration.homeMessages = [
            .mockRemote(withType: .small(titleText: "", descriptionText: "")),
        ]
        sut.load()

        let model = try XCTUnwrap(sut.homeMessageViewModels.first)
        await model.onDidClose(.secondaryAction(isShare: false))

        XCTAssertEqual(PixelFiringMock.lastPixelName, Pixel.Event.remoteMessageSecondaryActionClicked.name)
        XCTAssertEqual(PixelFiringMock.lastParams, [PixelParameters.message: "foo"])
    }

    func testDoesNotFirePixelOnCloseWhenMetricsAreDisabled() async throws {
        let sut = createSUT()
        messagesConfiguration.homeMessages = [
            .mockRemote(withType: .small(titleText: "", descriptionText: ""), isMetricsEnabled: false),
        ]
        sut.load()

        let model = try XCTUnwrap(sut.homeMessageViewModels.first)

        await model.onDidClose(.close)

        XCTAssertNil(PixelFiringMock.lastPixelName)
        XCTAssertNil(PixelFiringMock.lastParams)
    }

    func testDoesNotFirePixelOnActionWhenMetricsAreDisabled() async throws {
        let sut = createSUT()
        messagesConfiguration.homeMessages = [
            .mockRemote(withType: .small(titleText: "", descriptionText: ""), isMetricsEnabled: false),
        ]
        sut.load()

        let model = try XCTUnwrap(sut.homeMessageViewModels.first)
        await model.onDidClose(.action(isShare: false))

        XCTAssertNil(PixelFiringMock.lastPixelName)
        XCTAssertNil(PixelFiringMock.lastParams)
    }

    func testDoesNotFirePixelOnPrimaryActionWhenMetricsAreDisabled() async throws {
        let sut = createSUT()
        messagesConfiguration.homeMessages = [
            .mockRemote(withType: .small(titleText: "", descriptionText: ""), isMetricsEnabled: false),
        ]
        sut.load()

        let model = try XCTUnwrap(sut.homeMessageViewModels.first)
        await model.onDidClose(.primaryAction(isShare: false))

        XCTAssertNil(PixelFiringMock.lastPixelName)
        XCTAssertNil(PixelFiringMock.lastParams)
    }

    func testDoesNotFirePixelOnSecondaryActionWhenMetricsAreDisabled() async throws {
        let sut = createSUT()
        messagesConfiguration.homeMessages = [
            .mockRemote(withType: .small(titleText: "", descriptionText: ""), isMetricsEnabled: false),
        ]
        sut.load()

        let model = try XCTUnwrap(sut.homeMessageViewModels.first)
        await model.onDidClose(.secondaryAction(isShare: false))

        XCTAssertNil(PixelFiringMock.lastPixelName)
        XCTAssertNil(PixelFiringMock.lastParams)
    }

    // MARK: - openedAfterIdle

    func testWhenOpenedAfterIdleIsTrueThenRefreshPassesOpenedAfterIdleTrue() {
        let sut = createSUT(isOpenedAfterIdle: true)

        sut.load()

        XCTAssertTrue(messagesConfiguration.didRefresh)
        XCTAssertEqual(messagesConfiguration.lastRefreshOpenedAfterIdle, true)
    }

    func testWhenOpenedAfterIdleIsFalseThenRefreshPassesOpenedAfterIdleFalse() {
        let sut = createSUT(isOpenedAfterIdle: false)

        sut.load()

        XCTAssertTrue(messagesConfiguration.didRefresh)
        XCTAssertEqual(messagesConfiguration.lastRefreshOpenedAfterIdle, false)
    }

    func testWhenDefaultOpenedAfterIdleThenRefreshPassesFalse() {
        let sut = createSUT()

        sut.load()

        XCTAssertTrue(messagesConfiguration.didRefresh)
        XCTAssertEqual(messagesConfiguration.lastRefreshOpenedAfterIdle, false)
    }

    // MARK: - Helpers

    private func createSUT(
        isOpenedAfterIdle: Bool = false,
        homePageMessagesConfiguration: HomePageMessagesConfiguration? = nil,
        promoCoordinator: ArbitratingNewTabPagePromoCoordinatorMock? = nil,
        promoQueuePixelReporter: PromoQueuePixelReporting = MockPromoQueuePixelReporter()
    ) -> NewTabPageMessagesModel {
        // Built here rather than as a default argument: the mock is `@MainActor`, and default
        // argument expressions are evaluated in a nonisolated context.
        let promoCoordinator = promoCoordinator ?? ArbitratingNewTabPagePromoCoordinatorMock()
        let remoteMessageActionHandler = RemoteMessagingActionHandler(lastSearchStateRefresher: RemoteMessagingSurveyLastSearchStateRefresher())
        remoteMessageActionHandler.messageNavigator = DefaultMessageNavigator(delegate: self)

        return NewTabPageMessagesModel(homePageMessagesConfiguration: homePageMessagesConfiguration ?? messagesConfiguration,
                                notificationCenter: notificationCenter,
                                pixelFiring: PixelFiringMock.self,
                                messageActionHandler: remoteMessageActionHandler,
                                imageLoader: MockRemoteMessagingImageLoader(),
                                promoCoordinator: promoCoordinator,
                                promoQueuePixelReporter: promoQueuePixelReporter,
                                isOpenedAfterIdle: { isOpenedAfterIdle })
    }

    private func createRenderableSUT(
        homePageMessagesConfiguration: HomePageMessagesConfiguration? = nil,
        promoCoordinator: ArbitratingNewTabPagePromoCoordinatorMock,
        promoQueuePixelReporter: PromoQueuePixelReporting = MockPromoQueuePixelReporter()
    ) -> NewTabPageMessagesModel {
        let sut = createSUT(
            homePageMessagesConfiguration: homePageMessagesConfiguration,
            promoCoordinator: promoCoordinator,
            promoQueuePixelReporter: promoQueuePixelReporter
        )
        sut.setSurfaceAttachmentProvider { true }
        sut.load()
        sut.setSurfaceRenderable(true)
        return sut
    }

    private func remoteRenderSession(
        in sut: NewTabPageMessagesModel
    ) throws -> NewTabPageRemoteMessageRenderSession? {
        try remoteMessageGate(in: sut)?.renderSession
    }

    private func remoteMessageGate(
        in sut: NewTabPageMessagesModel
    ) throws -> NewTabPageRemoteMessageGate? {
        guard let item = sut.homeMessageRenderItems.first else {
            return nil
        }
        guard case .remoteMessageGate(let gate) = item.content else {
            return nil
        }
        return gate
    }

    @discardableResult
    private func appearRemoteMessageGate(
        in sut: NewTabPageMessagesModel,
        expectedMessageID: String
    ) throws -> UUID {
        let gate = try XCTUnwrap(try remoteMessageGate(in: sut))
        XCTAssertEqual(gate.messageID, expectedMessageID)
        let mountID = UUID()
        sut.remoteMessageGateDidAppear(
            gateID: gate.id,
            messageID: gate.messageID,
            mountID: mountID
        )
        return mountID
    }

    private func waitForNextMainQueueTurn() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }
}

@MainActor
private final class ArbitratingNewTabPagePromoCoordinatorMock: NewTabPagePromoCoordinating {
    var promoQueueFeatureState: PromoQueueFeatureState
    let arbiter = PromoQueueLeaseArbiter()
    private(set) weak var retryTarget: NewTabPagePromoRetrying?
    private(set) var registrationCount = 0
    private(set) var deregistrationCount = 0
    private(set) var publicAdmissionCallCount = 0
    private var modalLease: PromoQueueModalLease?

    init(featureState: PromoQueueFeatureState = .disabled) {
        promoQueueFeatureState = featureState
    }

    func acquireModalLease() {
        guard case .acquired(let lease) = arbiter.acquireModalLease() else {
            XCTFail("Expected the mock modal lease to be acquired.")
            return
        }
        modalLease = lease
    }

    func admitVisiblePromo(_ identity: VisiblePromoIdentity) -> VisiblePromoAdmissionResult {
        publicAdmissionCallCount += 1
        switch promoQueueFeatureState {
        case .disabled:
            return .featureDisabled
        case .transitioning:
            return .unavailableDuringTransition
        case .enabled:
            break
        }

        switch arbiter.acquireVisiblePromoLease(for: identity) {
        case .acquired(let lease):
            return .acquired(lease)
        case .blockedByModal:
            return .blockedByModal
        case .occupiedSurfaceSlot(let identity):
            return .occupiedSurfaceSlot(identity)
        }
    }

    func releaseVisiblePromoLease(_ lease: PromoQueueVisiblePromoLease) {
        lease.release()
    }

    func registerVisiblePromoRetry(
        for surfaceID: UUID,
        target: NewTabPagePromoRetrying
    ) -> NewTabPagePromoRetryRegistration {
        registrationCount += 1
        retryTarget = target
        return NewTabPagePromoRetryRegistration { [weak self, weak target] in
            guard let self, retryTarget === target else {
                return
            }
            deregistrationCount += 1
            retryTarget = nil
        }
    }
}
private final class MockPromoQueuePixelReporter: PromoQueuePixelReporting {
    private(set) var modalAdmissionBlockedByRemoteMessageCount = 0
    private(set) var remoteMessageAdmissionBlockedByModalCount = 0

    func fireModalAdmissionBlockedByRemoteMessage() {
        modalAdmissionBlockedByRemoteMessageCount += 1
    }

    func fireRemoteMessageAdmissionBlockedByModal() {
        remoteMessageAdmissionBlockedByModalCount += 1
    }
}
extension NewTabPageMessagesModelTests: MessageNavigationDelegate {

    func segueToSettingsAIChat(openedFromSERPSettingsButton: Bool, presentationStyle: PresentationContext.Style) {
        segueToAIChatSettingsCallCount += 1
    }
    
    func segueToSettings(presentationStyle: PresentationContext.Style) {
        segueToSettingsCallCount += 1
    }

    func segueToSettingsGeneral(presentationStyle: PresentationContext.Style) {
        segueToSettingsGeneralCallCount += 1
    }

    func segueToFeedback(presentationStyle: PresentationContext.Style) {
        segueToFeedbackCallCount += 1
    }

    func segueToSettingsSync(with source: String?, pairingInfo: PairingInfo?, presentationStyle: PresentationContext.Style) {
        segueToSyncSettingsCallCount += 1
    }

    func segueToImportPasswords(presentationStyle: DuckDuckGo.PresentationContext.Style) {
        assertionFailure("Not implemented yet")
    }

    func segueToSettingsAppearance(presentationStyle: PresentationContext.Style) {
        segueToSettingsAppearanceCallCount += 1
    }

    func segueToPIR(presentationStyle: DuckDuckGo.PresentationContext.Style) {
        segueToPIRCallCount += 1
    }

}

private extension HomeMessage {
    static func mockRemote(
        id: String = "foo",
        withType type: RemoteMessageModelType,
        isMetricsEnabled: Bool = true
    ) -> Self {
        HomeMessage.remoteMessage(
            remoteMessage: .init(
                id: id,
                surfaces: .newTabPage,
                content: type,
                matchingRules: [],
                exclusionRules: [],
                isMetricsEnabled: isMetricsEnabled
            )
        )
    }
}

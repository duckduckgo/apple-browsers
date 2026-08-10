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
import DDGSync
import RemoteMessaging
import SwiftUI
import UIKit
import XCTest

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
        let promoCoordinator = ArbitratingNewTabPagePromoCoordinatorMock(promoCoordinationMode: .legacy)
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
        let promoCoordinator = ArbitratingNewTabPagePromoCoordinatorMock(promoCoordinationMode: .legacy)
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
        let promoCoordinator = ArbitratingNewTabPagePromoCoordinatorMock(promoCoordinationMode: .coordinated)
        promoCoordinator.acquireModalLease()
        messagesConfiguration.homeMessages = [.mockRemote(id: "message-a", withType: .small(titleText: "Title", descriptionText: "Body"))]
        let sut = createRenderableSUT(promoCoordinator: promoCoordinator)

        try appearRemoteMessageGate(in: sut, expectedMessageID: "message-a")

        XCTAssertTrue(sut.homeMessageViewModels.isEmpty)
        XCTAssertNil(try remoteRenderSession(in: sut))
        XCTAssertTrue(promoCoordinator.arbiter.snapshot.hasModalLease)
        XCTAssertNil(messagesConfiguration.lastAppearedHomeMessage)
    }

    func testFeatureOnConstructsAndPublishesRemoteCardOnlyAfterLeaseAdmission() throws {
        let promoCoordinator = ArbitratingNewTabPagePromoCoordinatorMock(promoCoordinationMode: .coordinated)
        messagesConfiguration.homeMessages = [.mockRemote(id: "message-a", withType: .small(titleText: "Title", descriptionText: "Body"))]
        let sut = createRenderableSUT(promoCoordinator: promoCoordinator)

        XCTAssertTrue(sut.homeMessageViewModels.isEmpty)
        XCTAssertNil(try remoteRenderSession(in: sut))

        try appearRemoteMessageGate(in: sut, expectedMessageID: "message-a")

        XCTAssertEqual(sut.homeMessageViewModels.map(\.messageId), ["message-a"])
        XCTAssertNotNil(try remoteRenderSession(in: sut))
        XCTAssertNotNil(promoCoordinator.arbiter.snapshot.visiblePromoIdentity)
        XCTAssertNil(messagesConfiguration.lastAppearedHomeMessage)
    }

    func testFeatureOnAcquiresAdmissionBeforeSynchronousImageLoaderAccess() throws {
        let promoCoordinator = ArbitratingNewTabPagePromoCoordinatorMock(promoCoordinationMode: .coordinated)
        let imageLoader = AdmissionOrderingImageLoader()
        promoCoordinator.onAdmissionAcquired = { _ in
            imageLoader.recordAdmissionAcquired()
        }
        messagesConfiguration.homeMessages = [
            .mockRemote(
                id: "message-a",
                withType: .medium(
                    titleText: "Title",
                    descriptionText: "Body",
                    placeholder: .announce,
                    imageUrl: URL(string: "https://example.com/image.png")
                )
            )
        ]
        let sut = createSUT(
            promoCoordinator: promoCoordinator,
            imageLoader: imageLoader
        )
        sut.setSurfaceAttachmentProvider { true }
        sut.load()
        sut.setSurfaceRenderable(true)

        try appearRemoteMessageGate(in: sut, expectedMessageID: "message-a")

        XCTAssertEqual(imageLoader.events, [.admissionAcquired, .cachedImageRequested])
        XCTAssertNotNil(promoCoordinator.arbiter.snapshot.visiblePromoIdentity)
        XCTAssertNotNil(try remoteRenderSession(in: sut))
    }

    func testUnsupportedRemoteCardReleasesLeaseSynchronouslyAfterAdmission() throws {
        let promoCoordinator = ArbitratingNewTabPagePromoCoordinatorMock(promoCoordinationMode: .coordinated)
        messagesConfiguration.homeMessages = [
            .mockRemote(
                id: "message-a",
                withType: .cardsList(
                    titleText: "Unsupported",
                    placeholder: nil,
                    imageUrl: nil,
                    items: [],
                    primaryActionText: "Dismiss",
                    primaryAction: .dismiss
                )
            )
        ]
        let sut = createRenderableSUT(promoCoordinator: promoCoordinator)

        try appearRemoteMessageGate(in: sut, expectedMessageID: "message-a")

        XCTAssertNil(try remoteRenderSession(in: sut))
        XCTAssertNil(promoCoordinator.arbiter.snapshot.activeOwner)
        XCTAssertEqual(promoCoordinator.releaseCallCount, 1)
    }

    func testWhenRealSwiftUICardIsWithdrawnThenModalCannotAcquireUntilCardDidDisappear() async throws {
        let cardDidAppear = expectation(description: "Remote-message card appeared")
        let cardDidDisappear = expectation(description: "Remote-message card disappeared")
        let visibleLeaseReleased = expectation(description: "Visible lease released after physical removal")
        var events = [String]()
        var isCardRendered = false
        var didObserveCardDisappear = false
        var acquiredModalLease: PromoQueueModalLease?
        let promoCoordinator = ArbitratingNewTabPagePromoCoordinatorMock(promoCoordinationMode: .coordinated)
        promoCoordinator.onVisibleLeaseReleased = { [weak promoCoordinator] in
            guard let promoCoordinator else {
                return
            }

            events.append("visibleLeaseReleased")
            XCTAssertFalse(isCardRendered)
            XCTAssertTrue(didObserveCardDisappear)
            switch promoCoordinator.arbiter.acquireModalLease() {
            case .acquired(let lease):
                acquiredModalLease = lease
                events.append("modalAcquired")
            case .blockedByModal, .blockedByVisiblePromo:
                XCTFail("Expected modal acquisition only after the physically removed RMF released its lease")
            }
            visibleLeaseReleased.fulfill()
        }
        messagesConfiguration.homeMessages = [
            .mockRemote(id: "message-a", withType: .small(titleText: "Title", descriptionText: "Body"))
        ]
        let sut = createSUT(
            promoCoordinator: promoCoordinator,
            remoteMessageLifecycleObserver: { event in
                switch event {
                case .gateDidAppear:
                    events.append("gateDidAppear")
                case .cardDidAppear:
                    isCardRendered = true
                    events.append("cardDidAppear")
                    cardDidAppear.fulfill()
                case .cardDidDisappear:
                    isCardRendered = false
                    didObserveCardDisappear = true
                    events.append("cardDidDisappear")
                    switch promoCoordinator.arbiter.acquireModalLease() {
                    case .blockedByVisiblePromo:
                        break
                    case .acquired, .blockedByModal:
                        XCTFail("The outgoing RMF must retain its lease throughout the real card disappearance callback")
                    }
                    cardDidDisappear.fulfill()
                case .gateDidDisappear:
                    events.append("gateDidDisappear")
                }
            }
        )
        let hostState = NewTabPageRemoteMessageGateHostState()
        let hostingController = UIHostingController(
            rootView: NewTabPageRemoteMessageGateHost(
                messagesModel: sut,
                state: hostState
            )
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        defer {
            acquiredModalLease?.release()
            window.isHidden = true
        }

        sut.setSurfaceAttachmentProvider { [weak hostingController] in
            hostingController?.viewIfLoaded?.window != nil
        }
        sut.load()
        sut.setSurfaceRenderable(true)
        window.rootViewController = hostingController
        window.isHidden = false

        await fulfillment(of: [cardDidAppear], timeout: 1)

        XCTAssertTrue(isCardRendered)
        XCTAssertNotNil(promoCoordinator.arbiter.snapshot.visiblePromoIdentity)
        switch promoCoordinator.arbiter.acquireModalLease() {
        case .blockedByVisiblePromo:
            break
        case .acquired, .blockedByModal:
            XCTFail("The rendered RMF must block modal acquisition")
        }

        sut.setSurfaceRenderable(false)

        XCTAssertTrue(sut.homeMessageViewModels.isEmpty)
        XCTAssertNotNil(promoCoordinator.arbiter.snapshot.visiblePromoIdentity)
        switch promoCoordinator.arbiter.acquireModalLease() {
        case .blockedByVisiblePromo:
            break
        case .acquired, .blockedByModal:
            XCTFail("Publishing RMF removal must not release its lease before physical disappearance")
        }

        await fulfillment(of: [cardDidDisappear, visibleLeaseReleased], timeout: 1)

        XCTAssertEqual(promoCoordinator.releaseCallCount, 1)
        XCTAssertNotNil(acquiredModalLease)
        XCTAssertEqual(
            events,
            ["gateDidAppear", "cardDidAppear", "cardDidDisappear", "visibleLeaseReleased", "modalAcquired"]
        )
    }

    func testSameIDRefreshKeepsLeaseRenderSessionAndAppearanceReservation() throws {
        let promoCoordinator = ArbitratingNewTabPagePromoCoordinatorMock(promoCoordinationMode: .coordinated)
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
        sut.remoteMessageCardDidAppear(
            renderSessionID: originalSession.id,
            mountID: mountID
        )
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
        XCTAssertNotNil(promoCoordinator.arbiter.snapshot.visiblePromoIdentity)
    }

    func testOverlappingCardMountsKeepCurrentSessionUntilFinalMatchingMountDisappears() async throws {
        let promoCoordinator = ArbitratingNewTabPagePromoCoordinatorMock(promoCoordinationMode: .coordinated)
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
        sut.remoteMessageCardDidAppear(
            renderSessionID: session.id,
            mountID: originalMountID
        )

        sut.remoteMessageGateDidAppear(
            gateID: gate.id,
            messageID: gate.messageID,
            mountID: replacementMountID,
            renderSessionID: session.id
        )
        sut.remoteMessageCardDidAppear(
            renderSessionID: session.id,
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
        XCTAssertNotNil(promoCoordinator.arbiter.snapshot.visiblePromoIdentity)

        sut.remoteMessageDidDisappear(
            renderSessionID: session.id,
            mountID: replacementMountID
        )
        sut.remoteMessageGateDidDisappear(
            gateID: gate.id,
            messageID: gate.messageID,
            mountID: replacementMountID
        )

        XCTAssertNil(try remoteRenderSession(in: sut))
        XCTAssertNotNil(promoCoordinator.arbiter.snapshot.visiblePromoIdentity)

        await waitForNextMainQueueTurn()

        XCTAssertNil(promoCoordinator.arbiter.snapshot.activeOwner)
        XCTAssertEqual(promoCoordinator.releaseCallCount, 1)
    }

    func testPendingReplacementCardMountKeepsCurrentSessionWhenOriginalCardDisappearsFirst() async throws {
        let promoCoordinator = ArbitratingNewTabPagePromoCoordinatorMock(promoCoordinationMode: .coordinated)
        messagesConfiguration.homeMessages = [.mockRemote(id: "message-a", withType: .small(titleText: "Title", descriptionText: "Body"))]
        let sut = createRenderableSUT(promoCoordinator: promoCoordinator)
        let gate = try XCTUnwrap(try remoteMessageGate(in: sut))
        let originalMountID = UUID()
        let replacementMountID = UUID()

        sut.remoteMessageGateDidAppear(gateID: gate.id, messageID: gate.messageID, mountID: originalMountID)
        let session = try XCTUnwrap(try remoteRenderSession(in: sut))
        sut.remoteMessageCardDidAppear(renderSessionID: session.id, mountID: originalMountID)

        sut.remoteMessageGateDidAppear(
            gateID: gate.id,
            messageID: gate.messageID,
            mountID: replacementMountID,
            renderSessionID: session.id
        )
        sut.remoteMessageDidDisappear(renderSessionID: session.id, mountID: originalMountID)
        sut.remoteMessageGateDidDisappear(gateID: gate.id, messageID: gate.messageID, mountID: originalMountID)

        XCTAssertEqual(try remoteRenderSession(in: sut)?.id, session.id)
        XCTAssertNotNil(promoCoordinator.arbiter.snapshot.visiblePromoIdentity)
        XCTAssertEqual(promoCoordinator.releaseCallCount, 0)

        await waitForNextMainQueueTurn()

        XCTAssertEqual(try remoteRenderSession(in: sut)?.id, session.id)
        XCTAssertNotNil(promoCoordinator.arbiter.snapshot.visiblePromoIdentity)

        sut.remoteMessageCardDidAppear(renderSessionID: session.id, mountID: replacementMountID)
        sut.remoteMessageDidDisappear(renderSessionID: session.id, mountID: replacementMountID)
        sut.remoteMessageGateDidDisappear(gateID: gate.id, messageID: gate.messageID, mountID: replacementMountID)

        XCTAssertNotNil(promoCoordinator.arbiter.snapshot.visiblePromoIdentity)

        await waitForNextMainQueueTurn()

        XCTAssertNil(promoCoordinator.arbiter.snapshot.activeOwner)
        XCTAssertEqual(promoCoordinator.releaseCallCount, 1)
    }

    func testLateOutgoingCardAppearanceCancelsScheduledReleaseUntilThatMountDisappears() async throws {
        let promoCoordinator = ArbitratingNewTabPagePromoCoordinatorMock(promoCoordinationMode: .coordinated)
        messagesConfiguration.homeMessages = [.mockRemote(id: "message-a", withType: .small(titleText: "Title", descriptionText: "Body"))]
        let sut = createRenderableSUT(promoCoordinator: promoCoordinator)
        let originalMountID = try appearRemoteMessageGate(in: sut, expectedMessageID: "message-a")
        let session = try XCTUnwrap(try remoteRenderSession(in: sut))
        let lateMountID = UUID()

        sut.setSurfaceRenderable(false)
        sut.remoteMessageDidDisappear(renderSessionID: session.id, mountID: originalMountID)
        sut.remoteMessageCardDidAppear(renderSessionID: session.id, mountID: lateMountID)

        await waitForNextMainQueueTurn()

        XCTAssertNotNil(promoCoordinator.arbiter.snapshot.visiblePromoIdentity)
        XCTAssertEqual(promoCoordinator.releaseCallCount, 0)

        sut.remoteMessageDidDisappear(renderSessionID: session.id, mountID: lateMountID)
        XCTAssertNotNil(promoCoordinator.arbiter.snapshot.visiblePromoIdentity)

        await waitForNextMainQueueTurn()

        XCTAssertNil(promoCoordinator.arbiter.snapshot.activeOwner)
        XCTAssertEqual(promoCoordinator.releaseCallCount, 1)
    }

    func testEmptyGateRemountDoesNotCancelOutgoingRelease() async throws {
        let promoCoordinator = ArbitratingNewTabPagePromoCoordinatorMock(promoCoordinationMode: .coordinated)
        messagesConfiguration.homeMessages = [.mockRemote(id: "message-a", withType: .small(titleText: "Title", descriptionText: "Body"))]
        let sut = createRenderableSUT(promoCoordinator: promoCoordinator)
        let gate = try XCTUnwrap(try remoteMessageGate(in: sut))
        let originalMountID = UUID()
        let emptyGateMountID = UUID()

        sut.remoteMessageGateDidAppear(gateID: gate.id, messageID: gate.messageID, mountID: originalMountID)
        let session = try XCTUnwrap(try remoteRenderSession(in: sut))
        sut.remoteMessageCardDidAppear(renderSessionID: session.id, mountID: originalMountID)

        sut.setSurfaceRenderable(false)
        sut.remoteMessageDidDisappear(renderSessionID: session.id, mountID: originalMountID)
        sut.remoteMessageGateDidAppear(
            gateID: gate.id,
            messageID: gate.messageID,
            mountID: emptyGateMountID,
            renderSessionID: nil
        )

        XCTAssertNotNil(promoCoordinator.arbiter.snapshot.visiblePromoIdentity)

        await waitForNextMainQueueTurn()

        XCTAssertNil(promoCoordinator.arbiter.snapshot.activeOwner)
        XCTAssertEqual(promoCoordinator.releaseCallCount, 1)
    }

    func testStaleCardBearingGateAppearanceRetainsExactOutgoingSessionAfterCandidateChanges() async throws {
        let promoCoordinator = ArbitratingNewTabPagePromoCoordinatorMock(promoCoordinationMode: .coordinated)
        messagesConfiguration.homeMessages = [.mockRemote(id: "message-a", withType: .small(titleText: "First", descriptionText: "Body"))]
        let sut = createRenderableSUT(promoCoordinator: promoCoordinator)
        let originalGate = try XCTUnwrap(try remoteMessageGate(in: sut))
        let originalMountID = UUID()

        sut.remoteMessageGateDidAppear(
            gateID: originalGate.id,
            messageID: originalGate.messageID,
            mountID: originalMountID
        )
        let originalSession = try XCTUnwrap(try remoteRenderSession(in: sut))
        sut.remoteMessageCardDidAppear(renderSessionID: originalSession.id, mountID: originalMountID)

        messagesConfiguration.homeMessages = [.mockRemote(id: "message-b", withType: .small(titleText: "Second", descriptionText: "Body"))]
        sut.refresh()
        sut.remoteMessageDidDisappear(renderSessionID: originalSession.id, mountID: originalMountID)

        let staleMountID = UUID()
        sut.remoteMessageGateDidAppear(
            gateID: originalGate.id,
            messageID: originalGate.messageID,
            mountID: staleMountID,
            renderSessionID: originalSession.id
        )

        await waitForNextMainQueueTurn()

        XCTAssertEqual(promoCoordinator.arbiter.snapshot.visiblePromoIdentity?.promoID, "message-a")
        XCTAssertEqual(promoCoordinator.releaseCallCount, 0)

        sut.remoteMessageCardDidAppear(renderSessionID: originalSession.id, mountID: staleMountID)
        sut.remoteMessageDidDisappear(renderSessionID: originalSession.id, mountID: staleMountID)
        sut.remoteMessageGateDidDisappear(
            gateID: originalGate.id,
            messageID: originalGate.messageID,
            mountID: staleMountID
        )

        await waitForNextMainQueueTurn()

        XCTAssertNil(promoCoordinator.arbiter.snapshot.activeOwner)
        XCTAssertEqual(promoCoordinator.releaseCallCount, 1)
    }

    func testWhenRemoteMessageIDChangesThenReplacementWaitsForPhysicalRemovalBeforeAdmission() async throws {
        let promoCoordinator = ArbitratingNewTabPagePromoCoordinatorMock(promoCoordinationMode: .coordinated)
        messagesConfiguration.homeMessages = [.mockRemote(id: "message-a", withType: .small(titleText: "First", descriptionText: "Body"))]
        let sut = createRenderableSUT(promoCoordinator: promoCoordinator)
        let originalMountID = try appearRemoteMessageGate(in: sut, expectedMessageID: "message-a")
        let originalSession = try XCTUnwrap(try remoteRenderSession(in: sut))

        messagesConfiguration.homeMessages = [.mockRemote(id: "message-b", withType: .small(titleText: "Second", descriptionText: "Body"))]
        sut.refresh()
        try appearRemoteMessageGate(in: sut, expectedMessageID: "message-b")

        XCTAssertNil(try remoteRenderSession(in: sut))
        XCTAssertEqual(promoCoordinator.arbiter.snapshot.visiblePromoIdentity?.promoID, "message-a")

        await waitForNextMainQueueTurn()

        XCTAssertNil(try remoteRenderSession(in: sut))
        XCTAssertEqual(promoCoordinator.arbiter.snapshot.visiblePromoIdentity?.promoID, "message-a")

        sut.remoteMessageDidDisappear(
            renderSessionID: originalSession.id,
            mountID: originalMountID
        )

        XCTAssertNil(try remoteRenderSession(in: sut))
        XCTAssertEqual(promoCoordinator.arbiter.snapshot.visiblePromoIdentity?.promoID, "message-a")

        await waitForNextMainQueueTurn()
        let replacementSession = try XCTUnwrap(try remoteRenderSession(in: sut))

        XCTAssertNotEqual(replacementSession.id, originalSession.id)
        XCTAssertEqual(promoCoordinator.arbiter.snapshot.visiblePromoIdentity?.promoID, "message-b")
    }

    func testOutgoingSessionWaitsForFinalPhysicalMountAndReleasesExactlyOnce() async throws {
        let promoCoordinator = ArbitratingNewTabPagePromoCoordinatorMock(promoCoordinationMode: .coordinated)
        messagesConfiguration.homeMessages = [.mockRemote(id: "message-a", withType: .small(titleText: "Title", descriptionText: "Body"))]
        let sut = createRenderableSUT(promoCoordinator: promoCoordinator)
        let gate = try XCTUnwrap(try remoteMessageGate(in: sut))
        let firstMountID = UUID()
        let finalMountID = UUID()

        sut.remoteMessageGateDidAppear(gateID: gate.id, messageID: gate.messageID, mountID: firstMountID)
        let session = try XCTUnwrap(try remoteRenderSession(in: sut))
        sut.remoteMessageCardDidAppear(renderSessionID: session.id, mountID: firstMountID)
        sut.remoteMessageGateDidAppear(gateID: gate.id, messageID: gate.messageID, mountID: finalMountID)
        sut.remoteMessageCardDidAppear(renderSessionID: session.id, mountID: finalMountID)

        sut.setSurfaceRenderable(false)
        sut.remoteMessageDidDisappear(renderSessionID: session.id, mountID: firstMountID)
        await waitForNextMainQueueTurn()

        XCTAssertNotNil(promoCoordinator.arbiter.snapshot.visiblePromoIdentity)
        XCTAssertEqual(promoCoordinator.releaseCallCount, 0)

        sut.remoteMessageDidDisappear(renderSessionID: session.id, mountID: finalMountID)
        XCTAssertNotNil(promoCoordinator.arbiter.snapshot.visiblePromoIdentity)

        await waitForNextMainQueueTurn()

        XCTAssertNil(promoCoordinator.arbiter.snapshot.activeOwner)
        XCTAssertEqual(promoCoordinator.releaseCallCount, 1)

        sut.remoteMessageDidDisappear(renderSessionID: session.id, mountID: finalMountID)
        sut.remoteMessageGateDidDisappear(gateID: gate.id, messageID: gate.messageID, mountID: finalMountID)
        await waitForNextMainQueueTurn()

        XCTAssertEqual(promoCoordinator.releaseCallCount, 1)
    }

    func testRenderableWithdrawalRetainsLeaseUntilPhysicalDisappearanceThenReadmitsWhenRenderableAgain() async throws {
        let promoCoordinator = ArbitratingNewTabPagePromoCoordinatorMock(promoCoordinationMode: .coordinated)
        messagesConfiguration.homeMessages = [.mockRemote(id: "message-a", withType: .small(titleText: "Title", descriptionText: "Body"))]
        let sut = createRenderableSUT(promoCoordinator: promoCoordinator)
        let mountID = try appearRemoteMessageGate(in: sut, expectedMessageID: "message-a")
        let session = try XCTUnwrap(try remoteRenderSession(in: sut))

        sut.setSurfaceRenderable(false)

        XCTAssertTrue(sut.homeMessageViewModels.isEmpty)
        XCTAssertNotNil(promoCoordinator.arbiter.snapshot.visiblePromoIdentity)

        await waitForNextMainQueueTurn()
        XCTAssertNotNil(promoCoordinator.arbiter.snapshot.visiblePromoIdentity)

        sut.remoteMessageDidDisappear(renderSessionID: session.id, mountID: mountID)

        XCTAssertNotNil(promoCoordinator.arbiter.snapshot.visiblePromoIdentity)

        await waitForNextMainQueueTurn()
        XCTAssertNil(promoCoordinator.arbiter.snapshot.activeOwner)

        sut.setSurfaceRenderable(true)

        XCTAssertNotNil(try remoteRenderSession(in: sut))
        XCTAssertNotNil(promoCoordinator.arbiter.snapshot.visiblePromoIdentity)
    }

    func testOwnerTeardownRetainsLeaseUntilPhysicalDisappearance() async throws {
        let promoCoordinator = ArbitratingNewTabPagePromoCoordinatorMock(promoCoordinationMode: .coordinated)
        messagesConfiguration.homeMessages = [.mockRemote(id: "message-a", withType: .small(titleText: "Title", descriptionText: "Body"))]
        let sut = createRenderableSUT(promoCoordinator: promoCoordinator)
        let mountID = try appearRemoteMessageGate(in: sut, expectedMessageID: "message-a")
        let session = try XCTUnwrap(try remoteRenderSession(in: sut))

        sut.tearDown()
        XCTAssertNotNil(promoCoordinator.arbiter.snapshot.visiblePromoIdentity)

        await waitForNextMainQueueTurn()
        XCTAssertNotNil(promoCoordinator.arbiter.snapshot.visiblePromoIdentity)

        sut.remoteMessageDidDisappear(renderSessionID: session.id, mountID: mountID)

        await waitForNextMainQueueTurn()

        XCTAssertNil(promoCoordinator.arbiter.snapshot.activeOwner)
        XCTAssertEqual(promoCoordinator.releaseCallCount, 1)
    }

    func testConfigurationRemovalClearsBlockedCandidateWithoutAppearanceAccounting() throws {
        let promoCoordinator = ArbitratingNewTabPagePromoCoordinatorMock(promoCoordinationMode: .coordinated)
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
        let promoCoordinator = ArbitratingNewTabPagePromoCoordinatorMock(promoCoordinationMode: .coordinated)
        promoCoordinator.acquireModalLease()
        messagesConfiguration.homeMessages = [.mockRemote(id: "message-a", withType: .small(titleText: "Title", descriptionText: "Body"))]
        let sut = createRenderableSUT(promoCoordinator: promoCoordinator)
        try appearRemoteMessageGate(in: sut, expectedMessageID: "message-a")
        let admissionCallCountBeforeRetry = promoCoordinator.publicAdmissionCallCount

        sut.retryRemoteMessageAdmission(using: promoCoordinator.admitRemoteMessage)

        XCTAssertEqual(promoCoordinator.publicAdmissionCallCount - admissionCallCountBeforeRetry, 1)
        XCTAssertNil(try remoteRenderSession(in: sut))
        XCTAssertTrue(promoCoordinator.arbiter.snapshot.hasModalLease)
    }

    func testRemovedAndReinsertedSameIDGetsNewSessionAndIgnoresStaleCallbacks() async throws {
        let promoCoordinator = ArbitratingNewTabPagePromoCoordinatorMock(promoCoordinationMode: .coordinated)
        messagesConfiguration.homeMessages = [.mockRemote(id: "message-a", withType: .small(titleText: "First", descriptionText: "Body"))]
        let sut = createRenderableSUT(promoCoordinator: promoCoordinator)
        let originalGate = try XCTUnwrap(try remoteMessageGate(in: sut))
        let originalMountID = UUID()
        sut.remoteMessageGateDidAppear(
            gateID: originalGate.id,
            messageID: originalGate.messageID,
            mountID: originalMountID
        )
        let originalSession = try XCTUnwrap(try remoteRenderSession(in: sut))
        sut.remoteMessageCardDidAppear(
            renderSessionID: originalSession.id,
            mountID: originalMountID
        )

        messagesConfiguration.homeMessages = []
        sut.refresh()
        sut.remoteMessageDidDisappear(
            renderSessionID: originalSession.id,
            mountID: originalMountID
        )
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
        sut.remoteMessageDidDisappear(
            renderSessionID: originalSession.id,
            mountID: originalMountID
        )

        await waitForNextMainQueueTurn()

        XCTAssertEqual(try remoteRenderSession(in: sut)?.id, replacementSession.id)
        XCTAssertNotNil(promoCoordinator.arbiter.snapshot.visiblePromoIdentity)
        XCTAssertEqual(promoCoordinator.releaseCallCount, 1)
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
        promoCoordinator: ArbitratingNewTabPagePromoCoordinatorMock? = nil,
        imageLoader: RemoteMessagingImageLoading? = nil,
        remoteMessageLifecycleObserver: ((NewTabPageRemoteMessageLifecycleEvent) -> Void)? = nil
    ) -> NewTabPageMessagesModel {
        // Built here rather than as a default argument: the mock is `@MainActor`, and default
        // argument expressions are evaluated in a nonisolated context.
        let promoCoordinator = promoCoordinator ?? ArbitratingNewTabPagePromoCoordinatorMock()
        let remoteMessageActionHandler = RemoteMessagingActionHandler(lastSearchStateRefresher: RemoteMessagingSurveyLastSearchStateRefresher())
        remoteMessageActionHandler.messageNavigator = DefaultMessageNavigator(delegate: self)

        let imageLoader = imageLoader ?? MockRemoteMessagingImageLoader()
        return NewTabPageMessagesModel(homePageMessagesConfiguration: messagesConfiguration,
                                notificationCenter: notificationCenter,
                                pixelFiring: PixelFiringMock.self,
                                messageActionHandler: remoteMessageActionHandler,
                                imageLoader: imageLoader,
                                promoCoordinator: promoCoordinator,
                                remoteMessageLifecycleObserver: remoteMessageLifecycleObserver,
                                isOpenedAfterIdle: { isOpenedAfterIdle })
    }

    private func createRenderableSUT(
        promoCoordinator: ArbitratingNewTabPagePromoCoordinatorMock
    ) -> NewTabPageMessagesModel {
        let sut = createSUT(promoCoordinator: promoCoordinator)
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
        if let renderSession = try remoteRenderSession(in: sut) {
            sut.remoteMessageCardDidAppear(
                renderSessionID: renderSession.id,
                mountID: mountID
            )
        }
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
private final class NewTabPageRemoteMessageGateHostState: ObservableObject {
    @Published var isGatePresented = true
}

private struct NewTabPageRemoteMessageGateHost: View {
    @ObservedObject var messagesModel: NewTabPageMessagesModel
    @ObservedObject var state: NewTabPageRemoteMessageGateHostState

    @ViewBuilder
    var body: some View {
        if state.isGatePresented, let gate = remoteMessageGate {
            NewTabPageRemoteMessageGateMountView(
                gate: gate,
                messagesModel: messagesModel,
                maximumWidth: 320
            )
        }
    }

    private var remoteMessageGate: NewTabPageRemoteMessageGate? {
        messagesModel.homeMessageRenderItems.lazy.compactMap { item in
            guard case .remoteMessageGate(let gate) = item.content else {
                return nil
            }
            return gate
        }.first
    }
}

@MainActor
private final class ArbitratingNewTabPagePromoCoordinatorMock: NewTabPagePromoCoordinating {
    var promoCoordinationMode: PromoCoordinationMode
    let arbiter = PromoQueueLeaseArbiter()
    private(set) weak var retryTarget: NewTabPagePromoRetrying?
    private(set) var registrationCount = 0
    private(set) var deregistrationCount = 0
    private(set) var publicAdmissionCallCount = 0
    private(set) var releaseCallCount = 0
    var onVisibleLeaseReleased: (() -> Void)?
    var onAdmissionAcquired: ((VisiblePromoIdentity) -> Void)?
    private var modalLease: PromoQueueModalLease?

    init(promoCoordinationMode: PromoCoordinationMode = .legacy) {
        self.promoCoordinationMode = promoCoordinationMode
    }

    func acquireModalLease() {
        guard case .acquired(let lease) = arbiter.acquireModalLease() else {
            XCTFail("Expected the mock modal lease to be acquired.")
            return
        }
        modalLease = lease
    }

    func admitRemoteMessage(_ identity: VisiblePromoIdentity) -> PromoQueueRemoteMessageAdmissionResult {
        publicAdmissionCallCount += 1
        switch promoCoordinationMode {
        case .legacy:
            return .deferred
        case .coordinated:
            break
        }

        switch arbiter.acquireVisiblePromoLease(for: identity) {
        case .acquired(let lease):
            onAdmissionAcquired?(identity)
            return .acquired(PromoQueueRemoteMessageAdmission { [weak self, lease] in
                guard lease.release() else {
                    return
                }
                self?.releaseCallCount += 1
                self?.onVisibleLeaseReleased?()
            })
        case .blockedByModal, .blockedByVisiblePromo:
            return .deferred
        }
    }

    func registerRemoteMessageRetry(
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

private final class AdmissionOrderingImageLoader: RemoteMessagingImageLoading {
    enum Event: Equatable {
        case admissionAcquired
        case cachedImageRequested
    }

    private(set) var events = [Event]()

    func recordAdmissionAcquired() {
        events.append(.admissionAcquired)
    }

    func prefetch(_ urls: [URL]) {}

    func cachedImage(for url: URL) -> RemoteMessagingImage? {
        events.append(.cachedImageRequested)
        return nil
    }

    func loadImage(from url: URL) async throws -> RemoteMessagingImage {
        throw RemoteMessagingImageLoadingError.invalidImageData
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

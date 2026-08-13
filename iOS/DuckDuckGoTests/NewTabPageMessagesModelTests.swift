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

    // MARK: - Loading And Legacy Rendering

    func testUpdatesOnNotification() {
        let sut = createSUT()
        sut.load()

        XCTAssertTrue(sut.homeMessageViewModels.isEmpty)

        messagesConfiguration.homeMessages = [.placeholder]
        notificationCenter.post(
            name: RemoteMessagingStore.Notifications.remoteMessagesDidChange,
            object: nil
        )

        XCTAssertEqual(sut.homeMessageViewModels.count, 1)
    }

    func testWhenCoordinatedThenLoadIsIdempotentAndTearDownRemovesObserverAndRegistration() {
        let promoCoordinator = RendererCoordinatorMock(promoCoordinationMode: .coordinated)
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
    }

    func testWhenLegacyThenModelNeverRegistersRenderer() {
        let promoCoordinator = RendererCoordinatorMock(promoCoordinationMode: .legacy)
        let sut = createSUT(promoCoordinator: promoCoordinator)

        sut.load()
        sut.setSurfaceAttachmentProvider { true }
        sut.setSurfaceLifecycleReady(true)
        sut.refresh()
        sut.tearDown()

        XCTAssertEqual(promoCoordinator.registrationCount, 0)
        XCTAssertTrue(promoCoordinator.updates.isEmpty)
        XCTAssertEqual(promoCoordinator.deregistrationCount, 0)
    }

    func testFeatureOffRecordsLegacyAppearanceEagerlyThenAgainWhenVisible() throws {
        let promoCoordinator = RendererCoordinatorMock(promoCoordinationMode: .legacy)
        let message = HomeMessage.mockRemote(
            id: "message-a",
            withType: .small(titleText: "Title", descriptionText: "Body")
        )
        messagesConfiguration.homeMessages = [message]
        let sut = createSUT(promoCoordinator: promoCoordinator)

        sut.load()

        let viewModel = try XCTUnwrap(sut.homeMessageViewModels.first)
        XCTAssertEqual(messagesConfiguration.appearanceCallCount, 1)
        XCTAssertEqual(messagesConfiguration.lastAppearedHomeMessage, message)
        XCTAssertEqual(promoCoordinator.registrationCount, 0)

        viewModel.onDidAppear()

        XCTAssertEqual(messagesConfiguration.appearanceCallCount, 2)
        XCTAssertEqual(messagesConfiguration.lastAppearedHomeMessage, message)
        XCTAssertEqual(promoCoordinator.registrationCount, 0)
    }

    func testFeatureOffMapsEveryMessageDirectlyInInputOrder() {
        let promoCoordinator = RendererCoordinatorMock(promoCoordinationMode: .legacy)
        let message = HomeMessage.mockRemote(
            id: "message-a",
            withType: .small(titleText: "Title", descriptionText: "Body")
        )
        messagesConfiguration.homeMessages = [.placeholder, message]
        let sut = createSUT(promoCoordinator: promoCoordinator)

        sut.load()

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

    // MARK: - Coordinated Renderer Reporting

    func testWhenCoordinatedThenRegistrationUsesStableSurfaceIDAndReportsCandidateAndLocalReadiness() {
        let surfaceID = UUID()
        let promoCoordinator = RendererCoordinatorMock(promoCoordinationMode: .coordinated)
        messagesConfiguration.homeMessages = [
            .mockRemote(id: "message-a", withType: .small(titleText: "Title", descriptionText: "Body")),
        ]
        var isAttached = false
        let sut = createSUT(surfaceID: surfaceID, promoCoordinator: promoCoordinator)
        sut.setSurfaceAttachmentProvider { isAttached }

        sut.load()

        XCTAssertEqual(promoCoordinator.registeredRendererID, surfaceID)
        XCTAssertTrue(promoCoordinator.rendererTarget === sut)
        XCTAssertEqual(
            promoCoordinator.updates.last,
            RendererUpdate(candidate: .available(messageID: "message-a"), isLocallyReady: false)
        )
        XCTAssertTrue(sut.homeMessageViewModels.isEmpty)

        isAttached = true
        sut.setSurfaceAttachmentProvider { isAttached }
        XCTAssertEqual(promoCoordinator.updates.last?.isLocallyReady, false)

        sut.setSurfaceLifecycleReady(true)
        XCTAssertEqual(
            promoCoordinator.updates.last,
            RendererUpdate(candidate: .available(messageID: "message-a"), isLocallyReady: true)
        )

        sut.setSurfaceLifecycleReady(false)
        XCTAssertEqual(
            promoCoordinator.updates.last,
            RendererUpdate(candidate: .available(messageID: "message-a"), isLocallyReady: false)
        )

        messagesConfiguration.homeMessages = []
        sut.refresh()
        XCTAssertEqual(
            promoCoordinator.updates.last,
            RendererUpdate(candidate: .none, isLocallyReady: false)
        )
    }

    func testWhenCoordinatedCandidateExistsThenNothingIsBuiltOrPublishedBeforeAuthorization() {
        let promoCoordinator = RendererCoordinatorMock(promoCoordinationMode: .coordinated)
        let imageLoader = MockRemoteMessagingImageLoader()
        let imageURL = URL(string: "https://example.com/image.png")!
        messagesConfiguration.homeMessages = [
            .mockRemote(
                id: "message-a",
                withType: .medium(
                    titleText: "Title",
                    descriptionText: "Body",
                    placeholder: .announce,
                    imageUrl: imageURL
                )
            ),
        ]
        let sut = createRenderableSUT(promoCoordinator: promoCoordinator, imageLoader: imageLoader)

        XCTAssertTrue(sut.homeMessageRenderItems.isEmpty)
        XCTAssertTrue(sut.homeMessageViewModels.isEmpty)
        XCTAssertNil(imageLoader.cachedImageCalledWithUrl)

        let presentation = makePresentation(messageID: "message-a")
        XCTAssertTrue(sut.showRemoteMessage(presentation))

        XCTAssertEqual(imageLoader.cachedImageCalledWithUrl, imageURL)
        XCTAssertEqual(coordinatedRenderSession(in: sut)?.presentation, presentation)
        XCTAssertEqual(sut.homeMessageViewModels.map(\.messageId), ["message-a"])
        XCTAssertNil(messagesConfiguration.lastAppearedHomeMessage)
    }

    func testWhenCoordinatedSnapshotContainsDuplicateRemoteMessageIDsThenAuthorizationPublishesOnePresentation() {
        let promoCoordinator = RendererCoordinatorMock(promoCoordinationMode: .coordinated)
        messagesConfiguration.homeMessages = [
            .mockRemote(id: "message-a", withType: .small(titleText: "First", descriptionText: "Body")),
            .mockRemote(id: "message-a", withType: .small(titleText: "Duplicate", descriptionText: "Body")),
        ]
        let sut = createRenderableSUT(promoCoordinator: promoCoordinator)
        let presentation = makePresentation(messageID: "message-a")

        XCTAssertTrue(sut.showRemoteMessage(presentation))

        let coordinatedPresentations = sut.homeMessageRenderItems.compactMap { item -> PromoQueueRemoteMessagePresentation? in
            guard case .coordinatedRemoteMessage(let renderSession) = item.content else {
                return nil
            }
            return renderSession.presentation
        }
        XCTAssertEqual(sut.homeMessageRenderItems.count, 1)
        XCTAssertEqual(coordinatedPresentations, [presentation])
        XCTAssertEqual(sut.homeMessageViewModels.map(\.messageId), ["message-a"])
    }

    func testShowRejectsStaleCandidateWithoutPublishingContent() {
        let promoCoordinator = RendererCoordinatorMock(promoCoordinationMode: .coordinated)
        messagesConfiguration.homeMessages = [
            .mockRemote(id: "message-a", withType: .small(titleText: "Title", descriptionText: "Body")),
        ]
        let sut = createRenderableSUT(promoCoordinator: promoCoordinator)

        let stalePresentation = makePresentation(messageID: "message-b")

        XCTAssertFalse(sut.showRemoteMessage(stalePresentation))
        XCTAssertTrue(sut.homeMessageRenderItems.isEmpty)
        XCTAssertNil(messagesConfiguration.lastAppearedHomeMessage)
    }

    func testShowRejectsUnrenderableCandidateWithoutPublishingContent() {
        let promoCoordinator = RendererCoordinatorMock(promoCoordinationMode: .coordinated)
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
            ),
        ]
        let sut = createRenderableSUT(promoCoordinator: promoCoordinator)

        XCTAssertFalse(sut.showRemoteMessage(makePresentation(messageID: "message-a")))
        XCTAssertTrue(sut.homeMessageRenderItems.isEmpty)
        XCTAssertNil(messagesConfiguration.lastAppearedHomeMessage)
    }

    // MARK: - Coordinated Appearance

    func testAcceptedAppearanceIsConfirmedBeforeOrdinaryAccounting() throws {
        let promoCoordinator = RendererCoordinatorMock(promoCoordinationMode: .coordinated)
        promoCoordinator.appearanceResults = [.accepted, .rejected]
        var confirmationCallCount = 0
        promoCoordinator.onConfirmAppearance = { [unowned self] in
            if confirmationCallCount == 0 {
                XCTAssertEqual(messagesConfiguration.appearanceCallCount, 0)
            }
            confirmationCallCount += 1
        }
        let message = HomeMessage.mockRemote(
            id: "message-a",
            withType: .small(titleText: "Title", descriptionText: "Body")
        )
        messagesConfiguration.homeMessages = [message]
        let sut = createRenderableSUT(promoCoordinator: promoCoordinator)
        let presentation = makePresentation(messageID: "message-a")
        XCTAssertTrue(sut.showRemoteMessage(presentation))
        let viewModel = try XCTUnwrap(coordinatedRenderSession(in: sut)?.viewModel)

        viewModel.onDidAppear()

        XCTAssertEqual(
            promoCoordinator.appearanceCalls,
            [AppearanceCall(
                sessionID: presentation.session.id,
                presentationID: presentation.id,
                isAttachedToWindow: true
            )]
        )
        XCTAssertEqual(messagesConfiguration.appearanceCallCount, 1)
        XCTAssertEqual(messagesConfiguration.lastAppearedHomeMessage, message)

        viewModel.onDidAppear()

        XCTAssertEqual(promoCoordinator.appearanceCalls.count, 2)
        XCTAssertEqual(messagesConfiguration.appearanceCallCount, 1)
    }

    func testRejectedAppearanceDoesNotRunOrdinaryAccounting() throws {
        let promoCoordinator = RendererCoordinatorMock(promoCoordinationMode: .coordinated)
        promoCoordinator.appearanceResults = [.rejected]
        messagesConfiguration.homeMessages = [
            .mockRemote(id: "message-a", withType: .small(titleText: "Title", descriptionText: "Body")),
        ]
        let sut = createRenderableSUT(promoCoordinator: promoCoordinator)
        XCTAssertTrue(sut.showRemoteMessage(makePresentation(messageID: "message-a")))

        try XCTUnwrap(coordinatedRenderSession(in: sut)?.viewModel).onDidAppear()

        XCTAssertEqual(promoCoordinator.appearanceCalls.count, 1)
        XCTAssertEqual(messagesConfiguration.appearanceCallCount, 0)
    }

    func testAppearanceFromWithdrawnPresentationIsIgnored() throws {
        let promoCoordinator = RendererCoordinatorMock(promoCoordinationMode: .coordinated)
        messagesConfiguration.homeMessages = [
            .mockRemote(id: "message-a", withType: .small(titleText: "Title", descriptionText: "Body")),
        ]
        let sut = createRenderableSUT(
            promoCoordinator: promoCoordinator,
            remoteMessageRemovalPath: .synchronousSourceClear
        )
        let presentation = makePresentation(messageID: "message-a")
        XCTAssertTrue(sut.showRemoteMessage(presentation))
        let staleViewModel = try XCTUnwrap(coordinatedRenderSession(in: sut)?.viewModel)

        sut.hideRemoteMessage(presentation, removalID: UUID())
        staleViewModel.onDidAppear()

        XCTAssertTrue(promoCoordinator.appearanceCalls.isEmpty)
        XCTAssertEqual(messagesConfiguration.appearanceCallCount, 0)
    }

    // MARK: - Candidate Refresh

    func testSameIDPayloadUpdatePreservesPresentationAndRebuildsViewModel() throws {
        let promoCoordinator = RendererCoordinatorMock(promoCoordinationMode: .coordinated)
        messagesConfiguration.homeMessages = [
            .mockRemote(id: "message-a", withType: .small(titleText: "First", descriptionText: "Body")),
        ]
        let sut = createRenderableSUT(promoCoordinator: promoCoordinator)
        let presentation = makePresentation(messageID: "message-a")
        XCTAssertTrue(sut.showRemoteMessage(presentation))
        XCTAssertEqual(coordinatedRenderSession(in: sut)?.viewModel.title, "First")

        messagesConfiguration.homeMessages = [
            .mockRemote(id: "message-a", withType: .small(titleText: "Second", descriptionText: "Updated")),
        ]
        sut.refresh()

        let updatedSession = try XCTUnwrap(coordinatedRenderSession(in: sut))
        XCTAssertEqual(updatedSession.presentation, presentation)
        XCTAssertEqual(updatedSession.viewModel.title, "Second")
        XCTAssertEqual(
            promoCoordinator.updates.last,
            RendererUpdate(candidate: .available(messageID: "message-a"), isLocallyReady: true)
        )
    }

    func testSameIDRebuildFailureRetainsAuthorizedContentAndReportsUnrenderableCandidate() throws {
        let promoCoordinator = RendererCoordinatorMock(promoCoordinationMode: .coordinated)
        messagesConfiguration.homeMessages = [
            .mockRemote(id: "message-a", withType: .small(titleText: "Original", descriptionText: "Body")),
        ]
        let sut = createRenderableSUT(promoCoordinator: promoCoordinator)
        let presentation = makePresentation(messageID: "message-a")
        XCTAssertTrue(sut.showRemoteMessage(presentation))

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
            ),
        ]
        sut.refresh()

        let retainedSession = try XCTUnwrap(coordinatedRenderSession(in: sut))
        XCTAssertEqual(retainedSession.presentation, presentation)
        XCTAssertEqual(retainedSession.viewModel.title, "Original")
        XCTAssertEqual(
            promoCoordinator.updates.last,
            RendererUpdate(candidate: .unrenderable(messageID: "message-a"), isLocallyReady: true)
        )
    }

    func testCandidateRemovalRetainsAuthorizedContentUntilServiceIssuedHide() throws {
        let promoCoordinator = RendererCoordinatorMock(promoCoordinationMode: .coordinated)
        messagesConfiguration.homeMessages = [
            .mockRemote(id: "message-a", withType: .small(titleText: "Title", descriptionText: "Body")),
        ]
        let sut = createRenderableSUT(
            promoCoordinator: promoCoordinator,
            remoteMessageRemovalPath: .synchronousSourceClear
        )
        let presentation = makePresentation(messageID: "message-a")
        XCTAssertTrue(sut.showRemoteMessage(presentation))

        messagesConfiguration.homeMessages = []
        sut.refresh()

        XCTAssertEqual(coordinatedRenderSession(in: sut)?.presentation, presentation)
        XCTAssertEqual(
            promoCoordinator.updates.last,
            RendererUpdate(candidate: .none, isLocallyReady: true)
        )

        sut.hideRemoteMessage(presentation, removalID: UUID())
        XCTAssertNil(coordinatedRenderSession(in: sut))
    }

    func testDifferentCandidateRetainsOldPresentationUntilServiceIssuedHide() throws {
        let promoCoordinator = RendererCoordinatorMock(promoCoordinationMode: .coordinated)
        messagesConfiguration.homeMessages = [
            .mockRemote(id: "message-a", withType: .small(titleText: "First", descriptionText: "Body")),
        ]
        let sut = createRenderableSUT(
            promoCoordinator: promoCoordinator,
            remoteMessageRemovalPath: .synchronousSourceClear
        )
        let presentation = makePresentation(messageID: "message-a")
        XCTAssertTrue(sut.showRemoteMessage(presentation))

        messagesConfiguration.homeMessages = [
            .mockRemote(id: "message-b", withType: .small(titleText: "Second", descriptionText: "Body")),
        ]
        sut.refresh()

        XCTAssertEqual(coordinatedRenderSession(in: sut)?.presentation, presentation)
        XCTAssertEqual(
            promoCoordinator.updates.last,
            RendererUpdate(candidate: .available(messageID: "message-b"), isLocallyReady: true)
        )

        sut.hideRemoteMessage(presentation, removalID: UUID())
        XCTAssertNil(coordinatedRenderSession(in: sut))
    }

    // MARK: - Removal And Teardown

    func testSynchronousRemovalClearsExactSourceAndReportsExactTerminalOnce() throws {
        let promoCoordinator = RendererCoordinatorMock(promoCoordinationMode: .coordinated)
        messagesConfiguration.homeMessages = [
            .mockRemote(id: "message-a", withType: .small(titleText: "Title", descriptionText: "Body")),
        ]
        let sut = createRenderableSUT(
            promoCoordinator: promoCoordinator,
            remoteMessageRemovalPath: .synchronousSourceClear
        )
        let presentation = makePresentation(messageID: "message-a")
        let removalID = UUID()
        XCTAssertTrue(sut.showRemoteMessage(presentation))

        sut.hideRemoteMessage(presentation, removalID: removalID)

        XCTAssertNil(coordinatedRenderSession(in: sut))
        XCTAssertEqual(
            promoCoordinator.removalCalls,
            [RemovalCall(
                sessionID: presentation.session.id,
                presentationID: presentation.id,
                removalID: removalID,
                terminal: .sourceRemovedWithoutAnimation
            )]
        )

        sut.hideRemoteMessage(presentation, removalID: removalID)
        sut.remoteMessageHostDidDetach()

        XCTAssertEqual(promoCoordinator.removalCalls.count, 1)
    }

    func testWhenAutomaticRemovalRunsOnIOS17ThenExactAnimationTerminalPrecedesServiceSettlement() async throws {
        guard #available(iOS 17, *) else {
            throw XCTSkip("Native SwiftUI removed-completion is available on iOS 17 and later")
        }

        let promoCoordinator = RendererCoordinatorMock(promoCoordinationMode: .coordinated)
        messagesConfiguration.homeMessages = [
            .mockRemote(id: "message-a", withType: .small(titleText: "Title", descriptionText: "Body")),
        ]
        let sut = createSUT(promoCoordinator: promoCoordinator)
        let probe = RemoteMessageWindowAttachmentProbe()
        let mountedHost = mountRemoteMessageRenderHost(model: sut, probe: probe)
        defer {
            sut.tearDown()
            mountedHost.window.rootViewController = UIViewController()
            sut.remoteMessageHostDidDetach()
            mountedHost.window.isHidden = true
        }
        let presentation = makePresentation(messageID: "message-a")
        let removalID = UUID()
        let didAttach = expectation(description: "The authorized remote message attached to the test window")
        let didDetach = expectation(description: "The outgoing remote message detached from the test window")
        let didObserveRemovalTransaction = expectation(description: "The mounted host observed the native removal transaction")
        let didReachTerminal = expectation(description: "Native removal reached its exact terminal")
        let didReachSettlement = expectation(description: "The outgoing view detached before service settlement")
        var lifecycleEvents = [RemoteMessageRemovalLifecycleEvent]()
        var wasSourceClearedAtTerminal = false
        var wasProbeDetachedAtSettlement = false
        probe.onAttachmentChanged = { isAttached in
            lifecycleEvents.append(isAttached ? .attached : .detached)
            if isAttached {
                didAttach.fulfill()
            } else {
                didDetach.fulfill()
            }
        }
        probe.onRemovalTransaction = {
            didObserveRemovalTransaction.fulfill()
        }
        promoCoordinator.onRemovalTerminal = { call in
            lifecycleEvents.append(.terminal(call.terminal))
            wasSourceClearedAtTerminal = self.coordinatedRenderSession(in: sut) == nil
            didReachTerminal.fulfill()
            DispatchQueue.main.async {
                wasProbeDetachedAtSettlement = !probe.isAttachedToWindow
                lifecycleEvents.append(.settlement)
                didReachSettlement.fulfill()
            }
        }

        sut.load()
        promoCoordinator.setSelectedRemoteMessageRendererID(sut.surfaceID)
        sut.setSurfaceLifecycleReady(true)
        XCTAssertTrue(sut.showRemoteMessage(presentation))
        await fulfillment(of: [didAttach], timeout: 1)

        XCTAssertTrue(sut.usesAnimatedRemoteMessageRemoval)
        XCTAssertTrue(probe.isAttachedToWindow)

        sut.hideRemoteMessage(presentation, removalID: removalID)

        XCTAssertNil(coordinatedRenderSession(in: sut))
        XCTAssertTrue(probe.isAttachedToWindow, "The transition tail must remain physically attached until SwiftUI reports .removed")
        XCTAssertTrue(promoCoordinator.removalCalls.isEmpty)

        await fulfillment(of: [didObserveRemovalTransaction, didDetach, didReachTerminal, didReachSettlement], timeout: 2)

        XCTAssertTrue(wasSourceClearedAtTerminal)
        XCTAssertTrue(wasProbeDetachedAtSettlement)
        XCTAssertEqual(
            probe.removalTransaction,
            RemoteMessageRemovalTransaction(hasAnimation: true, disablesAnimations: false)
        )
        XCTAssertEqual(
            promoCoordinator.removalCalls,
            [RemovalCall(
                sessionID: presentation.session.id,
                presentationID: presentation.id,
                removalID: removalID,
                terminal: .animationCompleted
            )]
        )
        let detachedEventIndex = try XCTUnwrap(lifecycleEvents.firstIndex(of: .detached))
        let terminalEventIndex = try XCTUnwrap(lifecycleEvents.firstIndex(of: .terminal(.animationCompleted)))
        let settlementEventIndex = try XCTUnwrap(lifecycleEvents.firstIndex(of: .settlement))
        XCTAssertLessThan(terminalEventIndex, settlementEventIndex)
        XCTAssertLessThan(detachedEventIndex, settlementEventIndex)
    }

    func testWhenSynchronousSourceClearIsInjectedThenMountedSourceDisappearsWithoutWaitingForAnimationTerminal() async throws {
        let promoCoordinator = RendererCoordinatorMock(promoCoordinationMode: .coordinated)
        messagesConfiguration.homeMessages = [
            .mockRemote(id: "message-a", withType: .small(titleText: "Title", descriptionText: "Body")),
        ]
        let sut = createSUT(
            promoCoordinator: promoCoordinator,
            remoteMessageRemovalPath: .synchronousSourceClear
        )
        let probe = RemoteMessageWindowAttachmentProbe()
        let mountedHost = mountRemoteMessageRenderHost(model: sut, probe: probe)
        defer {
            sut.tearDown()
            mountedHost.window.rootViewController = UIViewController()
            sut.remoteMessageHostDidDetach()
            mountedHost.window.isHidden = true
        }
        let presentation = makePresentation(messageID: "message-a")
        let removalID = UUID()
        let didAttach = expectation(description: "The authorized remote message attached to the test window")
        let didDetach = expectation(description: "The synchronously cleared remote message detached from the test window")
        let didObserveRemovalTransaction = expectation(description: "The mounted host observed the synchronous removal transaction")
        var wasSourceClearedAtTerminal = false
        probe.onAttachmentChanged = { isAttached in
            if isAttached {
                didAttach.fulfill()
            } else {
                didDetach.fulfill()
            }
        }
        probe.onRemovalTransaction = {
            didObserveRemovalTransaction.fulfill()
        }
        promoCoordinator.onRemovalTerminal = { _ in
            wasSourceClearedAtTerminal = self.coordinatedRenderSession(in: sut) == nil
        }

        sut.load()
        promoCoordinator.setSelectedRemoteMessageRendererID(sut.surfaceID)
        sut.setSurfaceLifecycleReady(true)
        XCTAssertTrue(sut.showRemoteMessage(presentation))
        await fulfillment(of: [didAttach], timeout: 1)

        XCTAssertFalse(sut.usesAnimatedRemoteMessageRemoval)
        XCTAssertTrue(probe.isAttachedToWindow)

        sut.hideRemoteMessage(presentation, removalID: removalID)

        XCTAssertNil(coordinatedRenderSession(in: sut))
        XCTAssertTrue(wasSourceClearedAtTerminal)
        XCTAssertEqual(
            promoCoordinator.removalCalls,
            [RemovalCall(
                sessionID: presentation.session.id,
                presentationID: presentation.id,
                removalID: removalID,
                terminal: .sourceRemovedWithoutAnimation
            )]
        )

        await fulfillment(of: [didObserveRemovalTransaction, didDetach], timeout: 1)
        XCTAssertFalse(probe.isAttachedToWindow)
        XCTAssertEqual(
            probe.removalTransaction,
            RemoteMessageRemovalTransaction(hasAnimation: false, disablesAnimations: true)
        )
        XCTAssertEqual(promoCoordinator.removalCalls.count, 1)
    }

    func testStaleHideDoesNotWithdrawCurrentPresentationOrReportTerminal() throws {
        let promoCoordinator = RendererCoordinatorMock(promoCoordinationMode: .coordinated)
        messagesConfiguration.homeMessages = [
            .mockRemote(id: "message-a", withType: .small(titleText: "Title", descriptionText: "Body")),
        ]
        let sut = createRenderableSUT(
            promoCoordinator: promoCoordinator,
            remoteMessageRemovalPath: .synchronousSourceClear
        )
        let presentation = makePresentation(messageID: "message-a")
        XCTAssertTrue(sut.showRemoteMessage(presentation))

        sut.hideRemoteMessage(makePresentation(messageID: "message-a"), removalID: UUID())

        XCTAssertEqual(coordinatedRenderSession(in: sut)?.presentation, presentation)
        XCTAssertTrue(promoCoordinator.removalCalls.isEmpty)
    }

    func testTearDownReportsNotLocallyReadyBeforeDeregisterAndRetainsAuthorizedPresentation() throws {
        let promoCoordinator = RendererCoordinatorMock(promoCoordinationMode: .coordinated)
        messagesConfiguration.homeMessages = [
            .mockRemote(id: "message-a", withType: .small(titleText: "Title", descriptionText: "Body")),
        ]
        let sut = createRenderableSUT(promoCoordinator: promoCoordinator)
        let presentation = makePresentation(messageID: "message-a")
        XCTAssertTrue(sut.showRemoteMessage(presentation))

        sut.tearDown()

        XCTAssertEqual(
            promoCoordinator.updates.last,
            RendererUpdate(candidate: .available(messageID: "message-a"), isLocallyReady: false)
        )
        XCTAssertEqual(promoCoordinator.deregistrationCount, 1)
        XCTAssertEqual(coordinatedRenderSession(in: sut)?.presentation, presentation)
    }

    func testTornDownRendererCanReportVerifiedHostDetachmentAfterDeregistration() throws {
        let promoCoordinator = RendererCoordinatorMock(promoCoordinationMode: .coordinated)
        messagesConfiguration.homeMessages = [
            .mockRemote(id: "message-a", withType: .small(titleText: "Title", descriptionText: "Body")),
        ]
        var isAttached = true
        let sut = createSUT(promoCoordinator: promoCoordinator)
        sut.setSurfaceAttachmentProvider { isAttached }
        sut.load()
        promoCoordinator.setSelectedRemoteMessageRendererID(sut.surfaceID)
        sut.setSurfaceLifecycleReady(true)
        let presentation = makePresentation(messageID: "message-a")
        let removalID = UUID()
        XCTAssertTrue(sut.showRemoteMessage(presentation))

        sut.tearDown()
        isAttached = false
        sut.hideRemoteMessage(presentation, removalID: removalID)

        XCTAssertNil(coordinatedRenderSession(in: sut))
        XCTAssertEqual(promoCoordinator.deregistrationCount, 1)
        XCTAssertEqual(
            promoCoordinator.removalCalls,
            [RemovalCall(
                sessionID: presentation.session.id,
                presentationID: presentation.id,
                removalID: removalID,
                terminal: .hostDetached
            )]
        )

        sut.remoteMessageHostDidDetach()
        XCTAssertEqual(promoCoordinator.removalCalls.count, 1)
    }

    // MARK: - Callbacks

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

    func testMessageNavigator() {
        func assertSegueCount(_ count: Int) {
            XCTAssertEqual(segueToSettingsCallCount, count)
            XCTAssertEqual(segueToSettingsGeneralCallCount, count)
            XCTAssertEqual(segueToAIChatSettingsCallCount, count)
            XCTAssertEqual(segueToFeedbackCallCount, count)
            XCTAssertEqual(segueToSettingsAppearanceCallCount, count)
            XCTAssertEqual(segueToPIRCallCount, count)
        }

        assertSegueCount(0)

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

        assertSegueCount(1)
    }

    // MARK: - Pixels

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

    // MARK: - Opened After Idle

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
        surfaceID: UUID = UUID(),
        isOpenedAfterIdle: Bool = false,
        promoCoordinator: RendererCoordinatorMock? = nil,
        imageLoader: RemoteMessagingImageLoading? = nil,
        remoteMessageRemovalPath: NewTabPageRemoteMessageRemovalPath = .automatic
    ) -> NewTabPageMessagesModel {
        let promoCoordinator = promoCoordinator ?? RendererCoordinatorMock()
        let remoteMessageActionHandler = RemoteMessagingActionHandler(
            lastSearchStateRefresher: RemoteMessagingSurveyLastSearchStateRefresher()
        )
        remoteMessageActionHandler.messageNavigator = DefaultMessageNavigator(delegate: self)

        return NewTabPageMessagesModel(
            homePageMessagesConfiguration: messagesConfiguration,
            surfaceID: surfaceID,
            notificationCenter: notificationCenter,
            pixelFiring: PixelFiringMock.self,
            messageActionHandler: remoteMessageActionHandler,
            imageLoader: imageLoader ?? MockRemoteMessagingImageLoader(),
            promoCoordinator: promoCoordinator,
            remoteMessageRemovalPath: remoteMessageRemovalPath,
            isOpenedAfterIdle: { isOpenedAfterIdle }
        )
    }

    private func createRenderableSUT(
        promoCoordinator: RendererCoordinatorMock,
        imageLoader: RemoteMessagingImageLoading? = nil,
        remoteMessageRemovalPath: NewTabPageRemoteMessageRemovalPath = .automatic
    ) -> NewTabPageMessagesModel {
        let sut = createSUT(
            promoCoordinator: promoCoordinator,
            imageLoader: imageLoader,
            remoteMessageRemovalPath: remoteMessageRemovalPath
        )
        sut.setSurfaceAttachmentProvider { true }
        sut.load()
        promoCoordinator.setSelectedRemoteMessageRendererID(sut.surfaceID)
        sut.setSurfaceLifecycleReady(true)
        XCTAssertEqual(promoCoordinator.selectedRendererID, sut.surfaceID)
        return sut
    }

    private func coordinatedRenderSession(
        in sut: NewTabPageMessagesModel
    ) -> NewTabPageRemoteMessageRenderSession? {
        for item in sut.homeMessageRenderItems {
            if case .coordinatedRemoteMessage(let renderSession) = item.content {
                return renderSession
            }
        }
        return nil
    }

    private func makePresentation(messageID: String) -> PromoQueueRemoteMessagePresentation {
        PromoQueueRemoteMessagePresentation(
            id: UUID(),
            session: PromoQueueRemoteMessageSession(id: UUID(), messageID: messageID)
        )
    }

    private func mountRemoteMessageRenderHost(
        model: NewTabPageMessagesModel,
        probe: RemoteMessageWindowAttachmentProbe
    ) -> (window: UIWindow, hostingController: UIHostingController<RemoteMessageRenderTestHost>) {
        let hostingController = UIHostingController(
            rootView: RemoteMessageRenderTestHost(model: model, probe: probe)
        )
        let window: UIWindow
        if let windowScene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: windowScene)
            window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        } else {
            window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        }
        window.rootViewController = hostingController
        window.makeKeyAndVisible()
        hostingController.view.layoutIfNeeded()
        model.setSurfaceAttachmentProvider { [weak hostingController] in
            hostingController?.viewIfLoaded?.window != nil
        }
        return (window, hostingController)
    }
}

private struct RendererUpdate: Equatable {
    let candidate: PromoQueueRemoteMessageCandidateState
    let isLocallyReady: Bool
}

private struct AppearanceCall: Equatable {
    let sessionID: UUID
    let presentationID: UUID
    let isAttachedToWindow: Bool
}

private struct RemovalCall: Equatable {
    let sessionID: UUID
    let presentationID: UUID
    let removalID: UUID
    let terminal: PromoQueueRemoteMessageRemovalTerminal
}

private enum RemoteMessageRemovalLifecycleEvent: Equatable {
    case attached
    case detached
    case terminal(PromoQueueRemoteMessageRemovalTerminal)
    case settlement
}

private struct RemoteMessageRenderTestHost: View {
    @ObservedObject var model: NewTabPageMessagesModel
    let probe: RemoteMessageWindowAttachmentProbe

    var body: some View {
        VStack {
            ForEach(model.homeMessageRenderItems) { item in
                switch item.content {
                case .message:
                    EmptyView()
                case .coordinatedRemoteMessage(let renderSession):
                    RemoteMessageWindowAttachmentProbeView(probe: probe)
                        .frame(width: 120, height: 80)
                        .transition(remoteMessageTransition)
                        .id(renderSession.presentation.id)
                }
            }
        }
        .background(RemoteMessageRemovalTransactionProbeView(
            presentationIDs: coordinatedPresentationIDs,
            probe: probe
        ))
    }

    private var coordinatedPresentationIDs: [UUID] {
        model.homeMessageRenderItems.compactMap { item in
            guard case .coordinatedRemoteMessage(let renderSession) = item.content else {
                return nil
            }
            return renderSession.presentation.id
        }
    }

    private var remoteMessageTransition: AnyTransition {
        NewTabPageRemoteMessageTransition.make(
            usesAnimatedRemoval: model.usesAnimatedRemoteMessageRemoval
        )
    }
}

private struct RemoteMessageRemovalTransaction: Equatable {
    let hasAnimation: Bool
    let disablesAnimations: Bool
}

@MainActor
private final class RemoteMessageWindowAttachmentProbe {
    private weak var observedView: UIView?
    private(set) var isAttachedToWindow = false
    private(set) var removalTransaction: RemoteMessageRemovalTransaction?
    var onAttachmentChanged: ((Bool) -> Void)?
    var onRemovalTransaction: (() -> Void)?
    private var previousPresentationIDs = Set<UUID>()

    func observe(_ view: UIView) {
        observedView = view
        updateAttachmentState(for: view)
    }

    func windowDidChange(for view: UIView) {
        guard observedView === view else {
            return
        }
        updateAttachmentState(for: view)
    }

    func recordRemovalTransaction(presentationIDs: [UUID], transaction: Transaction) {
        let currentPresentationIDs = Set(presentationIDs)
        defer {
            previousPresentationIDs = currentPresentationIDs
        }
        guard !previousPresentationIDs.isEmpty,
              currentPresentationIDs.isEmpty,
              removalTransaction == nil else {
            return
        }

        removalTransaction = RemoteMessageRemovalTransaction(
            hasAnimation: transaction.animation != nil,
            disablesAnimations: transaction.disablesAnimations
        )
        onRemovalTransaction?()
    }

    private func updateAttachmentState(for view: UIView) {
        let newValue = view.window != nil
        guard isAttachedToWindow != newValue else {
            return
        }
        isAttachedToWindow = newValue
        onAttachmentChanged?(newValue)
    }
}

private struct RemoteMessageRemovalTransactionProbeView: UIViewRepresentable {
    let presentationIDs: [UUID]
    let probe: RemoteMessageWindowAttachmentProbe

    func makeUIView(context: Context) -> UIView {
        UIView(frame: .zero)
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        probe.recordRemovalTransaction(
            presentationIDs: presentationIDs,
            transaction: context.transaction
        )
    }
}

private struct RemoteMessageWindowAttachmentProbeView: UIViewRepresentable {
    let probe: RemoteMessageWindowAttachmentProbe

    func makeUIView(context: Context) -> RemoteMessageWindowAttachmentProbeUIView {
        let view = RemoteMessageWindowAttachmentProbeUIView()
        view.onWindowChanged = { [weak probe, weak view] in
            guard let view else {
                return
            }
            probe?.windowDidChange(for: view)
        }
        probe.observe(view)
        return view
    }

    func updateUIView(_ uiView: RemoteMessageWindowAttachmentProbeUIView, context: Context) {
        probe.observe(uiView)
    }
}

private final class RemoteMessageWindowAttachmentProbeUIView: UIView {
    var onWindowChanged: (() -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onWindowChanged?()
    }
}

@MainActor
private final class RendererCoordinatorMock: NewTabPagePromoCoordinating {
    let promoCoordinationMode: PromoCoordinationMode

    private(set) var registrationCount = 0
    private(set) var deregistrationCount = 0
    private(set) var registeredRendererID: UUID?
    private(set) var selectedRendererID: UUID?
    private(set) weak var rendererTarget: NewTabPagePromoRendering?
    private(set) var updates = [RendererUpdate]()
    private(set) var appearanceCalls = [AppearanceCall]()
    private(set) var removalCalls = [RemovalCall]()
    var appearanceResults = [PromoQueueRemoteMessageAppearanceResult]()
    var onConfirmAppearance: (() -> Void)?
    var onRemovalTerminal: ((RemovalCall) -> Void)?

    init(promoCoordinationMode: PromoCoordinationMode = .legacy) {
        self.promoCoordinationMode = promoCoordinationMode
    }

    func setSelectedRemoteMessageRendererID(_ rendererID: UUID?) {
        selectedRendererID = rendererID
    }

    func registerRemoteMessageRenderer(
        id: UUID,
        target: NewTabPagePromoRendering
    ) -> NewTabPagePromoRendererRegistration {
        registrationCount += 1
        registeredRendererID = id
        rendererTarget = target

        return NewTabPagePromoRendererRegistration(
            updateHandler: { [weak self] candidate, isLocallyReady in
                self?.updates.append(RendererUpdate(candidate: candidate, isLocallyReady: isLocallyReady))
            },
            appearanceHandler: { [weak self] sessionID, presentationID, isAttachedToWindow in
                guard let self else {
                    return .rejected
                }
                appearanceCalls.append(AppearanceCall(
                    sessionID: sessionID,
                    presentationID: presentationID,
                    isAttachedToWindow: isAttachedToWindow
                ))
                onConfirmAppearance?()
                guard !appearanceResults.isEmpty else {
                    return .rejected
                }
                return appearanceResults.removeFirst()
            },
            removalTerminalHandler: { [weak self] sessionID, presentationID, removalID, terminal in
                let call = RemovalCall(
                    sessionID: sessionID,
                    presentationID: presentationID,
                    removalID: removalID,
                    terminal: terminal
                )
                self?.removalCalls.append(call)
                self?.onRemovalTerminal?(call)
            },
            deregistrationHandler: { [weak self] in
                self?.deregistrationCount += 1
            }
        )
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

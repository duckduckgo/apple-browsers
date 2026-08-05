//
//  NewTabPageMessagesModel.swift
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
import Foundation
import RemoteMessaging

// MARK: - Render Models

/// A stable SwiftUI render slot for either a direct home message or a coordinated remote-message gate.
struct NewTabPageHomeMessageRenderItem: Identifiable {
    enum Content {
        /// A home message rendered directly without coordinated admission.
        case message(HomeMessageViewModel)
        /// A stable mount point whose optional session reflects visible-promo admission.
        case remoteMessageGate(NewTabPageRemoteMessageGate)
    }

    /// Stable identity used to preserve the appropriate SwiftUI mount across model refreshes.
    let id: String
    let content: Content
}

/// Keeps a remote-message mount in the render tree while admission controls whether it has content.
struct NewTabPageRemoteMessageGate {
    /// Identity of the gate for the current remote-message candidate.
    let id: UUID
    let messageID: String
    /// Present only while this gate owns an admitted visible-promo render session.
    let renderSession: NewTabPageRemoteMessageRenderSession?
}

/// Identity and view model for one admitted rendering of a remote message.
struct NewTabPageRemoteMessageRenderSession {
    /// Changes when SwiftUI should replace the mounted card with a newly admitted session.
    let id: UUID
    let viewModel: HomeMessageViewModel
}

@MainActor
final class NewTabPageMessagesModel: ObservableObject {
    // MARK: - Published State

    @Published private(set) var homeMessageRenderItems: [NewTabPageHomeMessageRenderItem] = []

    var homeMessageViewModels: [HomeMessageViewModel] {
        homeMessageRenderItems.compactMap { item in
            switch item.content {
            case .message(let viewModel):
                return viewModel
            case .remoteMessageGate(let gate):
                return gate.renderSession?.viewModel
            }
        }
    }

    let surfaceID: UUID

    // MARK: - Coordination State

    private struct AdmittedRemoteMessageSession {
        let id: UUID
        let gateID: UUID
        let identity: VisiblePromoIdentity
        let lease: PromoQueueVisiblePromoLease
        var message: HomeMessage
        var viewModel: HomeMessageViewModel
        var appearanceRecorded: Bool
    }

    private struct RemoteMessageGateIdentity {
        let id: UUID
        let messageID: String
    }

    private var observable: NSObjectProtocol?
    private var retryRegistration: NewTabPagePromoRetryRegistration?
    private var isLoaded = false
    private var isTornDown = false
    private var isSurfaceRenderable = false
    private var attachedToWindowProvider: () -> Bool = { false }
    private var messagesSnapshot = [HomeMessage]()
    private var remoteMessageCandidate: HomeMessage?
    private var remoteMessageGateIdentity: RemoteMessageGateIdentity?
    private var visibleRemoteMessageGateID: UUID?
    private var visibleRemoteMessageGateMountIDs = Set<UUID>()
    private var admittedRemoteMessageSession: AdmittedRemoteMessageSession?
    private var featureTransitionTarget: PromoQueueFeatureTargetState?

    // MARK: - Dependencies

    private let homePageMessagesConfiguration: HomePageMessagesConfiguration
    private let notificationCenter: NotificationCenter
    private let pixelFiring: PixelFiring.Type
    private let subscriptionDataReporter: SubscriptionDataReporting?
    private let messageActionHandler: RemoteMessagingActionHandling
    private let imageLoader: RemoteMessagingImageLoading
    private let pixelReporter: RemoteMessagingPixelReporting?
    private let promoCoordinator: NewTabPagePromoCoordinating
    private let isOpenedAfterIdle: () -> Bool

    // MARK: - Initialization

    init(homePageMessagesConfiguration: HomePageMessagesConfiguration,
         surfaceID: UUID = UUID(),
         notificationCenter: NotificationCenter = .default,
         pixelFiring: PixelFiring.Type = Pixel.self,
         subscriptionDataReporter: SubscriptionDataReporting? = nil,
         messageActionHandler: RemoteMessagingActionHandling,
         imageLoader: RemoteMessagingImageLoading,
         pixelReporter: RemoteMessagingPixelReporting? = nil,
         promoCoordinator: NewTabPagePromoCoordinating,
         isOpenedAfterIdle: @escaping () -> Bool = { false }) {
        self.homePageMessagesConfiguration = homePageMessagesConfiguration
        self.surfaceID = surfaceID
        self.notificationCenter = notificationCenter
        self.pixelFiring = pixelFiring
        self.subscriptionDataReporter = subscriptionDataReporter
        self.messageActionHandler = messageActionHandler
        self.imageLoader = imageLoader
        self.pixelReporter = pixelReporter
        self.promoCoordinator = promoCoordinator
        self.isOpenedAfterIdle = isOpenedAfterIdle
    }

    deinit {
        if let observable {
            notificationCenter.removeObserver(observable)
        }
    }

    // MARK: - Lifecycle

    /// The owning controller must call this once after construction; repeat calls are ignored.
    func load() {
        guard !isLoaded, !isTornDown else {
            if isTornDown {
                assertionFailure("A torn-down messages model must not be reloaded")
            }
            return
        }

        isLoaded = true
        retryRegistration = promoCoordinator.registerVisiblePromoRetry(
            for: surfaceID,
            target: self
        )
        observable = notificationCenter.addObserver(
            forName: RemoteMessagingStore.Notifications.remoteMessagesDidChange,
            object: nil,
            queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.refresh()
                }
        }

        refresh()
    }

    func tearDown() {
        guard !isTornDown else {
            return
        }

        isTornDown = true
        isSurfaceRenderable = false
        visibleRemoteMessageGateID = nil
        visibleRemoteMessageGateMountIDs.removeAll()
        remoteMessageGateIdentity = nil

        if let observable {
            notificationCenter.removeObserver(observable)
            self.observable = nil
        }
        retryRegistration?.deregister()
        retryRegistration = nil

        withdrawAdmittedRemoteMessage()
        messagesSnapshot = []
        remoteMessageCandidate = nil
        publishRenderItems()
    }

    // MARK: - Surface Exposure

    func setSurfaceAttachmentProvider(_ provider: @escaping () -> Bool) {
        attachedToWindowProvider = provider
        attemptRemoteMessageAdmission()
    }

    func setSurfaceRenderable(_ isRenderable: Bool) {
        guard isSurfaceRenderable != isRenderable else {
            if isRenderable {
                attemptRemoteMessageAdmission()
            }
            return
        }

        isSurfaceRenderable = isRenderable
        if isRenderable {
            attemptRemoteMessageAdmission()
        } else {
            withdrawAdmittedRemoteMessage()
        }
    }

    // MARK: - Gate Mount Lifecycle

    func remoteMessageGateDidAppear(gateID: UUID, messageID: String, mountID: UUID) {
        guard remoteMessageCandidate?.remoteMessageID == messageID,
              remoteMessageGateIdentity?.id == gateID,
              remoteMessageGateIdentity?.messageID == messageID else {
            return
        }

        visibleRemoteMessageGateID = gateID
        visibleRemoteMessageGateMountIDs.insert(mountID)
        attemptRemoteMessageAdmission()
    }

    func remoteMessageGateDidDisappear(gateID: UUID, messageID: String, mountID: UUID) {
        guard remoteMessageGateIdentity?.id == gateID,
              remoteMessageGateIdentity?.messageID == messageID,
              visibleRemoteMessageGateID == gateID else {
            return
        }
        guard visibleRemoteMessageGateMountIDs.remove(mountID) != nil else {
            return
        }
        guard visibleRemoteMessageGateMountIDs.isEmpty else {
            return
        }

        visibleRemoteMessageGateID = nil
        withdrawAdmittedRemoteMessage()
    }

    func remoteMessageDidDisappear(renderSessionID: UUID, mountID: UUID) {
        if admittedRemoteMessageSession?.id == renderSessionID {
            guard visibleRemoteMessageGateMountIDs.count == 1,
                  visibleRemoteMessageGateMountIDs.contains(mountID) else {
                return
            }

            guard let session = admittedRemoteMessageSession else {
                return
            }
            admittedRemoteMessageSession = nil
            publishRenderItems()
            promoCoordinator.releaseVisiblePromoLease(session.lease)
            scheduleAdmissionAfterPhysicalRemoval()
        }
    }

    // MARK: - Message Actions

    @MainActor
    func dismissHomeMessage(_ homeMessage: HomeMessage) async {
        await homePageMessagesConfiguration.dismissHomeMessage(homeMessage)
        updateHomeMessageViewModel()
    }

    func didAppear(_ homeMessage: HomeMessage) {
        homePageMessagesConfiguration.didAppear(homeMessage)
    }

    func refresh() {
        refresh(shouldAttemptAdmission: true)
    }

    private func refresh(shouldAttemptAdmission: Bool) {
        guard !isTornDown else {
            return
        }

        homePageMessagesConfiguration.refresh(openedAfterIdle: isOpenedAfterIdle())
        updateHomeMessageViewModel(shouldAttemptAdmission: shouldAttemptAdmission)
    }

    // MARK: - Render Model Updates

    private func updateHomeMessageViewModel(shouldAttemptAdmission: Bool = true) {
        let newMessages = homePageMessagesConfiguration.homeMessages
        let newRemoteMessageCandidate = newMessages.first(where: \.isRemoteMessage)
        let previousMessageID = remoteMessageCandidate?.remoteMessageID
        let newMessageID = newRemoteMessageCandidate?.remoteMessageID

        messagesSnapshot = newMessages

        if previousMessageID != newMessageID {
            withdrawAdmittedRemoteMessage()
            visibleRemoteMessageGateID = nil
            visibleRemoteMessageGateMountIDs.removeAll()
            remoteMessageGateIdentity = nil
        }

        remoteMessageCandidate = newRemoteMessageCandidate

        if let admittedRemoteMessageSession,
           admittedRemoteMessageSession.identity.promoID == newMessageID,
           let newRemoteMessageCandidate {
            updateAdmittedRemoteMessageSession(
                admittedRemoteMessageSession,
                with: newRemoteMessageCandidate
            )
        }

        publishRenderItems()

        if previousMessageID != newMessageID {
            scheduleAdmissionAfterPhysicalRemoval()
        } else if shouldAttemptAdmission {
            attemptRemoteMessageAdmission()
        }
    }

    private func updateAdmittedRemoteMessageSession(
        _ session: AdmittedRemoteMessageSession,
        with message: HomeMessage
    ) {
        guard case .remoteMessage(let remoteMessage) = message else {
            return
        }

        var updatedSession = session
        updatedSession.message = message
        guard let viewModel = makeRemoteMessageViewModel(
            for: remoteMessage,
            message: message,
            renderSessionID: session.id
        ) else {
            withdrawAdmittedRemoteMessage()
            return
        }
        updatedSession.viewModel = viewModel
        admittedRemoteMessageSession = updatedSession
    }

    private func publishRenderItems(useCoordinatedGate coordinatedGateOverride: Bool? = nil) {
        let shouldUseCoordinatedGate = coordinatedGateOverride
            ?? (featureTransitionTarget != nil || promoCoordinator.promoQueueFeatureState != .disabled)
        var renderItems = [NewTabPageHomeMessageRenderItem]()

        for (index, message) in messagesSnapshot.enumerated() {
            switch message {
            case .placeholder:
                let viewModel = makePlaceholderViewModel(for: message)
                renderItems.append(NewTabPageHomeMessageRenderItem(
                    id: "local-message-\(index)",
                    content: .message(viewModel)
                ))

            case .remoteMessage(let remoteMessage):
                if shouldUseCoordinatedGate {
                    guard remoteMessage.id == remoteMessageCandidate?.remoteMessageID else {
                        assertionFailure("Expected at most one remote message candidate")
                        continue
                    }
                    let gateIdentity = remoteMessageGateIdentity(for: remoteMessage.id)
                    let renderSession: NewTabPageRemoteMessageRenderSession?
                    if let session = admittedRemoteMessageSession,
                       session.identity.promoID == remoteMessage.id,
                       session.gateID == gateIdentity.id {
                        renderSession = NewTabPageRemoteMessageRenderSession(
                            id: session.id,
                            viewModel: session.viewModel
                        )
                    } else {
                        renderSession = nil
                    }

                    renderItems.append(NewTabPageHomeMessageRenderItem(
                        id: "remote-message-gate-\(gateIdentity.id.uuidString)",
                        content: .remoteMessageGate(NewTabPageRemoteMessageGate(
                            id: gateIdentity.id,
                            messageID: remoteMessage.id,
                            renderSession: renderSession
                        ))
                    ))
                } else {
                    remoteMessageGateIdentity = nil
                    visibleRemoteMessageGateID = nil
                    visibleRemoteMessageGateMountIDs.removeAll()
                    guard let viewModel = makeLegacyRemoteMessageViewModel(
                        for: remoteMessage,
                        message: message
                    ) else {
                        continue
                    }
                    renderItems.append(NewTabPageHomeMessageRenderItem(
                        id: "remote-message-\(remoteMessage.id)",
                        content: .message(viewModel)
                    ))
                }
            }
        }

        homeMessageRenderItems = renderItems
    }

    // MARK: - View Model Construction

    private func makePlaceholderViewModel(for message: HomeMessage) -> HomeMessageViewModel {
        HomeMessageViewModel(
            messageId: "",
            modelType: .small(titleText: "", descriptionText: ""),
            messageActionHandler: messageActionHandler,
            preloadedImage: nil,
            loadRemoteImage: nil
        ) { [weak self] _ in
            await self?.dismissHomeMessage(message)
        } onDidAppear: {
            // no-op
        } onAttachAdditionalParameters: { _, params in
            params
        }
    }

    private func makeLegacyRemoteMessageViewModel(
        for remoteMessage: RemoteMessageModel,
        message: HomeMessage
    ) -> HomeMessageViewModel? {
        // Preserve the feature-off path exactly: refreshing an already-visible NTP records
        // appearance eagerly, and the SwiftUI view records its normal onAppear separately.
        didAppear(message)

        return buildRemoteMessageViewModel(
            for: remoteMessage,
            message: message
        ) { [weak self] in
            self?.didAppear(message)
        }
    }

    private func makeRemoteMessageViewModel(
        for remoteMessage: RemoteMessageModel,
        message: HomeMessage,
        renderSessionID: UUID
    ) -> HomeMessageViewModel? {
        buildRemoteMessageViewModel(
            for: remoteMessage,
            message: message
        ) { [weak self] in
            self?.recordAppearance(
                for: message,
                renderSessionID: renderSessionID
            )
        }
    }

    private func buildRemoteMessageViewModel(
        for remoteMessage: RemoteMessageModel,
        message: HomeMessage,
        onDidAppear: @escaping () -> Void
    ) -> HomeMessageViewModel? {
        HomeMessageViewModelBuilder.build(
            for: remoteMessage,
            with: subscriptionDataReporter,
            messageActionHandler: messageActionHandler,
            imageLoader: imageLoader,
            pixelReporter: pixelReporter
        ) { @MainActor [weak self] action in
            guard let action,
                  let self else {
                return
            }

            switch action {
            case .action(let isSharing):
                if !isSharing {
                    await dismissHomeMessage(message)
                }
                if remoteMessage.isMetricsEnabled {
                    pixelFiring.fire(
                        .remoteMessageActionClicked,
                        withAdditionalParameters: additionalParameters(for: remoteMessage.id)
                    )
                }

            case .primaryAction(let isSharing):
                if !isSharing {
                    await dismissHomeMessage(message)
                }
                if remoteMessage.isMetricsEnabled {
                    pixelFiring.fire(
                        .remoteMessagePrimaryActionClicked,
                        withAdditionalParameters: additionalParameters(for: remoteMessage.id)
                    )
                }

            case .secondaryAction(let isSharing):
                if !isSharing {
                    await dismissHomeMessage(message)
                }
                if remoteMessage.isMetricsEnabled {
                    pixelFiring.fire(
                        .remoteMessageSecondaryActionClicked,
                        withAdditionalParameters: additionalParameters(for: remoteMessage.id)
                    )
                }

            case .close:
                await dismissHomeMessage(message)
                if remoteMessage.isMetricsEnabled {
                    pixelFiring.fire(
                        .remoteMessageDismissed,
                        withAdditionalParameters: additionalParameters(for: remoteMessage.id)
                    )
                }
            }
        } onDidAppear: {
            onDidAppear()
        }
    }

    // MARK: - Appearance Accounting

    private func recordAppearance(
        for message: HomeMessage,
        renderSessionID: UUID
    ) {
        guard var session = admittedRemoteMessageSession,
              session.id == renderSessionID,
              !session.appearanceRecorded else {
            return
        }

        session.appearanceRecorded = true
        admittedRemoteMessageSession = session
        didAppear(message)
    }

    // MARK: - Admission

    private func attemptRemoteMessageAdmission() {
        guard promoCoordinator.promoQueueFeatureState == .enabled else {
            return
        }

        attemptRemoteMessageAdmission(using: promoCoordinator.admitVisiblePromo)
    }

    private func attemptRemoteMessageAdmission(
        using admissionHandler: VisiblePromoAdmissionHandler
    ) {
        guard isLoaded,
              !isTornDown,
              featureTransitionTarget == nil,
              isSurfaceRenderable,
              attachedToWindowProvider(),
              let message = remoteMessageCandidate,
              let messageID = message.remoteMessageID,
              let gateIdentity = remoteMessageGateIdentity,
              gateIdentity.messageID == messageID,
              visibleRemoteMessageGateID == gateIdentity.id,
              !visibleRemoteMessageGateMountIDs.isEmpty else {
            return
        }

        if admittedRemoteMessageSession?.identity.promoID == messageID,
           admittedRemoteMessageSession?.gateID == gateIdentity.id {
            return
        }

        let identity = VisiblePromoIdentity(
            surfaceID: surfaceID,
            promoType: .remoteMessage,
            promoID: messageID
        )

        let admissionResult = admissionHandler(identity)
        switch admissionResult {
        case .acquired(let lease):
            guard case .remoteMessage(let remoteMessage) = message else {
                promoCoordinator.releaseVisiblePromoLease(lease)
                return
            }
            let renderSessionID = UUID()
            guard let viewModel = makeRemoteMessageViewModel(
                for: remoteMessage,
                message: message,
                renderSessionID: renderSessionID
            ) else {
                promoCoordinator.releaseVisiblePromoLease(lease)
                return
            }
            admittedRemoteMessageSession = AdmittedRemoteMessageSession(
                id: renderSessionID,
                gateID: gateIdentity.id,
                identity: identity,
                lease: lease,
                message: message,
                viewModel: viewModel,
                appearanceRecorded: false
            )
            publishRenderItems()

        case .blockedByModal, .occupiedSurfaceSlot, .featureDisabled, .unavailableDuringTransition:
            break
        }
    }

    private func withdrawAdmittedRemoteMessage() {
        guard let session = admittedRemoteMessageSession else {
            return
        }

        admittedRemoteMessageSession = nil
        publishRenderItems()
        // SwiftUI removes the card in the transaction triggered above. The next-turn release
        // bounds any physical-removal overlap to that single animation.
        let promoCoordinator = promoCoordinator
        DispatchQueue.main.async { [weak self, promoCoordinator, session] in
            promoCoordinator.releaseVisiblePromoLease(session.lease)
            self?.attemptRemoteMessageAdmission()
        }
    }

    private func scheduleAdmissionAfterPhysicalRemoval() {
        DispatchQueue.main.async { [weak self] in
            self?.attemptRemoteMessageAdmission()
        }
    }

    // MARK: - Utilities

    private func additionalParameters(for messageID: String) -> [String: String] {
        let defaultParameters = [PixelParameters.message: "\(messageID)"]
        return subscriptionDataReporter?.mergeRandomizedParameters(
            for: .messageID(messageID),
            with: defaultParameters
        ) ?? defaultParameters
    }

    private func remoteMessageGateIdentity(for messageID: String) -> RemoteMessageGateIdentity {
        if let remoteMessageGateIdentity,
           remoteMessageGateIdentity.messageID == messageID {
            return remoteMessageGateIdentity
        }

        let identity = RemoteMessageGateIdentity(
            id: UUID(),
            messageID: messageID
        )
        remoteMessageGateIdentity = identity
        return identity
    }

}

// MARK: - NewTabPagePromoRetrying

extension NewTabPageMessagesModel: NewTabPagePromoRetrying {
    var isActiveForPromoRetry: Bool {
        isLoaded
            && !isTornDown
            && isSurfaceRenderable
            && attachedToWindowProvider()
    }

    func retryVisiblePromoAdmission(using admissionHandler: VisiblePromoAdmissionHandler) {
        refresh(shouldAttemptAdmission: false)
        attemptRemoteMessageAdmission(using: admissionHandler)
    }

    func promoQueueWillTransition(to targetState: PromoQueueFeatureTargetState) {
        featureTransitionTarget = targetState
        withdrawAdmittedRemoteMessage()
        visibleRemoteMessageGateID = nil
        visibleRemoteMessageGateMountIDs.removeAll()
        publishRenderItems()
    }

    func promoQueueDidTransition(to targetState: PromoQueueFeatureTargetState) {
        guard featureTransitionTarget == targetState else {
            return
        }

        featureTransitionTarget = nil
        if targetState == .disabled {
            publishRenderItems(useCoordinatedGate: false)
        } else {
            publishRenderItems(useCoordinatedGate: true)
        }
    }
}

// MARK: - HomeMessage Helpers

private extension HomeMessage {
    var isRemoteMessage: Bool {
        if case .remoteMessage = self {
            return true
        }
        return false
    }

    var remoteMessageID: String? {
        guard case .remoteMessage(let remoteMessage) = self else {
            return nil
        }
        return remoteMessage.id
    }
}

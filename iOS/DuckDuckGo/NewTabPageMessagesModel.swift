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
import SwiftUI

// MARK: - Render Models

/// A stable SwiftUI render item for either a legacy/direct message or one centrally authorized remote-message presentation.
struct NewTabPageHomeMessageRenderItem: Identifiable {
    enum Content {
        case message(HomeMessageViewModel)
        case coordinatedRemoteMessage(NewTabPageRemoteMessageRenderSession)
    }

    let id: String
    let content: Content
}

/// The single service-authorized physical presentation rendered by this model.
struct NewTabPageRemoteMessageRenderSession {
    let presentation: PromoQueueRemoteMessagePresentation
    let viewModel: HomeMessageViewModel
}

/// Injectable selection of the old-OS synchronous removal path so it can be exercised on a current simulator.
enum NewTabPageRemoteMessageRemovalPath: Equatable {
    case automatic
    case synchronousSourceClear
}

@MainActor
final class NewTabPageMessagesModel: ObservableObject {
    @Published private(set) var homeMessageRenderItems: [NewTabPageHomeMessageRenderItem] = []

    var homeMessageViewModels: [HomeMessageViewModel] {
        homeMessageRenderItems.map { item in
            switch item.content {
            case .message(let viewModel):
                return viewModel
            case .coordinatedRemoteMessage(let renderSession):
                return renderSession.viewModel
            }
        }
    }

    var usesAnimatedRemoteMessageRemoval: Bool {
        guard removalPath == .automatic else {
            return false
        }
        if #available(iOS 17, *) {
            return true
        }
        return false
    }

    let surfaceID: UUID

    private struct AuthorizedRemoteMessage {
        let presentation: PromoQueueRemoteMessagePresentation
        var message: HomeMessage
        var viewModel: HomeMessageViewModel
    }

    private struct PendingRemoteMessageRemoval {
        let presentation: PromoQueueRemoteMessagePresentation
        let removalID: UUID
        let registration: NewTabPagePromoRendererRegistration
        var didReportTerminal: Bool
    }

    private var observable: NSObjectProtocol?
    private var rendererRegistration: NewTabPagePromoRendererRegistration?
    private var isLoaded = false
    private var isTornDown = false
    private var isSurfaceRenderable = false
    private var attachedToWindowProvider: () -> Bool = { false }
    private var messagesSnapshot = [HomeMessage]()
    private var remoteMessageCandidate: HomeMessage?
    private var remoteMessageCandidateState = PromoQueueRemoteMessageCandidateState.none
    private var authorizedRemoteMessage: AuthorizedRemoteMessage?
    private var pendingRemoteMessageRemoval: PendingRemoteMessageRemoval?

    private let homePageMessagesConfiguration: HomePageMessagesConfiguration
    private let notificationCenter: NotificationCenter
    private let pixelFiring: PixelFiring.Type
    private let subscriptionDataReporter: SubscriptionDataReporting?
    private let messageActionHandler: RemoteMessagingActionHandling
    private let imageLoader: RemoteMessagingImageLoading
    private let pixelReporter: RemoteMessagingPixelReporting?
    private let promoCoordinator: NewTabPagePromoCoordinating
    private let removalPath: NewTabPageRemoteMessageRemovalPath
    private let isOpenedAfterIdle: () -> Bool

    init(homePageMessagesConfiguration: HomePageMessagesConfiguration,
         surfaceID: UUID = UUID(),
         notificationCenter: NotificationCenter = .default,
         pixelFiring: PixelFiring.Type = Pixel.self,
         subscriptionDataReporter: SubscriptionDataReporting? = nil,
         messageActionHandler: RemoteMessagingActionHandling,
         imageLoader: RemoteMessagingImageLoading,
         pixelReporter: RemoteMessagingPixelReporting? = nil,
         promoCoordinator: NewTabPagePromoCoordinating,
         remoteMessageRemovalPath: NewTabPageRemoteMessageRemovalPath = .automatic,
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
        self.removalPath = remoteMessageRemovalPath
        self.isOpenedAfterIdle = isOpenedAfterIdle
    }

    deinit {
        if let observable {
            notificationCenter.removeObserver(observable)
        }
    }

    // MARK: - Lifecycle

    func load() {
        guard !isLoaded, !isTornDown else {
            if isTornDown {
                assertionFailure("A torn-down messages model must not be reloaded")
            }
            return
        }

        isLoaded = true
        if promoCoordinator.promoCoordinationMode == .coordinated {
            rendererRegistration = promoCoordinator.registerRemoteMessageRenderer(id: surfaceID, target: self)
        }
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
        if let observable {
            notificationCenter.removeObserver(observable)
            self.observable = nil
        }

        reportCandidateAndEligibility()
        rendererRegistration?.deregister()
        messagesSnapshot = []
        remoteMessageCandidate = nil
        remoteMessageCandidateState = .none

        if authorizedRemoteMessage == nil {
            publishRenderItems()
        }
    }

    /// Called after a host has physically detached this renderer. It is idempotent with the OS-specific removal terminal.
    func remoteMessageHostDidDetach() {
        guard !isRemoteMessageRendererAttachedToWindow,
              var pendingRemoval = pendingRemoteMessageRemoval,
              !pendingRemoval.didReportTerminal else {
            return
        }

        clearAuthorizedPresentation(matching: pendingRemoval.presentation)
        pendingRemoval.didReportTerminal = true
        pendingRemoteMessageRemoval = pendingRemoval
        pendingRemoval.registration.removalDidReachTerminal(
            sessionID: pendingRemoval.presentation.session.id,
            presentationID: pendingRemoval.presentation.id,
            removalID: pendingRemoval.removalID,
            terminal: .hostDetached
        )
        pendingRemoteMessageRemoval = nil
    }

    // MARK: - Surface Exposure

    func setSurfaceAttachmentProvider(_ provider: @escaping () -> Bool) {
        attachedToWindowProvider = provider
        reportCandidateAndEligibility()
        if isTornDown {
            remoteMessageHostDidDetach()
        }
    }

    func setSurfaceRenderable(_ isRenderable: Bool) {
        guard isSurfaceRenderable != isRenderable else {
            if isRenderable {
                reportCandidateAndEligibility()
            }
            return
        }

        isSurfaceRenderable = isRenderable
        reportCandidateAndEligibility()
    }

    // MARK: - Message Actions

    func dismissHomeMessage(_ homeMessage: HomeMessage) async {
        await homePageMessagesConfiguration.dismissHomeMessage(homeMessage)
        updateHomeMessageViewModel()
    }

    func didAppear(_ homeMessage: HomeMessage) {
        homePageMessagesConfiguration.didAppear(homeMessage)
    }

    func refresh() {
        guard !isTornDown else {
            return
        }

        homePageMessagesConfiguration.refresh(openedAfterIdle: isOpenedAfterIdle())
        updateHomeMessageViewModel()
    }

    // MARK: - Candidate And Rendering

    private func updateHomeMessageViewModel() {
        let newMessages = homePageMessagesConfiguration.homeMessages
        let newRemoteMessageCandidate = newMessages.first(where: \.isRemoteMessage)
        messagesSnapshot = newMessages
        remoteMessageCandidate = newRemoteMessageCandidate

        if let messageID = newRemoteMessageCandidate?.remoteMessageID {
            remoteMessageCandidateState = .available(messageID: messageID)
        } else {
            remoteMessageCandidateState = .none
        }

        if let authorizedRemoteMessage,
           authorizedRemoteMessage.presentation.session.messageID == newRemoteMessageCandidate?.remoteMessageID,
           let newRemoteMessageCandidate {
            updateAuthorizedRemoteMessage(authorizedRemoteMessage, with: newRemoteMessageCandidate)
        }

        publishRenderItems()
        reportCandidateAndEligibility()
    }

    private func updateAuthorizedRemoteMessage(
        _ authorizedRemoteMessage: AuthorizedRemoteMessage,
        with message: HomeMessage
    ) {
        guard case .remoteMessage(let remoteMessage) = message,
              let viewModel = makeRemoteMessageViewModel(
                for: remoteMessage,
                message: message,
                presentation: authorizedRemoteMessage.presentation
              ) else {
            remoteMessageCandidateState = .unrenderable(messageID: authorizedRemoteMessage.presentation.session.messageID)
            return
        }

        self.authorizedRemoteMessage = AuthorizedRemoteMessage(
            presentation: authorizedRemoteMessage.presentation,
            message: message,
            viewModel: viewModel
        )
    }

    private func publishRenderItems() {
        var renderItems = [NewTabPageHomeMessageRenderItem]()
        var didPublishAuthorizedRemoteMessage = false

        for (index, message) in messagesSnapshot.enumerated() {
            switch message {
            case .placeholder:
                renderItems.append(NewTabPageHomeMessageRenderItem(
                    id: "local-message-\(index)",
                    content: .message(makePlaceholderViewModel(for: message))
                ))
            case .remoteMessage(let remoteMessage):
                guard promoCoordinator.promoCoordinationMode == .legacy else {
                    if !didPublishAuthorizedRemoteMessage,
                       let authorizedRemoteMessage,
                       authorizedRemoteMessage.presentation.session.messageID == remoteMessage.id {
                        renderItems.append(makeRenderItem(for: authorizedRemoteMessage))
                        didPublishAuthorizedRemoteMessage = true
                    }
                    continue
                }
                guard let viewModel = makeLegacyRemoteMessageViewModel(for: remoteMessage, message: message) else {
                    continue
                }
                renderItems.append(NewTabPageHomeMessageRenderItem(
                    id: "remote-message-\(remoteMessage.id)",
                    content: .message(viewModel)
                ))
            }
        }

        if let authorizedRemoteMessage, !didPublishAuthorizedRemoteMessage {
            renderItems.append(makeRenderItem(for: authorizedRemoteMessage))
        }

        homeMessageRenderItems = renderItems
    }

    private func makeRenderItem(for authorizedRemoteMessage: AuthorizedRemoteMessage) -> NewTabPageHomeMessageRenderItem {
        let renderSession = NewTabPageRemoteMessageRenderSession(
            presentation: authorizedRemoteMessage.presentation,
            viewModel: authorizedRemoteMessage.viewModel
        )
        return NewTabPageHomeMessageRenderItem(
            id: "coordinated-remote-message-\(authorizedRemoteMessage.presentation.id.uuidString)",
            content: .coordinatedRemoteMessage(renderSession)
        )
    }

    private func reportCandidateAndEligibility() {
        guard promoCoordinator.promoCoordinationMode == .coordinated else {
            return
        }
        rendererRegistration?.update(candidate: remoteMessageCandidateState, isEligible: isEligibleForRemoteMessageRendering)
    }

    private var isEligibleForRemoteMessageRendering: Bool {
        isLoaded && !isTornDown && isSurfaceRenderable && attachedToWindowProvider()
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
        // Preserve feature-off behavior: refresh records eagerly and SwiftUI records its ordinary appearance separately.
        didAppear(message)
        return buildRemoteMessageViewModel(for: remoteMessage, message: message) { [weak self] in
            self?.didAppear(message)
        }
    }

    private func makeRemoteMessageViewModel(
        for remoteMessage: RemoteMessageModel,
        message: HomeMessage,
        presentation: PromoQueueRemoteMessagePresentation
    ) -> HomeMessageViewModel? {
        buildRemoteMessageViewModel(for: remoteMessage, message: message) { [weak self] in
            self?.recordAppearance(for: message, presentation: presentation)
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
            guard let action, let self else {
                return
            }

            switch action {
            case .action(let isSharing):
                if !isSharing { await dismissHomeMessage(message) }
                if remoteMessage.isMetricsEnabled {
                    pixelFiring.fire(.remoteMessageActionClicked, withAdditionalParameters: additionalParameters(for: remoteMessage.id))
                }
            case .primaryAction(let isSharing):
                if !isSharing { await dismissHomeMessage(message) }
                if remoteMessage.isMetricsEnabled {
                    pixelFiring.fire(.remoteMessagePrimaryActionClicked, withAdditionalParameters: additionalParameters(for: remoteMessage.id))
                }
            case .secondaryAction(let isSharing):
                if !isSharing { await dismissHomeMessage(message) }
                if remoteMessage.isMetricsEnabled {
                    pixelFiring.fire(.remoteMessageSecondaryActionClicked, withAdditionalParameters: additionalParameters(for: remoteMessage.id))
                }
            case .close:
                await dismissHomeMessage(message)
                if remoteMessage.isMetricsEnabled {
                    pixelFiring.fire(.remoteMessageDismissed, withAdditionalParameters: additionalParameters(for: remoteMessage.id))
                }
            }
        } onDidAppear: {
            onDidAppear()
        }
    }

    private func recordAppearance(
        for message: HomeMessage,
        presentation: PromoQueueRemoteMessagePresentation
    ) {
        guard authorizedRemoteMessage?.presentation == presentation,
              rendererRegistration?.confirmAppearance(
                sessionID: presentation.session.id,
                presentationID: presentation.id,
                isAttachedToWindow: isRemoteMessageRendererAttachedToWindow
              ) == .accepted else {
            return
        }
        didAppear(message)
    }

    private func additionalParameters(for messageID: String) -> [String: String] {
        let defaultParameters = [PixelParameters.message: "\(messageID)"]
        return subscriptionDataReporter?.mergeRandomizedParameters(
            for: .messageID(messageID),
            with: defaultParameters
        ) ?? defaultParameters
    }
}

// MARK: - NewTabPagePromoRendering

extension NewTabPageMessagesModel: NewTabPagePromoRendering {
    var isRemoteMessageRendererAttachedToWindow: Bool {
        attachedToWindowProvider()
    }

    var hasPublishedRemoteMessagePresentation: Bool {
        authorizedRemoteMessage != nil || pendingRemoteMessageRemoval != nil
    }

    func showRemoteMessage(_ presentation: PromoQueueRemoteMessagePresentation) -> Bool {
        guard authorizedRemoteMessage == nil,
              pendingRemoteMessageRemoval == nil else {
            return false
        }
        guard !isTornDown,
              remoteMessageCandidate?.remoteMessageID == presentation.session.messageID,
              case .remoteMessage(let remoteMessage) = remoteMessageCandidate,
              let message = remoteMessageCandidate,
              let viewModel = makeRemoteMessageViewModel(
                for: remoteMessage,
                message: message,
                presentation: presentation
              ) else {
            return false
        }

        authorizedRemoteMessage = AuthorizedRemoteMessage(
            presentation: presentation,
            message: message,
            viewModel: viewModel
        )
        publishRenderItems()
        return true
    }

    func hideRemoteMessage(
        _ presentation: PromoQueueRemoteMessagePresentation,
        removalID: UUID
    ) {
        guard authorizedRemoteMessage?.presentation == presentation,
              pendingRemoteMessageRemoval == nil,
              let rendererRegistration else {
            return
        }

        pendingRemoteMessageRemoval = PendingRemoteMessageRemoval(
            presentation: presentation,
            removalID: removalID,
            registration: rendererRegistration,
            didReportTerminal: false
        )

        if !isRemoteMessageRendererAttachedToWindow {
            remoteMessageHostDidDetach()
            return
        }

        switch removalPath {
        case .synchronousSourceClear:
            removeWithoutAnimation(presentation: presentation, removalID: removalID)
        case .automatic:
            if #available(iOS 17, *) {
                removeWithNativeAnimation(presentation: presentation, removalID: removalID)
            } else {
                removeWithoutAnimation(presentation: presentation, removalID: removalID)
            }
        }
    }

    @available(iOS 17, *)
    private func removeWithNativeAnimation(
        presentation: PromoQueueRemoteMessagePresentation,
        removalID: UUID
    ) {
        SwiftUI.withAnimation(.default, completionCriteria: .removed) { [self] in
            clearAuthorizedPresentation(matching: presentation)
        } completion: { [self] in
            reportRemovalTerminal(
                presentation: presentation,
                removalID: removalID,
                terminal: .animationCompleted
            )
        }
    }

    private func removeWithoutAnimation(
        presentation: PromoQueueRemoteMessagePresentation,
        removalID: UUID
    ) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        SwiftUI.withTransaction(transaction) { [self] in
            clearAuthorizedPresentation(matching: presentation)
        }

        guard authorizedRemoteMessage?.presentation != presentation else {
            return
        }
        reportRemovalTerminal(
            presentation: presentation,
            removalID: removalID,
            terminal: .sourceRemovedWithoutAnimation
        )
    }

    private func clearAuthorizedPresentation(matching presentation: PromoQueueRemoteMessagePresentation) {
        guard authorizedRemoteMessage?.presentation == presentation else {
            return
        }
        authorizedRemoteMessage = nil
        publishRenderItems()
    }

    private func reportRemovalTerminal(
        presentation: PromoQueueRemoteMessagePresentation,
        removalID: UUID,
        terminal: PromoQueueRemoteMessageRemovalTerminal
    ) {
        guard var pendingRemoval = pendingRemoteMessageRemoval,
              pendingRemoval.presentation == presentation,
              pendingRemoval.removalID == removalID,
              !pendingRemoval.didReportTerminal else {
            return
        }

        pendingRemoval.didReportTerminal = true
        pendingRemoteMessageRemoval = pendingRemoval
        pendingRemoval.registration.removalDidReachTerminal(
            sessionID: presentation.session.id,
            presentationID: presentation.id,
            removalID: removalID,
            terminal: terminal
        )
        pendingRemoteMessageRemoval = nil
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

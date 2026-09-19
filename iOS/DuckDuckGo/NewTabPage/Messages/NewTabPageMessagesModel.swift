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

import Combine
import Core
import Foundation
import PixelKit
import RemoteMessaging

@MainActor
final class NewTabPageMessagesModel: ObservableObject {

    @Published private(set) var homeMessageViewModels: [HomeMessageViewModel] = []

    private var messagesCancellable: AnyCancellable?
    private var legacyNotificationObserver: NSObjectProtocol?
    private var renderableHomeMessages: [HomeMessageViewModel.ViewIdentity: HomeMessage] = [:]
    private var appearedMessageIdentities = Set<HomeMessageViewModel.ViewIdentity>()
    private var reportedMessageIdentities = Set<HomeMessageViewModel.ViewIdentity>()
    private var isSurfaceVisible = false

    private let homePageMessagesConfiguration: HomePageMessagesConfiguration
    private let notificationCenter: NotificationCenter
    private let pixelFiring: (any PixelKitFiring)?
    private let subscriptionDataReporter: SubscriptionDataReporting?
    private let messageActionHandler: RemoteMessagingActionHandling
    private let imageLoader: RemoteMessagingImageLoading
    private let pixelReporter: RemoteMessagingPixelReporting?
    private let isOpenedAfterIdle: () -> Bool

    init(homePageMessagesConfiguration: HomePageMessagesConfiguration,
         notificationCenter: NotificationCenter = .default,
         pixelFiring: (any PixelKitFiring)? = PixelKit.shared,
         subscriptionDataReporter: SubscriptionDataReporting? = nil,
         messageActionHandler: RemoteMessagingActionHandling,
         imageLoader: RemoteMessagingImageLoading,
         pixelReporter: RemoteMessagingPixelReporting? = nil,
         isOpenedAfterIdle: @escaping () -> Bool = { false }) {
        self.homePageMessagesConfiguration = homePageMessagesConfiguration
        self.notificationCenter = notificationCenter
        self.pixelFiring = pixelFiring
        self.subscriptionDataReporter = subscriptionDataReporter
        self.messageActionHandler = messageActionHandler
        self.imageLoader = imageLoader
        self.pixelReporter = pixelReporter
        self.isOpenedAfterIdle = isOpenedAfterIdle
    }

    func load() {
        switch homePageMessagesConfiguration.mode {
        case .legacy:
            legacyNotificationObserver = notificationCenter.addObserver(
                forName: RemoteMessagingStore.Notifications.remoteMessagesDidChange,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.refresh()
                }
            }
            refresh()
        case .coordinated:
            messagesCancellable = homePageMessagesConfiguration.contentDidChangePublisher
                .sink { [weak self] _ in
                    self?.updateHomeMessageViewModel()
                }
            updateHomeMessageViewModel()
        }
    }

    func dismissHomeMessage(_ homeMessage: HomeMessage) async {
        await dismissHomeMessage(
            homeMessage,
            presentationContext: homePageMessagesConfiguration.presentationContext(for: homeMessage)
        )
    }

    func didAppear(_ homeMessage: HomeMessage) {
        homePageMessagesConfiguration.didAppear(
            homeMessage,
            presentationContext: homePageMessagesConfiguration.presentationContext(for: homeMessage)
        )
    }

    func setSurfaceVisible(_ isVisible: Bool) {
        guard isSurfaceVisible != isVisible else {
            return
        }

        isSurfaceVisible = isVisible
        if isVisible {
            for identity in appearedMessageIdentities {
                reportAppearanceIfNeeded(for: identity)
            }
        } else {
            reportedMessageIdentities.removeAll()
        }
    }

    // MARK: - Private

    /// Reports which control the user pressed on a message, so the New Tab Page session event can
    /// record it. The model handles the message itself either way.
    var onMessageInteraction: ((NewTabPageMessageInteraction) -> Void)?

    func refresh() {
        if homePageMessagesConfiguration.mode == .legacy {
            homePageMessagesConfiguration.refresh(openedAfterIdle: isOpenedAfterIdle())
        }
        updateHomeMessageViewModel()
    }

    private func dismissHomeMessage(
        _ homeMessage: HomeMessage,
        presentationContext: HomeMessagePresentationContext?
    ) async {
        await homePageMessagesConfiguration.dismissHomeMessage(
            homeMessage,
            presentationContext: presentationContext
        )
        if homePageMessagesConfiguration.mode == .legacy {
            updateHomeMessageViewModel()
        }
    }

    private func updateHomeMessageViewModel() {
        let messages = homePageMessagesConfiguration.homeMessages
        let mappedMessages = messages.compactMap { message -> (HomeMessage, HomeMessageViewModel)? in
            guard let viewModel = homeMessageViewModel(for: message) else {
                return nil
            }
            return (message, viewModel)
        }
        renderableHomeMessages = Dictionary(
            uniqueKeysWithValues: mappedMessages.map { ($0.1.viewIdentity, $0.0) }
        )
        appearedMessageIdentities.formIntersection(renderableHomeMessages.keys)
        reportedMessageIdentities.formIntersection(renderableHomeMessages.keys)
        homeMessageViewModels = mappedMessages.map { $0.1 }
    }

    private func messageViewDidAppear(with identity: HomeMessageViewModel.ViewIdentity) {
        appearedMessageIdentities.insert(identity)
        reportAppearanceIfNeeded(for: identity)
    }

    private func reportAppearanceIfNeeded(for identity: HomeMessageViewModel.ViewIdentity) {
        guard isSurfaceVisible,
              !reportedMessageIdentities.contains(identity),
              let homeMessage = renderableHomeMessages[identity] else {
            return
        }

        reportedMessageIdentities.insert(identity)
        didAppear(homeMessage)
    }

    // MARK: - HomeMessageViewModel Mapping

    private func homeMessageViewModel(for message: HomeMessage) -> HomeMessageViewModel? {
        switch message {
        case .placeholder:
            return HomeMessageViewModel(messageId: "",
                                        acquisitionIdentity: nil,
                                        modelType: .small(titleText: "", descriptionText: ""),
                                        messageActionHandler: messageActionHandler,
                                        preloadedImage: nil,
                                        loadRemoteImage: nil) { [weak self] _ in
                await self?.dismissHomeMessage(message)
            } onDidAppear: {
                // no-op
            } onAttachAdditionalParameters: { _, params in
                params
            }

        case .remoteMessage(let remoteMessage):
            let presentationContext = homePageMessagesConfiguration.presentationContext(for: message)
            let viewIdentity: HomeMessageViewModel.ViewIdentity
            if let acquisitionIdentity = presentationContext?.acquisitionIdentity {
                viewIdentity = .coordinated(messageID: remoteMessage.id, acquisitionIdentity: acquisitionIdentity)
            } else {
                viewIdentity = .legacy(messageID: remoteMessage.id)
            }

            return HomeMessageViewModelBuilder.build(for: remoteMessage,
                                                     with: subscriptionDataReporter,
                                                     messageActionHandler: messageActionHandler,
                                                     imageLoader: imageLoader,
                                                     pixelReporter: pixelReporter,
                                                     acquisitionIdentity: presentationContext?.acquisitionIdentity) { @MainActor [weak self] action in
                guard let action,
                      let self else { return }

                self.onMessageInteraction?(action == .close ? .dismiss : .callToAction)

                switch action {

                case .action(let isSharing):
                    if !isSharing {
                        await self.dismissHomeMessage(message, presentationContext: presentationContext)
                    }
                    if remoteMessage.isMetricsEnabled {
                        pixelFiring?.fire(Pixel.Event.remoteMessageActionClicked,
                                          options: .parameters(self.additionalParameters(for: remoteMessage.id)))
                    }

                case .primaryAction(let isSharing):
                    if !isSharing {
                        await self.dismissHomeMessage(message, presentationContext: presentationContext)
                    }
                    if remoteMessage.isMetricsEnabled {
                        pixelFiring?.fire(Pixel.Event.remoteMessagePrimaryActionClicked,
                                          options: .parameters(self.additionalParameters(for: remoteMessage.id)))
                    }

                case .secondaryAction(let isSharing):
                    if !isSharing {
                        await self.dismissHomeMessage(message, presentationContext: presentationContext)
                    }
                    if remoteMessage.isMetricsEnabled {
                        pixelFiring?.fire(Pixel.Event.remoteMessageSecondaryActionClicked,
                                          options: .parameters(self.additionalParameters(for: remoteMessage.id)))
                    }

                case .close:
                    await self.dismissHomeMessage(message, presentationContext: presentationContext)
                    if remoteMessage.isMetricsEnabled {
                        pixelFiring?.fire(Pixel.Event.remoteMessageDismissed,
                                          options: .parameters(self.additionalParameters(for: remoteMessage.id)))
                    }

                }
            } onDidAppear: { [weak self] in
                self?.messageViewDidAppear(with: viewIdentity)
            }
        }
    }

    private func additionalParameters(for messageID: String) -> [String: String] {
        let defaultParameters = [PixelParameters.message: "\(messageID)"]
        return subscriptionDataReporter?.mergeRandomizedParameters(for: .messageID(messageID),
                                                                 with: defaultParameters) ?? defaultParameters
    }
}

//
//  HomePageConfiguration.swift
//  DuckDuckGo
//
//  Copyright © 2018 DuckDuckGo. All rights reserved.
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

import BrowserServicesKit
import Combine
import Common
import Core
import Foundation
import FoundationExtensions
import RemoteMessaging
import os.log

@MainActor
final class HomePageConfiguration: HomePageMessagesConfiguration {

    private enum PreparationPolicy {
        case noTrigger
        case afterIdleThenNoTrigger

        init(openedAfterIdle: Bool) {
            self = openedAfterIdle ? .afterIdleThenNoTrigger : .noTrigger
        }
    }

    private struct SelectedRemoteMessage {
        let message: RemoteMessageModel
        let triggerFilter: TriggerFilter
    }

    private struct RMFOwnership {
        let message: RemoteMessageModel
        let lease: PromoQueueRemoteMessageLease
        let selectedTriggerFilter: TriggerFilter
        let presentationContext: HomeMessagePresentationContext
    }

    private let homeMessageStorage: HomeMessageStorage
    private let remoteMessagingStore: RemoteMessagingStoring
    private let subscriptionDataReporter: SubscriptionDataReporting
    private let isStillOnboarding: () -> Bool
    private let promoGate: PromoGating?
    private let notificationCenter: NotificationCenter
    private let contentDidChangeSubject = PassthroughSubject<Void, Never>()

    private var remoteMessagesCancellable: AnyCancellable?
    private var rmfOwnership: RMFOwnership?
    private var isRMFAdmissionEnabled: Bool
    private var lastPreparationPolicy: PreparationPolicy?

    var homeMessages: [HomeMessage] = []
    let mode: PromoCoordinationMode

    var contentDidChangePublisher: AnyPublisher<Void, Never> {
        contentDidChangeSubject.eraseToAnyPublisher()
    }

    init(variantManager: VariantManager? = nil,
         remoteMessagingStore: RemoteMessagingStoring,
         subscriptionDataReporter: SubscriptionDataReporting,
         isStillOnboarding: @escaping () -> Bool,
         promoGate: PromoGating? = nil,
         isRMFAdmissionEnabled: Bool = true,
         notificationCenter: NotificationCenter = .default
    ) {
        homeMessageStorage = HomeMessageStorage(variantManager: variantManager)
        self.remoteMessagingStore = remoteMessagingStore
        self.subscriptionDataReporter = subscriptionDataReporter
        self.isStillOnboarding = isStillOnboarding
        self.promoGate = promoGate
        self.notificationCenter = notificationCenter
        mode = promoGate?.mode ?? .legacy
        self.isRMFAdmissionEnabled = isRMFAdmissionEnabled

        switch mode {
        case .legacy:
            homeMessages = buildLegacyHomeMessages(openedAfterIdle: false)
        case .coordinated:
            homeMessages = nonRemoteHomeMessages
            observeRemoteMessagesChanges()
        }
    }

    func refresh(openedAfterIdle: Bool = false) {
        switch mode {
        case .legacy:
            homeMessages = buildLegacyHomeMessages(openedAfterIdle: openedAfterIdle)
        case .coordinated:
            prepareForNTP(openedAfterIdle: openedAfterIdle)
        }
    }

    func prepareForNTP(openedAfterIdle: Bool) {
        guard mode == .coordinated else {
            homeMessages = buildLegacyHomeMessages(openedAfterIdle: openedAfterIdle)
            return
        }
        guard isRMFAdmissionEnabled else {
            return
        }

        let preparationPolicy = PreparationPolicy(openedAfterIdle: openedAfterIdle)
        lastPreparationPolicy = preparationPolicy
        reconcileCoordinatedMessages(using: preparationPolicy)
    }

    func handleAppBackgrounded() {
        guard mode == .coordinated else {
            return
        }

        isRMFAdmissionEnabled = false
        lastPreparationPolicy = nil
        endCurrentRMFOwnership(replacingWith: nonRemoteHomeMessages)
    }

    func handleAppForegrounded() {
        guard mode == .coordinated else {
            return
        }

        isRMFAdmissionEnabled = true
    }

    func dismissHomeMessage(_ homeMessage: HomeMessage) async {
        await dismissHomeMessage(homeMessage, presentationContext: nil)
    }

    func didAppear(_ homeMessage: HomeMessage) {
        didAppear(homeMessage, presentationContext: nil)
    }

    func presentationContext(for homeMessage: HomeMessage) -> HomeMessagePresentationContext? {
        guard mode == .coordinated,
              case .remoteMessage(let remoteMessage) = homeMessage,
              let rmfOwnership,
              rmfOwnership.presentationContext.messageID == remoteMessage.id else {
            return nil
        }
        return rmfOwnership.presentationContext
    }

    func dismissHomeMessage(_ homeMessage: HomeMessage, presentationContext: HomeMessagePresentationContext?) async {
        guard case .remoteMessage(let remoteMessage) = homeMessage else {
            return
        }

        guard mode == .coordinated else {
            await dismissLegacyRemoteMessage(remoteMessage, homeMessage: homeMessage)
            return
        }

        guard let presentationContext,
              isCurrent(presentationContext, for: remoteMessage.id) else {
            return
        }

        Logger.remoteMessaging.info("Home message dismissed: \(remoteMessage.id)")
        await remoteMessagingStore.dismissRemoteMessage(withID: remoteMessage.id)

        if isCurrent(presentationContext, for: remoteMessage.id) {
            endCurrentRMFOwnership(replacingWith: nonRemoteHomeMessages)
        }

        notificationCenter.post(name: RemoteMessagingStore.Notifications.remoteMessagesDidChange, object: nil)
    }

    func didAppear(_ homeMessage: HomeMessage, presentationContext: HomeMessagePresentationContext?) {
        guard case .remoteMessage(let remoteMessage) = homeMessage else {
            return
        }

        guard mode == .coordinated else {
            reportRemoteMessageShown(remoteMessage)
            return
        }

        guard let presentationContext,
              isCurrent(presentationContext, for: remoteMessage.id),
              let rmfOwnership,
              rmfOwnership.lease.markShown() else {
            return
        }

        reportRemoteMessageShown(rmfOwnership.message)
    }

    private var nonRemoteHomeMessages: [HomeMessage] {
        homeMessageStorage.messagesToBeShown
    }

    private func buildLegacyHomeMessages(openedAfterIdle: Bool) -> [HomeMessage] {
        var messages = nonRemoteHomeMessages
        guard !isStillOnboarding(),
              let selectedRemoteMessage = selectedRemoteMessage(using: PreparationPolicy(openedAfterIdle: openedAfterIdle)) else {
            return messages
        }

        messages.append(.remoteMessage(remoteMessage: selectedRemoteMessage.message))
        return messages
    }

    private func observeRemoteMessagesChanges() {
        remoteMessagesCancellable = notificationCenter.publisher(for: RemoteMessagingStore.Notifications.remoteMessagesDidChange)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleRemoteMessagesChanged()
                }
            }
    }

    private func handleRemoteMessagesChanged() {
        guard mode == .coordinated else {
            return
        }

        guard isRMFAdmissionEnabled else {
            endCurrentRMFOwnership(replacingWith: nonRemoteHomeMessages)
            return
        }

        guard rmfOwnership != nil || lastPreparationPolicy != nil else {
            publishCoordinatedMessages(nonRemoteHomeMessages)
            return
        }

        reconcileCoordinatedMessages(using: lastPreparationPolicy)
    }

    private func reconcileCoordinatedMessages(using preparationPolicy: PreparationPolicy?) {
        let nonRemoteMessages = nonRemoteHomeMessages

        guard !isStillOnboarding() else {
            endCurrentRMFOwnership(replacingWith: nonRemoteMessages)
            return
        }

        if let rmfOwnership {
            let currentCandidate = remoteMessage(triggerFilter: rmfOwnership.selectedTriggerFilter)
            if let currentCandidate,
               currentCandidate.id == rmfOwnership.lease.messageID,
               HomeMessageViewModelBuilder.canBuild(for: currentCandidate) {
                self.rmfOwnership = RMFOwnership(
                    message: currentCandidate,
                    lease: rmfOwnership.lease,
                    selectedTriggerFilter: rmfOwnership.selectedTriggerFilter,
                    presentationContext: rmfOwnership.presentationContext
                )
                publishCoordinatedMessages(nonRemoteMessages + [.remoteMessage(remoteMessage: currentCandidate)])
                return
            }

            endCurrentRMFOwnership(replacingWith: nonRemoteMessages)
        }

        guard isRMFAdmissionEnabled,
              let preparationPolicy,
              let selectedRemoteMessage = selectedRemoteMessage(using: preparationPolicy),
              HomeMessageViewModelBuilder.canBuild(for: selectedRemoteMessage.message),
              let promoGate,
              let lease = promoGate.tryAcquireRemoteMessageLease(for: selectedRemoteMessage.message.id) else {
            publishCoordinatedMessages(nonRemoteMessages)
            return
        }

        let presentationContext = HomeMessagePresentationContext(
            messageID: selectedRemoteMessage.message.id,
            acquisitionIdentity: lease.acquisitionIdentity
        )
        rmfOwnership = RMFOwnership(
            message: selectedRemoteMessage.message,
            lease: lease,
            selectedTriggerFilter: selectedRemoteMessage.triggerFilter,
            presentationContext: presentationContext
        )
        publishCoordinatedMessages(nonRemoteMessages + [.remoteMessage(remoteMessage: selectedRemoteMessage.message)])
    }

    private func selectedRemoteMessage(using preparationPolicy: PreparationPolicy) -> SelectedRemoteMessage? {
        switch preparationPolicy {
        case .noTrigger:
            return remoteMessage(triggerFilter: .noTrigger).map {
                SelectedRemoteMessage(message: $0, triggerFilter: .noTrigger)
            }
        case .afterIdleThenNoTrigger:
            if let afterIdleMessage = remoteMessage(triggerFilter: .specific(.afterIdle)) {
                return SelectedRemoteMessage(message: afterIdleMessage, triggerFilter: .specific(.afterIdle))
            }
            return remoteMessage(triggerFilter: .noTrigger).map {
                SelectedRemoteMessage(message: $0, triggerFilter: .noTrigger)
            }
        }
    }

    private func remoteMessage(triggerFilter: TriggerFilter) -> RemoteMessageModel? {
        let remoteMessage = remoteMessagingStore.fetchScheduledRemoteMessage(
            surfaces: .newTabPage,
            triggerFilter: triggerFilter
        )
        if let remoteMessage {
            Logger.remoteMessaging.info("Remote message to show: \(remoteMessage.id, privacy: .public)")
        }
        return remoteMessage
    }

    private func publishCoordinatedMessages(_ messages: [HomeMessage]) {
        guard homeMessages != messages else {
            return
        }

        homeMessages = messages
        contentDidChangeSubject.send(())
    }

    private func endCurrentRMFOwnership(replacingWith messages: [HomeMessage]) {
        let ownership = rmfOwnership
        publishCoordinatedMessages(messages)
        ownership?.lease.release()
        rmfOwnership = nil
    }

    private func isCurrent(_ presentationContext: HomeMessagePresentationContext, for messageID: String) -> Bool {
        guard let rmfOwnership else {
            return false
        }
        return presentationContext.messageID == messageID &&
            rmfOwnership.presentationContext == presentationContext
    }

    private func dismissLegacyRemoteMessage(_ remoteMessage: RemoteMessageModel, homeMessage: HomeMessage) async {
        Logger.remoteMessaging.info("Home message dismissed: \(remoteMessage.id)")
        await remoteMessagingStore.dismissRemoteMessage(withID: remoteMessage.id)
        if let index = homeMessages.firstIndex(of: homeMessage) {
            homeMessages.remove(at: index)
        }
        notificationCenter.post(name: RemoteMessagingStore.Notifications.remoteMessagesDidChange, object: nil)
    }

    private func reportRemoteMessageShown(_ remoteMessage: RemoteMessageModel) {
        Logger.remoteMessaging.info("Remote message shown: \(remoteMessage.id, privacy: .public)")
        if remoteMessage.isMetricsEnabled {
            Pixel.fire(pixel: .remoteMessageShown,
                       withAdditionalParameters: additionalParameters(for: remoteMessage.id))
        }

        if !remoteMessagingStore.hasShownRemoteMessage(withID: remoteMessage.id) {
            Logger.remoteMessaging.info("Remote message shown for first time: \(remoteMessage.id, privacy: .public)")
            if remoteMessage.isMetricsEnabled {
                Pixel.fire(pixel: .remoteMessageShownUnique,
                           withAdditionalParameters: additionalParameters(for: remoteMessage.id))
            }
            Task {
                await remoteMessagingStore.updateRemoteMessage(withID: remoteMessage.id, asShown: true)
            }
        }
    }

    private func additionalParameters(for messageID: String) -> [String: String] {
        subscriptionDataReporter.mergeRandomizedParameters(for: .messageID(messageID),
                                                         with: [PixelParameters.message: "\(messageID)"])
    }
}

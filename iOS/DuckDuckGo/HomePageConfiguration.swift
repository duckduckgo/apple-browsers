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

import Foundation
import BrowserServicesKit
import RemoteMessaging
import Common
import FoundationExtensions
import Core
import Bookmarks
import os.log

protocol HomePageMessageShownPixelReporting {
    func fire(_ pixel: Pixel.Event, withAdditionalParameters parameters: [String: String])
}

struct DefaultHomePageMessageShownPixelReporter: HomePageMessageShownPixelReporting {
    func fire(_ pixel: Pixel.Event, withAdditionalParameters parameters: [String: String]) {
        Pixel.fire(pixel: pixel, withAdditionalParameters: parameters)
    }
}

final class HomePageConfiguration: HomePageMessagesConfiguration {

    // MARK: - Messages
    
    private var homeMessageStorage: HomeMessageStorage
    private var remoteMessagingStore: RemoteMessagingStoring
    private let subscriptionDataReporter: SubscriptionDataReporting
    private let isStillOnboarding: () -> Bool
    private let shownPixelReporter: HomePageMessageShownPixelReporting
    private var firstShownReservations = Set<String>()

    var homeMessages: [HomeMessage] = []

    init(variantManager: VariantManager? = nil,
         remoteMessagingStore: RemoteMessagingStoring,
         subscriptionDataReporter: SubscriptionDataReporting,
         isStillOnboarding: @escaping () -> Bool,
         shownPixelReporter: HomePageMessageShownPixelReporting = DefaultHomePageMessageShownPixelReporter()
    ) {
        homeMessageStorage = HomeMessageStorage(variantManager: variantManager)
        self.remoteMessagingStore = remoteMessagingStore
        self.subscriptionDataReporter = subscriptionDataReporter
        self.isStillOnboarding = isStillOnboarding
        self.shownPixelReporter = shownPixelReporter
        homeMessages = buildHomeMessages(openedAfterIdle: false)
    }

    func refresh(openedAfterIdle: Bool = false) {
        homeMessages = buildHomeMessages(openedAfterIdle: openedAfterIdle)
    }

    private func buildHomeMessages(openedAfterIdle: Bool) -> [HomeMessage] {
        var messages = homeMessageStorage.messagesToBeShown

        if isStillOnboarding() {
            return messages
        }

        guard let remoteMessage = remoteMessageToShow(openedAfterIdle: openedAfterIdle) else {
            return messages
        }

        messages.append(remoteMessage)
        return messages
    }

    private func remoteMessageToShow(openedAfterIdle: Bool) -> HomeMessage? {
        let remoteMessageToPresent: RemoteMessageModel?
        if openedAfterIdle,
           let idleMessage = remoteMessagingStore.fetchScheduledRemoteMessage(surfaces: .newTabPage, triggerFilter: .specific(.afterIdle)) {
            remoteMessageToPresent = idleMessage
        } else {
            remoteMessageToPresent = remoteMessagingStore.fetchScheduledRemoteMessage(surfaces: .newTabPage, triggerFilter: .noTrigger)
        }
        guard let remoteMessageToPresent else { return nil }
        Logger.remoteMessaging.info("Remote message to show: \(remoteMessageToPresent.id, privacy: .public)")
        return .remoteMessage(remoteMessage: remoteMessageToPresent)
    }

    @MainActor
    func dismissHomeMessage(_ homeMessage: HomeMessage) async {
        switch homeMessage {
        case .remoteMessage(let remoteMessage):
            Logger.remoteMessaging.info("Home message dismissed: \(remoteMessage.id)")
            await remoteMessagingStore.dismissRemoteMessage(withID: remoteMessage.id)
            if let index = homeMessages.firstIndex(of: homeMessage) {
                homeMessages.remove(at: index)
            }
            NotificationCenter.default.post(name: RemoteMessagingStore.Notifications.remoteMessagesDidChange, object: nil)
        default:
            break
        }
    }

    @MainActor
    func didAppear(_ homeMessage: HomeMessage) {
        switch homeMessage {
        case .remoteMessage(let remoteMessage):
            Logger.remoteMessaging.info("Remote message shown: \(remoteMessage.id, privacy: .public)")
            if remoteMessage.isMetricsEnabled {
                shownPixelReporter.fire(
                    .remoteMessageShown,
                    withAdditionalParameters: additionalParameters(for: remoteMessage.id)
                )
            }

            if !remoteMessagingStore.hasShownRemoteMessage(withID: remoteMessage.id),
               firstShownReservations.insert(remoteMessage.id).inserted {
                Logger.remoteMessaging.info("Remote message shown for first time: \(remoteMessage.id, privacy: .public)")
                if remoteMessage.isMetricsEnabled {
                    shownPixelReporter.fire(
                        .remoteMessageShownUnique,
                        withAdditionalParameters: additionalParameters(for: remoteMessage.id)
                    )
                }
                Task {
                    await remoteMessagingStore.updateRemoteMessage(withID: remoteMessage.id, asShown: true)
                }
            }

        default:
            break
        }

    }

    private func additionalParameters(for messageID: String) -> [String: String] {
        subscriptionDataReporter.mergeRandomizedParameters(for: .messageID(messageID),
                                                         with: [PixelParameters.message: "\(messageID)"])
    }
}

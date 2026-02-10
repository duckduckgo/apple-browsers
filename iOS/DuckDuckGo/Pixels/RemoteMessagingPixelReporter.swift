//
//  RemoteMessagingPixelReporter.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import RemoteMessaging
import Core

enum RemoteMessagePixelDismissType: String {
    case closeButton = "close_button"
    case pullDown = "pull_down"
    case primaryAction = "primary_action"
}

protocol RemoteMessagingPixelReporting {
    func measureRemoteMessageAppeared(_ remoteMessage: RemoteMessageModel, hasAlreadySeenMessage: Bool)
    func measureRemoteMessageDismissed(_ remoteMessage: RemoteMessageModel, dismissType: RemoteMessagePixelDismissType?)
    func measureRemoteMessageActionClicked(_ remoteMessage: RemoteMessageModel)
    func measureRemoteMessagePrimaryActionClicked(_ remoteMessage: RemoteMessageModel)
    func measureRemoteMessageSecondaryActionClicked(_ remoteMessage: RemoteMessageModel)
    func measureRemoteMessageSheetShown(_ remoteMessage: RemoteMessageModel, sheetResult: Bool)
    func measureRemoteMessageCardShown(_ remoteMessage: RemoteMessageModel, cardId: String)
    func measureRemoteMessageCardClicked(_ remoteMessage: RemoteMessageModel, cardId: String)
    func measureRemoteMessageImageLoadSuccess(_ remoteMessage: RemoteMessageModel)
    func measureRemoteMessageImageLoadFailed(_ remoteMessage: RemoteMessageModel)
}

extension RemoteMessagingPixelReporting {

    func measureRemoteMessageDismissed(_ remoteMessage: RemoteMessageModel) {
        measureRemoteMessageDismissed(remoteMessage, dismissType: nil)
    }

}

final class RemoteMessagePixelReporter: RemoteMessagingPixelReporting {
    private let pixelFiring: PixelFiring.Type
    private let parameterRandomiser: (SubscriptionDataReportingUseCase, _ parameters: [String: String]) -> [String: String]

    init(
        pixelFiring: PixelFiring.Type = Pixel.self,
        parameterRandomiser: @escaping (SubscriptionDataReportingUseCase, [String: String]) -> [String: String]
    ) {
        self.pixelFiring = pixelFiring
        self.parameterRandomiser = parameterRandomiser
    }

    func measureRemoteMessageAppeared(_ remoteMessage: RemoteMessageModel, hasAlreadySeenMessage: Bool) {
        firePixelIfMetricsEnabled(.remoteMessageShown, for: remoteMessage)

        if !hasAlreadySeenMessage {
            firePixelIfMetricsEnabled(.remoteMessageShownUnique, for: remoteMessage)
        }
    }

    func measureRemoteMessageDismissed(_ remoteMessage: RemoteMessageModel, dismissType: RemoteMessagePixelDismissType?) {
        let additionalParameters = dismissType.flatMap { [PixelParameters.dismissType: $0.rawValue] } ?? [:]
        firePixelIfMetricsEnabled(.remoteMessageDismissed, for: remoteMessage, additionalParameters: additionalParameters)
    }

    func measureRemoteMessageActionClicked(_ remoteMessage: RemoteMessageModel) {
        firePixelIfMetricsEnabled(.remoteMessageActionClicked, for: remoteMessage)
    }

    func measureRemoteMessagePrimaryActionClicked(_ remoteMessage: RemoteMessageModel) {
        firePixelIfMetricsEnabled(.remoteMessagePrimaryActionClicked, for: remoteMessage)
    }

    func measureRemoteMessageSecondaryActionClicked(_ remoteMessage: RemoteMessageModel) {
        firePixelIfMetricsEnabled(.remoteMessageSecondaryActionClicked, for: remoteMessage)
    }

    func measureRemoteMessageSheetShown(_ remoteMessage: RemoteMessageModel, sheetResult: Bool) {
        firePixelIfMetricsEnabled(.remoteMessageSheet, for: remoteMessage, additionalParameters: [PixelParameters.sheetResult: "\(sheetResult)"])
    }

    func measureRemoteMessageCardShown(_ remoteMessage: RemoteMessageModel, cardId: String) {
        firePixelIfMetricsEnabled(.remoteMessageCardShown, for: remoteMessage, additionalParameters: [PixelParameters.card: cardId])
    }

    func measureRemoteMessageCardClicked(_ remoteMessage: RemoteMessageModel, cardId: String) {
        firePixelIfMetricsEnabled(.remoteMessageCardClicked, for: remoteMessage, additionalParameters: [PixelParameters.card: cardId])
    }

    func measureRemoteMessageImageLoadSuccess(_ remoteMessage: RemoteMessageModel) {
        firePixelIfMetricsEnabled(.remoteMessageImageLoadSuccess, for: remoteMessage)
    }

    func measureRemoteMessageImageLoadFailed(_ remoteMessage: RemoteMessageModel) {
        firePixelIfMetricsEnabled(.remoteMessageImageLoadFailed, for: remoteMessage)
    }

    private func firePixelIfMetricsEnabled(_ pixel: Pixel.Event, for remoteMessage: RemoteMessageModel, additionalParameters: [String: String] = [:]) {
        guard remoteMessage.isMetricsEnabled else { return }

        let remoteMessageID = remoteMessage.id
        let randomisedParameter = parameterRandomiser(.messageID(remoteMessageID), [PixelParameters.message: "\(remoteMessageID)"])
        let parameters = randomisedParameter.merging(additionalParameters) { $1 }

        pixelFiring.fire(pixel, withAdditionalParameters: parameters)
    }
}

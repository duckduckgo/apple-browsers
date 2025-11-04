//
//  MockRemoteMessagingPixelReporter.swift
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

import Foundation
import RemoteMessaging
@testable import DuckDuckGo

final class MockRemoteMessagingPixelReporter: RemoteMessagingPixelReporting {

    // MARK: - Appeared
    var didCallMeasureRemoteMessageAppeared = false
    var capturedAppearedMessage: RemoteMessageModel?
    var capturedHasAlreadySeenMessage: Bool?

    func measureRemoteMessageAppeared(_ remoteMessage: RemoteMessageModel, hasAlreadySeenMessage: Bool) {
        didCallMeasureRemoteMessageAppeared = true
        capturedAppearedMessage = remoteMessage
        capturedHasAlreadySeenMessage = hasAlreadySeenMessage
    }

    // MARK: - Dismissed
    var didCallMeasureRemoteMessageDismissed = false
    var capturedDismissedMessage: RemoteMessageModel?
    var capturedDismissType: RemoteMessagePixelDismissType?

    func measureRemoteMessageDismissed(_ remoteMessage: RemoteMessageModel, dismissType: RemoteMessagePixelDismissType?) {
        didCallMeasureRemoteMessageDismissed = true
        capturedDismissedMessage = remoteMessage
        capturedDismissType = dismissType
    }

    // MARK: - Action Clicked
    var didCallMeasureRemoteMessageActionClicked = false
    var capturedActionClickedMessage: RemoteMessageModel?

    func measureRemoteMessageActionClicked(_ remoteMessage: RemoteMessageModel) {
        didCallMeasureRemoteMessageActionClicked = true
        capturedActionClickedMessage = remoteMessage
    }

    // MARK: - Primary Action Clicked
    var didCallMeasureRemoteMessagePrimaryActionClicked = false
    var capturedPrimaryActionClickedMessage: RemoteMessageModel?

    func measureRemoteMessagePrimaryActionClicked(_ remoteMessage: RemoteMessageModel) {
        didCallMeasureRemoteMessagePrimaryActionClicked = true
        capturedPrimaryActionClickedMessage = remoteMessage
    }

    // MARK: - Secondary Action Clicked
    var didCallMeasureRemoteMessageSecondaryActionClicked = false
    var capturedSecondaryActionClickedMessage: RemoteMessageModel?

    func measureRemoteMessageSecondaryActionClicked(_ remoteMessage: RemoteMessageModel) {
        didCallMeasureRemoteMessageSecondaryActionClicked = true
        capturedSecondaryActionClickedMessage = remoteMessage
    }

    // MARK: - Sheet Shown
    var didCallMeasureRemoteMessageSheetShown = false
    var capturedSheetShownMessage: RemoteMessageModel?
    var capturedSheetResult: Bool?

    func measureRemoteMessageSheetShown(_ remoteMessage: RemoteMessageModel, sheetResult: Bool) {
        didCallMeasureRemoteMessageSheetShown = true
        capturedSheetShownMessage = remoteMessage
        capturedSheetResult = sheetResult
    }

    // MARK: - Card Shown
    var didCallMeasureRemoteMessageCardShown = false
    var capturedCardShownMessage: RemoteMessageModel?
    var capturedCardShownCardId: String?

    func measureRemoteMessageCardShown(_ remoteMessage: RemoteMessageModel, cardId: String) {
        didCallMeasureRemoteMessageCardShown = true
        capturedCardShownMessage = remoteMessage
        capturedCardShownCardId = cardId
    }

    // MARK: - Card Clicked
    var didCallMeasureRemoteMessageCardClicked = false
    var capturedCardClickedMessage: RemoteMessageModel?
    var capturedCardClickedCardId: String?

    func measureRemoteMessageCardClicked(_ remoteMessage: RemoteMessageModel, cardId: String) {
        didCallMeasureRemoteMessageCardClicked = true
        capturedCardClickedMessage = remoteMessage
        capturedCardClickedCardId = cardId
    }

}

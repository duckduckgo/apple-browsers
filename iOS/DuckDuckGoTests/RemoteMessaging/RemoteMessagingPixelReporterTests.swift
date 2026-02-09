//
//  RemoteMessagingPixelReporterTests.swift
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
import Testing
import RemoteMessaging
import Core
@testable import DuckDuckGo

@Suite("RMF - Pixel Reporter Tests", .serialized)
final class RemoteMessagingPixelReporterTests {
    private let mockParameterRandomiser: MockParameterRandomiser
    private let sut: RemoteMessagePixelReporter

    init() {
        let mockParameterRandomiser = MockParameterRandomiser()
        self.mockParameterRandomiser = mockParameterRandomiser
        sut = RemoteMessagePixelReporter(
            pixelFiring: PixelFiringMock.self,
            parameterRandomiser: { useCase, parameters in
                mockParameterRandomiser.mergeRandomizedParameters(for: useCase, with: parameters)
            }
        )
    }

    deinit {
        PixelFiringMock.tearDown()
    }

    // MARK: - Message Appeared Tests

    @Test("Check Pixel Fires When Message Appears For First Time")
    func whenMessageAppearsForFirstTimeThenBothPixelsFire() {
        // GIVEN
        let message = makeRemoteMessage(id: "test-message-1", isMetricsEnabled: true)
        #expect(PixelFiringMock.allPixelsFired.isEmpty)

        // WHEN
        sut.measureRemoteMessageAppeared(message, hasAlreadySeenMessage: false)

        // THEN
        let capturedPixels = PixelFiringMock.allPixelsFired.compactMap(\.pixelName)
        #expect(!PixelFiringMock.allPixelsFired.isEmpty)
        #expect(PixelFiringMock.allPixelsFired.count == 2)
        #expect(capturedPixels.first == Pixel.Event.remoteMessageShown.name)
        #expect(capturedPixels.last == Pixel.Event.remoteMessageShownUnique.name)
    }

    @Test("Check Only Shown Pixel Fires When Message Appears Again")
    func whenMessageAppearsAgainThenOnlyShownPixelFires() {
        // GIVEN
        let message = makeRemoteMessage(id: "test-message-1", isMetricsEnabled: true)
        #expect(PixelFiringMock.allPixelsFired.isEmpty)

        // WHEN
        sut.measureRemoteMessageAppeared(message, hasAlreadySeenMessage: true)

        // THEN
        #expect(!PixelFiringMock.allPixelsFired.isEmpty)
        #expect(PixelFiringMock.allPixelsFired.count == 1)
        #expect(PixelFiringMock.allPixelsFired.first?.pixelName == Pixel.Event.remoteMessageShown.name)
    }

    @Test("Check Message ID Is Included In Parameters")
    func whenMessageAppearsThenMessageIDIsIncludedInParameters() {
        // GIVEN
        let message = makeRemoteMessage(id: "test-message-1", isMetricsEnabled: true)
        mockParameterRandomiser.parametersToReturn = [PixelParameters.message: "randomised-parameter-1"]

        // WHEN
        sut.measureRemoteMessageAppeared(message, hasAlreadySeenMessage: false)

        // THEN
        #expect(mockParameterRandomiser.didCallMergeRandomizedParameters)
        #expect(mockParameterRandomiser.capturedParameters[PixelParameters.message] == "test-message-1")
        #expect(PixelFiringMock.lastParams?[PixelParameters.message] == "randomised-parameter-1")
    }

    @Test("Check No Pixels Fire When Metrics Are Disabled")
    func whenMetricsDisabledThenNoPixelsFire() {
        // GIVEN
        let message = makeRemoteMessage(id: "test-message-1", isMetricsEnabled: false)

        // WHEN
        sut.measureRemoteMessageAppeared(message, hasAlreadySeenMessage: false)

        // THEN
        #expect(PixelFiringMock.allPixelsFired.isEmpty)
    }

    // MARK: - Dismiss Tests

    @Test("Check Dismissed Pixel Fires With Close Button Type")
    func whenMessageDismissedWithCloseButtonThenPixelFiresWithDismissType() {
        // GIVEN
        let message = makeRemoteMessage(id: "test-message-1", isMetricsEnabled: true)

        // WHEN
        sut.measureRemoteMessageDismissed(message, dismissType: .closeButton)

        // THEN
        #expect(PixelFiringMock.allPixelsFired.count == 1)
        #expect(PixelFiringMock.lastPixelName == Pixel.Event.remoteMessageDismissed.name)
        #expect(PixelFiringMock.lastParams?[PixelParameters.dismissType] == "close_button")
    }

    @Test("Check Dismissed Pixel Fires With Pull Down Type")
    func whenMessageDismissedWithPullDownThenPixelFiresWithDismissType() {
        // GIVEN
        let message = makeRemoteMessage(id: "test-message-1", isMetricsEnabled: true)

        // WHEN
        sut.measureRemoteMessageDismissed(message, dismissType: .pullDown)

        // THEN
        #expect(PixelFiringMock.allPixelsFired.count == 1)
        #expect(PixelFiringMock.lastPixelName == Pixel.Event.remoteMessageDismissed.name)
        #expect(PixelFiringMock.lastParams?[PixelParameters.dismissType] == "pull_down")
    }

    @Test("Check Dismissed Pixel Fires With Primary Action Type")
    func whenMessageDismissedWithPrimaryActionThenPixelFiresWithPrimaryActionType() {
        // GIVEN
        let message = makeRemoteMessage(id: "test-message-1", isMetricsEnabled: true)

        // WHEN
        sut.measureRemoteMessageDismissed(message, dismissType: .primaryAction)

        // THEN
        #expect(PixelFiringMock.allPixelsFired.count == 1)
        #expect(PixelFiringMock.lastPixelName == Pixel.Event.remoteMessageDismissed.name)
        #expect(PixelFiringMock.lastParams?[PixelParameters.dismissType] == "primary_action")
    }

    @Test("Check Dismissed Pixel Fires Without Dismiss Type When Nil")
    func whenMessageDismissedWithoutTypeThenPixelFiresWithoutDismissType() {
        // GIVEN
        let message = makeRemoteMessage(id: "test-message-1", isMetricsEnabled: true)

        // WHEN
        sut.measureRemoteMessageDismissed(message, dismissType: nil)

        // THEN
        #expect(PixelFiringMock.allPixelsFired.count == 1)
        #expect(PixelFiringMock.lastPixelName == Pixel.Event.remoteMessageDismissed.name)
        #expect(PixelFiringMock.lastParams?[PixelParameters.dismissType] == nil)
    }

    @Test("Check Default Extension Method Works")
    func whenMessageDismissedUsingDefaultExtensionThenPixelFiresWithoutDismissType() {
        // GIVEN
        let message = makeRemoteMessage(id: "test-message-8", isMetricsEnabled: true)

        // WHEN
        sut.measureRemoteMessageDismissed(message) // Using extension default

        // THEN
        #expect(PixelFiringMock.allPixelsFired.count == 1)
        #expect(PixelFiringMock.lastPixelName == Pixel.Event.remoteMessageDismissed.name)
        #expect(PixelFiringMock.lastParams?[PixelParameters.dismissType] == nil)
    }

    // MARK: - Action Tests

    @Test("Check Action Clicked Pixel Fires")
    func whenActionClickedThenPixelFires() {
        // GIVEN
        let message = makeRemoteMessage(id: "test-message-1", isMetricsEnabled: true)

        // WHEN
        sut.measureRemoteMessageActionClicked(message)

        // THEN
        #expect(PixelFiringMock.allPixelsFired.count == 1)
        #expect(PixelFiringMock.lastPixelName == Pixel.Event.remoteMessageActionClicked.name)
    }

    @Test("Check Primary Action Clicked Pixel Fires")
    func whenPrimaryActionClickedThenPixelFires() {
        // GIVEN
        let message = makeRemoteMessage(id: "test-message-1", isMetricsEnabled: true)

        // WHEN
        sut.measureRemoteMessagePrimaryActionClicked(message)

        // THEN
        #expect(PixelFiringMock.allPixelsFired.count == 1)
        #expect(PixelFiringMock.lastPixelName == Pixel.Event.remoteMessagePrimaryActionClicked.name)
    }

    @Test("Check Secondary Action Clicked Pixel Fires")
    func whenSecondaryActionClickedThenPixelFires() {
        // GIVEN
        let message = makeRemoteMessage(id: "test-message-11", isMetricsEnabled: true)

        // WHEN
        sut.measureRemoteMessageSecondaryActionClicked(message)

        // THEN
        #expect(PixelFiringMock.allPixelsFired.count == 1)
        #expect(PixelFiringMock.lastPixelName == Pixel.Event.remoteMessageSecondaryActionClicked.name)
    }

    // MARK: - Sheet Tests

    @Test(
        "Check Sheet Shown Pixel Fires With Result",
        arguments: [true, false]
    )
    func whenSheetShownThenPixelFiresWithResult(sheetResult: Bool) {
        // GIVEN
        let message = makeRemoteMessage(id: "test-message-1", isMetricsEnabled: true)
        mockParameterRandomiser.parametersToReturn = [PixelParameters.message: "randomised-parameter-1"]

        // WHEN
        sut.measureRemoteMessageSheetShown(message, sheetResult: sheetResult)

        // THEN
        #expect(PixelFiringMock.allPixelsFired.count == 1)
        #expect(PixelFiringMock.lastPixelName == Pixel.Event.remoteMessageSheet.name)
        #expect(PixelFiringMock.lastParams?[PixelParameters.message] == "randomised-parameter-1")
        #expect(PixelFiringMock.lastParams?[PixelParameters.sheetResult] == "\(sheetResult)")
    }

    // MARK: - Card Tests

    @Test("Check Card Shown Pixel Fires With Card ID")
    func whenCardShownThenPixelFiresWithCardID() {
        // GIVEN
        let message = makeRemoteMessage(id: "test-message-1", isMetricsEnabled: true)
        mockParameterRandomiser.parametersToReturn = [PixelParameters.message: "randomised-parameter-1"]
        let cardId = "card-123"

        // WHEN
        sut.measureRemoteMessageCardShown(message, cardId: cardId)

        // THEN
        #expect(PixelFiringMock.allPixelsFired.count == 1)
        #expect(PixelFiringMock.lastPixelName == Pixel.Event.remoteMessageCardShown.name)
        #expect(PixelFiringMock.lastParams?[PixelParameters.message] == "randomised-parameter-1")
        #expect(PixelFiringMock.lastParams?[PixelParameters.card] == cardId)
    }

    @Test("Check Card Clicked Pixel Fires With Card ID")
    func whenCardClickedThenPixelFiresWithCardID() {
        // GIVEN
        let message = makeRemoteMessage(id: "test-message-1", isMetricsEnabled: true)
        mockParameterRandomiser.parametersToReturn = [PixelParameters.message: "randomised-parameter-1"]
        let cardId = "card-456"

        // WHEN
        sut.measureRemoteMessageCardClicked(message, cardId: cardId)

        // THEN
        #expect(PixelFiringMock.allPixelsFired.count == 1)
        #expect(PixelFiringMock.lastPixelName == Pixel.Event.remoteMessageCardClicked.name)
        #expect(PixelFiringMock.lastParams?[PixelParameters.message] == "randomised-parameter-1")
        #expect(PixelFiringMock.lastParams?[PixelParameters.card] == cardId)
    }

    // MARK: - Metrics Disabled Tests

    @Test("Check No Pixel Fires When Metrics Disabled For Dismiss")
    func whenMetricsDisabledThenDismissPixelDoesNotFire() {
        // GIVEN
        let message = makeRemoteMessage(id: "test-message-1", isMetricsEnabled: false)

        // WHEN
        sut.measureRemoteMessageDismissed(message, dismissType: .closeButton)

        // THEN
        #expect(PixelFiringMock.allPixelsFired.isEmpty)
    }

    @Test("Check No Pixel Fires When Metrics Disabled For Actions")
    func whenMetricsDisabledThenActionPixelsDoNotFire() {
        // GIVEN
        let message = makeRemoteMessage(id: "test-message-1", isMetricsEnabled: false)

        // WHEN
        sut.measureRemoteMessageActionClicked(message)
        sut.measureRemoteMessagePrimaryActionClicked(message)
        sut.measureRemoteMessageSecondaryActionClicked(message)

        // THEN
        #expect(PixelFiringMock.allPixelsFired.isEmpty)
        #expect(PixelFiringMock.lastParams == nil)
    }

    @Test("Check No Pixel Fires When Metrics Disabled For Sheet")
    func whenMetricsDisabledThenSheetPixelDoesNotFire() {
        // GIVEN
        let message = makeRemoteMessage(id: "test-message-1", isMetricsEnabled: false)

        // WHEN
        sut.measureRemoteMessageSheetShown(message, sheetResult: true)

        // THEN
        #expect(PixelFiringMock.allPixelsFired.isEmpty)
        #expect(PixelFiringMock.lastParams == nil)
    }

    @Test("Check No Pixel Fires When Metrics Disabled For Cards")
    func whenMetricsDisabledThenCardPixelsDoNotFire() {
        // GIVEN
        let message = makeRemoteMessage(id: "test-message-1", isMetricsEnabled: false)

        // WHEN
        sut.measureRemoteMessageCardShown(message, cardId: "card-789")
        sut.measureRemoteMessageCardClicked(message, cardId: "card-789")

        // THEN
        #expect(PixelFiringMock.allPixelsFired.isEmpty)
        #expect(PixelFiringMock.lastParams == nil)
    }

    @Test("Check Image Load Success Pixel Fires")
    func whenImageLoadSuccessThenPixelFires() {
        let message = makeRemoteMessage(id: "test-message-1", isMetricsEnabled: true)
        mockParameterRandomiser.parametersToReturn = [PixelParameters.message: "randomised-parameter-1"]

        sut.measureRemoteMessageImageLoadSuccess(message)

        #expect(PixelFiringMock.allPixelsFired.count == 1)
        #expect(PixelFiringMock.lastPixelName == Pixel.Event.remoteMessageImageLoadSuccess.name)
        #expect(PixelFiringMock.lastParams?[PixelParameters.message] == "randomised-parameter-1")
    }

    @Test("Check Image Load Failed Pixel Fires")
    func whenImageLoadFailedThenPixelFires() {
        let message = makeRemoteMessage(id: "test-message-1", isMetricsEnabled: true)
        mockParameterRandomiser.parametersToReturn = [PixelParameters.message: "randomised-parameter-1"]

        sut.measureRemoteMessageImageLoadFailed(message)

        #expect(PixelFiringMock.allPixelsFired.count == 1)
        #expect(PixelFiringMock.lastPixelName == Pixel.Event.remoteMessageImageLoadFailed.name)
        #expect(PixelFiringMock.lastParams?[PixelParameters.message] == "randomised-parameter-1")
    }

    @Test("Check No Image Pixel Fires When Metrics Disabled")
    func whenMetricsDisabledThenImagePixelsDoNotFire() {
        let message = makeRemoteMessage(id: "test-message-1", isMetricsEnabled: false)

        sut.measureRemoteMessageImageLoadSuccess(message)
        sut.measureRemoteMessageImageLoadFailed(message)

        #expect(PixelFiringMock.allPixelsFired.isEmpty)
        #expect(PixelFiringMock.lastParams == nil)
    }
}

// MARK: - Helper Methods

private extension RemoteMessagingPixelReporterTests {

    func makeRemoteMessage(id: String, isMetricsEnabled: Bool) -> RemoteMessageModel {
        RemoteMessageModel(
            id: id,
            surfaces: .newTabPage,
            content: nil,
            matchingRules: [],
            exclusionRules: [],
            isMetricsEnabled: isMetricsEnabled
        )
    }

}

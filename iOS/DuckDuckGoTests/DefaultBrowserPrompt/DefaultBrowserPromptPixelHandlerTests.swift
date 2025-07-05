//
//  DefaultBrowserPromptPixelHandlerTests.swift
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

import Testing
import Core
@testable import DuckDuckGo

@Suite("Default Browser Prompt - Pixel Handler Tests")
final class DefaultBrowserPromptPixelHandlerTests {

    deinit {
        PixelFiringMock.tearDown()
    }

    @Test(
        "Check Modal Shown Event Fire Correct Pixel",
        arguments: [
            2, 4, 6, 8, 10, 12, 14, 16, 18, 20
        ]
    )
    func whenModalShownEventFiredThenCorrectPixelIsSent(numberOfModalShown: Int) {
        // GIVEN
        let sut = DefaultBrowserPromptPixelHandler(pixelFiring: PixelFiringMock.self)

        // WHEN
        sut.fire(.modalShown(numberOfModalShown: numberOfModalShown))

        // THEN
        let expectedParameter = numberOfModalShown <= 10 ? String(numberOfModalShown) : "10+"
        #expect(PixelFiringMock.lastPixelInfo?.pixelName == Pixel.Event.defaultBrowserPromptModalShown.name)
        #expect(PixelFiringMock.lastPixelInfo?.params == [PixelParameters.defaultBrowserPromptNumberOfModalsShown: expectedParameter])
    }

    @Test(
        "Check Modal Actioned Event Fire Correct Pixel",
        arguments: [
            2, 4, 6, 8, 10, 12, 14, 16, 18, 20
        ]
    )
    func whenModalActionedEventFiredThenCorrectPixelIsSent(numberOfModalShown: Int) {
        // GIVEN
        let sut = DefaultBrowserPromptPixelHandler(pixelFiring: PixelFiringMock.self)

        // WHEN
        sut.fire(.modalActioned(numberOfModalShown: numberOfModalShown))

        // THEN
        let expectedParameter = numberOfModalShown <= 10 ? String(numberOfModalShown) : "10+"
        #expect(PixelFiringMock.lastPixelInfo?.pixelName == Pixel.Event.defaultBrowserPromptModalSetAsDefaultBrowserButtonTapped.name)
        #expect(PixelFiringMock.lastPixelInfo?.params == [PixelParameters.defaultBrowserPromptNumberOfModalsShown: expectedParameter])
    }

    @Test("Check Modal Dismissed Event Fire Correct Pixel")
    func whenModalDismissedEventFiredThenCorrectPixelIsSent() {
        // GIVEN
        let sut = DefaultBrowserPromptPixelHandler(pixelFiring: PixelFiringMock.self)

        // WHEN
        sut.fire(.modalDismissed)

        // THEN
        #expect(PixelFiringMock.lastPixelInfo?.pixelName == Pixel.Event.defaultBrowserPromptModalClosedButtonTapped.name)
        #expect(PixelFiringMock.lastPixelInfo?.params?.isEmpty == true)
    }

    @Test("Check Modal Dismissed Permanently Event Fire Correct Pixel")
    func whenModalDismissedPermanentlyEventFiredThenCorrectPixelIsSent() {
        // GIVEN
        let sut = DefaultBrowserPromptPixelHandler(pixelFiring: PixelFiringMock.self)

        // WHEN
        sut.fire(.modalDismissedPermanently)

        // THEN
        #expect(PixelFiringMock.lastPixelInfo?.pixelName == Pixel.Event.defaultBrowserPromptModalDoNotAskAgainButtonTapped.name)
        #expect(PixelFiringMock.lastPixelInfo?.params?.isEmpty == true)
    }
}

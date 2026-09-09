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
@_spi(Testing) import PixelKit

@Suite("Default Browser Prompt - Pixel Handler Tests", .serialized)
final class DefaultBrowserPromptPixelHandlerTests {

    @Test(
        "Check Modal Shown Event Fire Correct Pixel",
        arguments: [
            2, 4, 6, 8, 10, 12, 14, 16, 18, 20
        ]
    )
    func whenModalShownEventFiredThenCorrectPixelIsSent(numberOfModalShown: Int) {
        // GIVEN
        let pixelKitMock = PixelKitMock()
        let sut = DefaultBrowserPromptPixelHandler(pixelFiring: pixelKitMock)

        // WHEN
        sut.fire(.activeModalShown(numberOfModalShown: numberOfModalShown))

        // THEN
        let expectedParameter = numberOfModalShown <= 10 ? String(numberOfModalShown) : "10+"
        #expect(pixelKitMock.actualFireCalls.last?.pixel.name == Pixel.Event.defaultBrowserPromptModalShown.name)
        #expect(pixelKitMock.actualFireCalls.last?.additionalParameters == [PixelParameters.defaultBrowserPromptNumberOfModalsShown: expectedParameter])
    }

    @Test(
        "Check Modal Actioned Event Fire Correct Pixel",
        arguments: [
            2, 4, 6, 8, 10, 12, 14, 16, 18, 20
        ]
    )
    func whenModalActionedEventFiredThenCorrectPixelIsSent(numberOfModalShown: Int) {
        // GIVEN
        let pixelKitMock = PixelKitMock()
        let sut = DefaultBrowserPromptPixelHandler(pixelFiring: pixelKitMock)

        // WHEN
        sut.fire(.activeModalActioned(numberOfModalShown: numberOfModalShown))

        // THEN
        let expectedParameter = numberOfModalShown <= 10 ? String(numberOfModalShown) : "10+"
        #expect(pixelKitMock.actualFireCalls.last?.pixel.name == Pixel.Event.defaultBrowserPromptModalSetAsDefaultBrowserButtonTapped.name)
        #expect(pixelKitMock.actualFireCalls.last?.additionalParameters == [PixelParameters.defaultBrowserPromptNumberOfModalsShown: expectedParameter])
    }

    @Test("Check Modal Dismissed Event Fire Correct Pixel")
    func whenModalDismissedEventFiredThenCorrectPixelIsSent() {
        // GIVEN
        let pixelKitMock = PixelKitMock()
        let sut = DefaultBrowserPromptPixelHandler(pixelFiring: pixelKitMock)

        // WHEN
        sut.fire(.activeModalDismissed)

        // THEN
        #expect(pixelKitMock.actualFireCalls.last?.pixel.name == Pixel.Event.defaultBrowserPromptModalClosedButtonTapped.name)
        #expect(pixelKitMock.actualFireCalls.last?.additionalParameters?.isEmpty == true)
    }

    @Test("Check Modal Dismissed Permanently Event Fire Correct Pixel")
    func whenModalDismissedPermanentlyEventFiredThenCorrectPixelIsSent() {
        // GIVEN
        let pixelKitMock = PixelKitMock()
        let sut = DefaultBrowserPromptPixelHandler(pixelFiring: pixelKitMock)

        // WHEN
        sut.fire(.activeModalDismissedPermanently)

        // THEN
        #expect(pixelKitMock.actualFireCalls.last?.pixel.name == Pixel.Event.defaultBrowserPromptModalDoNotAskAgainButtonTapped.name)
        #expect(pixelKitMock.actualFireCalls.last?.additionalParameters?.isEmpty == true)
    }

    // MARK: - Inactive Browser Prompt

    @Test("Check Inactive User Modal Shown Event Fire Correct Pixel")
    func whenInactiveUserModalShownEventThenCorrectPixelIsSent() async throws {
        // GIVEN
        let pixelKitMock = PixelKitMock()
        let sut = DefaultBrowserPromptPixelHandler(pixelFiring: pixelKitMock)

        // WHEN
        sut.fire(.inactiveModalShown)

        // THEN
        #expect(pixelKitMock.actualFireCalls.last?.pixel.name == Pixel.Event.defaultBrowserPromptInactiveUserModalShown.name)
        #expect(pixelKitMock.actualFireCalls.last?.additionalParameters?.isEmpty == true)
    }

    @Test("Check Inactive User Modal Shown Event Fire Correct Pixel")
    func whenInactiveUserModalDismissEventThenCorrectPixelIsSent() async throws {
        // GIVEN
        let pixelKitMock = PixelKitMock()
        let sut = DefaultBrowserPromptPixelHandler(pixelFiring: pixelKitMock)

        // WHEN
        sut.fire(.inactiveModalDismissed)

        // THEN
        #expect(pixelKitMock.actualFireCalls.last?.pixel.name == Pixel.Event.defaultBrowserPromptInactiveUserModalClosedButtonTapped.name)
        #expect(pixelKitMock.actualFireCalls.last?.additionalParameters?.isEmpty == true)
    }

    @Test("Check Inactive User Modal Shown Event Fire Correct Pixel")
    func whenInactiveUserModalActionedEventThenCorrectPixelIsSent() async throws {
        // GIVEN
        let pixelKitMock = PixelKitMock()
        let sut = DefaultBrowserPromptPixelHandler(pixelFiring: pixelKitMock)

        // WHEN
        sut.fire(.inactiveModalActioned)

        // THEN
        #expect(pixelKitMock.actualFireCalls.last?.pixel.name == Pixel.Event.defaultBrowserPromptInactiveUserModalSetAsDefaultBrowserButtonTapped.name)
        #expect(pixelKitMock.actualFireCalls.last?.additionalParameters?.isEmpty == true)
    }

    @Test("Check Inactive User Modal More Protections Event Fire Correct Pixel")
    func whenInactiveUserModalMoreProtectionEventThenCorrectPixelIsSent() async throws {
        // GIVEN
        let pixelKitMock = PixelKitMock()
        let sut = DefaultBrowserPromptPixelHandler(pixelFiring: pixelKitMock)

        // WHEN
        sut.fire(.inactiveModalMoreProtectionsAction)

        // THEN
        #expect(pixelKitMock.actualFireCalls.last?.pixel.name == Pixel.Event.defaultBrowserPromptInactiveUserModalMoreProtectionsButtonTapped.name)
        #expect(pixelKitMock.actualFireCalls.last?.additionalParameters?.isEmpty == true)
    }
}

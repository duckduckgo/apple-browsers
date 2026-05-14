//
//  NewTabPageNextStepsCardsPixelHandlerTests.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

import NewTabPage
import PixelKit
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class NewTabPageNextStepsCardsPixelHandlerTests: XCTestCase {
    private var pixelHandler: NewTabPageNextStepsCardsPixelHandler!
    private var firedPixels: [(event: PixelKitEvent, frequency: PixelKit.Frequency, includesAppVersionParameter: Bool)] = []

    override func setUp() async throws {
        firedPixels = []
        pixelHandler = NewTabPageNextStepsCardsPixelHandler { event, frequency, includesAppVersionParameter in
            self.firedPixels.append((event, frequency, includesAppVersionParameter))
        }
    }

    override func tearDown() {
        pixelHandler = nil
        firedPixels = []
    }

    // MARK: - Shown pixels

    func testWhenFireAddToDockPresentedPixelIfNeededCalled_WithAddAppToDockMacCard_ThenPixelIsFired() {
        // WHEN
        pixelHandler.fireAddToDockPresentedPixelIfNeeded([.defaultApp, .addAppToDockMac])

        // THEN
        XCTAssertEqual(firedPixels.count, 1)
        XCTAssertEqual(firedPixels.first?.event.name, GeneralPixel.addToDockNewTabPageCardPresented.name)
        XCTAssertEqual(firedPixels.first?.frequency, .uniqueByName)
        XCTAssertEqual(firedPixels.first?.includesAppVersionParameter, false)
    }

    func testWhenFireAddToDockPresentedPixelIfNeededCalled_WithoutAddAppToDockMacCard_ThenPixelIsNotFired() {
        // WHEN
        pixelHandler.fireAddToDockPresentedPixelIfNeeded([.defaultApp])

        // THEN
        XCTAssertTrue(firedPixels.isEmpty, "Expected no pixels to be fired, but fired pixels: \(firedPixels)")
    }

    func testWhenFireNextStepsCardShownPixelsCalled_WithAddToDock_ThenShownPixelIsFired() {
        pixelHandler.fireNextStepsCardShownPixels([.addAppToDockMac])

        XCTAssertEqual(firedPixels.count, 1)
        let expectedEvent = NewTabPagePixel.nextStepsCardShown(NewTabPageDataModel.CardID.addAppToDockMac.rawValue)
        XCTAssertEqual(firedPixels.first?.event.name, expectedEvent.name)
        XCTAssertEqual(firedPixels.first?.frequency, .uniqueByNameAndParameters)
        XCTAssertEqual(firedPixels.first?.includesAppVersionParameter, false)
    }

    func testWhenFireNextStepsCardShownPixelsCalled_WithDuckplayer_ThenShownPixelIsFired() {
        pixelHandler.fireNextStepsCardShownPixels([.duckplayer])

        XCTAssertEqual(firedPixels.count, 1)
        let expectedEvent = NewTabPagePixel.nextStepsCardShown(NewTabPageDataModel.CardID.duckplayer.rawValue)
        XCTAssertEqual(firedPixels.first?.event.name, expectedEvent.name)
        XCTAssertEqual(firedPixels.first?.frequency, .uniqueByNameAndParameters)
        XCTAssertEqual(firedPixels.first?.includesAppVersionParameter, false)
    }

    func testWhenFireNextStepsCardShownPixelsCalled_WithSubscription_ThenShownPixelIsFired() {
        pixelHandler.fireNextStepsCardShownPixels([.subscription])

        XCTAssertEqual(firedPixels.count, 1)
        let expectedEvent = NewTabPagePixel.nextStepsCardShown(NewTabPageDataModel.CardID.subscription.rawValue)
        XCTAssertEqual(firedPixels.first?.event.name, expectedEvent.name)
        XCTAssertEqual(firedPixels.first?.frequency, .uniqueByNameAndParameters)
        XCTAssertEqual(firedPixels.first?.includesAppVersionParameter, false)
    }

    func testWhenFireNextStepsCardShownPixelsCalled_WithDefaultApp_ThenShownPixelIsFired() {
        pixelHandler.fireNextStepsCardShownPixels([.defaultApp])

        XCTAssertEqual(firedPixels.count, 1)
        let expectedEvent = NewTabPagePixel.nextStepsCardShown(NewTabPageDataModel.CardID.defaultApp.rawValue)
        XCTAssertEqual(firedPixels.first?.event.name, expectedEvent.name)
        XCTAssertEqual(firedPixels.first?.frequency, .uniqueByNameAndParameters)
        XCTAssertEqual(firedPixels.first?.includesAppVersionParameter, false)
    }

    func testWhenFireNextStepsCardShownPixelsCalled_WithBringStuff_ThenShownPixelIsFired() {
        pixelHandler.fireNextStepsCardShownPixels([.bringStuff])

        XCTAssertEqual(firedPixels.count, 1)
        let expectedEvent = NewTabPagePixel.nextStepsCardShown(NewTabPageDataModel.CardID.bringStuff.rawValue)
        XCTAssertEqual(firedPixels.first?.event.name, expectedEvent.name)
        XCTAssertEqual(firedPixels.first?.frequency, .uniqueByNameAndParameters)
        XCTAssertEqual(firedPixels.first?.includesAppVersionParameter, false)
    }

    func testWhenFireNextStepsCardShownPixelsCalled_WithEmailProtection_ThenShownPixelIsFired() {
        pixelHandler.fireNextStepsCardShownPixels([.emailProtection])

        XCTAssertEqual(firedPixels.count, 1)
        let expectedEvent = NewTabPagePixel.nextStepsCardShown(NewTabPageDataModel.CardID.emailProtection.rawValue)
        XCTAssertEqual(firedPixels.first?.event.name, expectedEvent.name)
        XCTAssertEqual(firedPixels.first?.frequency, .uniqueByNameAndParameters)
        XCTAssertEqual(firedPixels.first?.includesAppVersionParameter, false)
    }

    func testWhenFireNextStepsCardShownPixelsCalled_WithMultipleCards_ThenShownPixelIsFiredForEach() {
        // WHEN
        pixelHandler.fireNextStepsCardShownPixels([.duckplayer, .emailProtection, .bringStuff])

        // THEN
        XCTAssertEqual(firedPixels.count, 3)

        let duckplayerPixel = NewTabPagePixel.nextStepsCardShown(NewTabPageDataModel.CardID.duckplayer.rawValue)
        let emailProtectionPixel = NewTabPagePixel.nextStepsCardShown(NewTabPageDataModel.CardID.emailProtection.rawValue)
        let bringStuffPixel = NewTabPagePixel.nextStepsCardShown(NewTabPageDataModel.CardID.bringStuff.rawValue)

        XCTAssertTrue(firedPixels.contains(where: { $0.event.name == duckplayerPixel.name }))
        XCTAssertTrue(firedPixels.contains(where: { $0.event.name == emailProtectionPixel.name }))
        XCTAssertTrue(firedPixels.contains(where: { $0.event.name == bringStuffPixel.name }))

        XCTAssertTrue(firedPixels.allSatisfy { $0.frequency == .uniqueByNameAndParameters })
        XCTAssertTrue(firedPixels.allSatisfy { $0.includesAppVersionParameter == false })
    }

    // MARK: - Clicked pixels

    func testWhenFireDefaultBrowserRequestedPixelCalled_ThenItFiresPixel() {
        // WHEN
        pixelHandler.fireDefaultBrowserRequestedPixel()

        // THEN
        XCTAssertEqual(firedPixels.count, 1)
        let expectedEvent = GeneralPixel.defaultRequestedFromHomepageSetupView
        XCTAssertEqual(firedPixels.first?.event.name, expectedEvent.name)
        XCTAssertEqual(firedPixels.first?.frequency, .standard)
        XCTAssertEqual(firedPixels.first?.includesAppVersionParameter, true)
    }

    func testWhenFireNextStepsCardClickedCalled_ForDefaultApp_ThenItFiresPixel() {
        // WHEN
        pixelHandler.fireNextStepsCardClickedPixel(.defaultApp)

        // THEN
        XCTAssertEqual(firedPixels.count, 1)
        let expectedEvent = NewTabPagePixel.nextStepsCardClicked(NewTabPageDataModel.CardID.defaultApp.rawValue)
        XCTAssertEqual(firedPixels.first?.event.name, expectedEvent.name)
        XCTAssertEqual(firedPixels.first?.frequency, .standard)
        XCTAssertEqual(firedPixels.first?.includesAppVersionParameter, true)
    }

    func testWhenFireAddedToDockPixelCalled_ThenItFiresPixels() {
        // WHEN
        pixelHandler.fireAddedToDockPixel()

        // THEN
        XCTAssertEqual(firedPixels.count, 1)
        let expectedEvent = GeneralPixel.userAddedToDockFromNewTabPageCard
        XCTAssertEqual(firedPixels.first?.event.name, expectedEvent.name)
        XCTAssertEqual(firedPixels.first?.frequency, .standard)
        XCTAssertEqual(firedPixels.first?.includesAppVersionParameter, false)
    }

    func testWhenFireNextStepsCardClickedCalled_ForAddToDock_ThenItFiresPixel() {
        // WHEN
        pixelHandler.fireNextStepsCardClickedPixel(.addAppToDockMac)

        // THEN
        XCTAssertEqual(firedPixels.count, 1)
        let expectedEvent = NewTabPagePixel.nextStepsCardClicked(NewTabPageDataModel.CardID.addAppToDockMac.rawValue)
        XCTAssertEqual(firedPixels.first?.event.name, expectedEvent.name)
        XCTAssertEqual(firedPixels.first?.frequency, .standard)
        XCTAssertEqual(firedPixels.first?.includesAppVersionParameter, true)
    }

    func testWhenFireNextStepsCardClickedCalled_ForDuckplayer_ThenItFiresPixel() {
        // WHEN
        pixelHandler.fireNextStepsCardClickedPixel(.duckplayer)

        // THEN
        XCTAssertEqual(firedPixels.count, 1)
        let expectedPixel = NewTabPagePixel.nextStepsCardClicked(NewTabPageDataModel.CardID.duckplayer.rawValue)
        XCTAssertEqual(firedPixels.first?.event.name, expectedPixel.name)
        XCTAssertEqual(firedPixels.first?.includesAppVersionParameter, true)
    }

    func testWhenFireNextStepsCardClickedCalled_ForEmailProtection_ThenItFiresPixel() {
        // WHEN
        pixelHandler.fireNextStepsCardClickedPixel(.emailProtection)

        // THEN
        XCTAssertEqual(firedPixels.count, 1)
        let expectedPixel = NewTabPagePixel.nextStepsCardClicked(NewTabPageDataModel.CardID.emailProtection.rawValue)
        XCTAssertEqual(firedPixels.first?.event.name, expectedPixel.name)
        XCTAssertEqual(firedPixels.first?.includesAppVersionParameter, true)
    }

    func testWhenFireNextStepsCardClickedCalled_ForBringStuff_ThenItFiresPixel() {
        // WHEN
        pixelHandler.fireNextStepsCardClickedPixel(.bringStuff)

        // THEN
        XCTAssertEqual(firedPixels.count, 1)
        let expectedPixel = NewTabPagePixel.nextStepsCardClicked(NewTabPageDataModel.CardID.bringStuff.rawValue)
        XCTAssertEqual(firedPixels.first?.event.name, expectedPixel.name)
        XCTAssertEqual(firedPixels.first?.includesAppVersionParameter, true)
    }

    func testWhenFireSubscriptionCardClickedPixelCalled_ThenItFiresPixel() {
        // WHEN
        pixelHandler.fireSubscriptionCardClickedPixel()

        // THEN
        XCTAssertEqual(firedPixels.count, 1)
        let expectedEvent = SubscriptionPixel.subscriptionNewTabPageNextStepsCardClicked
        XCTAssertEqual(firedPixels.first?.event.name, expectedEvent.name)
        XCTAssertEqual(firedPixels.first?.frequency, .standard)
        XCTAssertEqual(firedPixels.first?.includesAppVersionParameter, true)
    }

    func testWhenFireNextStepsCardClickedCalled_ForSubscription_ThenItFiresPixel() {
        // WHEN
        pixelHandler.fireNextStepsCardClickedPixel(.subscription)

        // THEN
        XCTAssertEqual(firedPixels.count, 1)
        let expectedEvent = NewTabPagePixel.nextStepsCardClicked(NewTabPageDataModel.CardID.subscription.rawValue)
        XCTAssertEqual(firedPixels.first?.event.name, expectedEvent.name)
        XCTAssertEqual(firedPixels.first?.frequency, .standard)
        XCTAssertEqual(firedPixels.first?.includesAppVersionParameter, true)
    }

    // MARK: - Dismissed pixels

    func testWhenFireNextStepsCardDismissedPixelCalled_ForDefaultApp_ThenItFiresPixel() {
        // WHEN
        pixelHandler.fireNextStepsCardDismissedPixel(.defaultApp)

        // THEN
        XCTAssertEqual(firedPixels.count, 1)
        let expectedEvent = NewTabPagePixel.nextStepsCardDismissed(NewTabPageDataModel.CardID.defaultApp.rawValue)
        XCTAssertEqual(firedPixels.first?.event.name, expectedEvent.name)
        XCTAssertEqual(firedPixels.first?.frequency, .standard)
        XCTAssertEqual(firedPixels.first?.includesAppVersionParameter, true)
    }

    func testWhenFireNextStepsCardDismissedPixelCalled_ForAddToDock_ThenItFiresPixel() {
        // WHEN
        pixelHandler.fireNextStepsCardDismissedPixel(.addAppToDockMac)

        // THEN
        XCTAssertEqual(firedPixels.count, 1)
        let expectedEvent = NewTabPagePixel.nextStepsCardDismissed(NewTabPageDataModel.CardID.addAppToDockMac.rawValue)
        XCTAssertEqual(firedPixels.first?.event.name, expectedEvent.name)
        XCTAssertEqual(firedPixels.first?.frequency, .standard)
        XCTAssertEqual(firedPixels.first?.includesAppVersionParameter, true)
    }

    func testWhenFireNextStepsCardDismissedPixelCalled_ForDuckplayer_ThenItFiresPixel() {
        // WHEN
        pixelHandler.fireNextStepsCardDismissedPixel(.duckplayer)

        // THEN
        XCTAssertEqual(firedPixels.count, 1)
        let expectedEvent = NewTabPagePixel.nextStepsCardDismissed(NewTabPageDataModel.CardID.duckplayer.rawValue)
        XCTAssertEqual(firedPixels.first?.event.name, expectedEvent.name)
        XCTAssertEqual(firedPixels.first?.frequency, .standard)
        XCTAssertEqual(firedPixels.first?.includesAppVersionParameter, true)
    }

    func testWhenFireNextStepsCardDismissedPixelCalled_ForEmailProtection_ThenItFiresPixel() {
        // WHEN
        pixelHandler.fireNextStepsCardDismissedPixel(.emailProtection)

        // THEN
        XCTAssertEqual(firedPixels.count, 1)
        let expectedEvent = NewTabPagePixel.nextStepsCardDismissed(NewTabPageDataModel.CardID.emailProtection.rawValue)
        XCTAssertEqual(firedPixels.first?.event.name, expectedEvent.name)
        XCTAssertEqual(firedPixels.first?.frequency, .standard)
        XCTAssertEqual(firedPixels.first?.includesAppVersionParameter, true)
    }

    func testWhenFireNextStepsCardDismissedPixelCalled_ForBringStuff_ThenItFiresPixel() {
        // WHEN
        pixelHandler.fireNextStepsCardDismissedPixel(.bringStuff)

        // THEN
        XCTAssertEqual(firedPixels.count, 1)
        let expectedEvent = NewTabPagePixel.nextStepsCardDismissed(NewTabPageDataModel.CardID.bringStuff.rawValue)
        XCTAssertEqual(firedPixels.first?.event.name, expectedEvent.name)
        XCTAssertEqual(firedPixels.first?.frequency, .standard)
        XCTAssertEqual(firedPixels.first?.includesAppVersionParameter, true)
    }

    func testWhenFireSubscriptionCardDismissedPixelCalled_ThenItFiresPixel() {
        // WHEN
        pixelHandler.fireSubscriptionCardDismissedPixel()

        // THEN
        XCTAssertEqual(firedPixels.count, 1)
        let expectedEvent = SubscriptionPixel.subscriptionNewTabPageNextStepsCardDismissed
        XCTAssertEqual(firedPixels.first?.event.name, expectedEvent.name)
        XCTAssertEqual(firedPixels.first?.frequency, .standard)
        XCTAssertEqual(firedPixels.first?.includesAppVersionParameter, true)
    }

    func testWhenFireNextStepsCardDismissedPixelCalled_ForSubscription_ThenItFiresPixel() {
        // WHEN
        pixelHandler.fireNextStepsCardDismissedPixel(.subscription)

        // THEN
        XCTAssertEqual(firedPixels.count, 1)
        let expectedEvent = NewTabPagePixel.nextStepsCardDismissed(NewTabPageDataModel.CardID.subscription.rawValue)
        XCTAssertEqual(firedPixels.first?.event.name, expectedEvent.name)
        XCTAssertEqual(firedPixels.first?.frequency, .standard)
        XCTAssertEqual(firedPixels.first?.includesAppVersionParameter, true)
    }

}

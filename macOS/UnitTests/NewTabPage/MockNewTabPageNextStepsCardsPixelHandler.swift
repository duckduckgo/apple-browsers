//
//  MockNewTabPageNextStepsCardsPixelHandler.swift
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
@testable import DuckDuckGo_Privacy_Browser

final class MockNewTabPageNextStepsCardsPixelHandler: NewTabPageNextStepsCardsPixelHandling {
    private(set) var fireAddToDockPresentedPixelIfNeededCalledWith: [NewTabPageDataModel.CardID]?
    private(set) var fireNextStepsCardShownPixelsCalledWith: [NewTabPageDataModel.CardID]?
    private(set) var fireNextStepsCardClickedPixelCalledWith: NewTabPageDataModel.CardID?
    private(set) var fireNextStepsCardDismissedPixelCalledWith: NewTabPageDataModel.CardID?
    private(set) var fireAddedToDockPixelCalled = false
    private(set) var fireDefaultBrowserRequestedPixelCalled = false
    private(set) var fireSubscriptionCardClickedPixelCalled = false
    private(set) var fireSubscriptionCardDismissedPixelCalled = false

    func fireAddToDockPresentedPixelIfNeeded(_ cards: [NewTabPageDataModel.CardID]) {
        fireAddToDockPresentedPixelIfNeededCalledWith = cards
    }

    func fireNextStepsCardShownPixels(_ cards: [NewTabPageDataModel.CardID]) {
        fireNextStepsCardShownPixelsCalledWith = cards
    }

    func fireNextStepsCardClickedPixel(_ card: NewTabPage.NewTabPageDataModel.CardID) {
        fireNextStepsCardClickedPixelCalledWith = card
    }

    func fireNextStepsCardDismissedPixel(_ card: NewTabPage.NewTabPageDataModel.CardID) {
        fireNextStepsCardDismissedPixelCalledWith = card
    }

    func fireAddedToDockPixel() {
        fireAddedToDockPixelCalled = true
    }

    func fireDefaultBrowserRequestedPixel() {
        fireDefaultBrowserRequestedPixelCalled = true
    }

    func fireSubscriptionCardClickedPixel() {
        fireSubscriptionCardClickedPixelCalled = true
    }

    func fireSubscriptionCardDismissedPixel() {
        fireSubscriptionCardDismissedPixelCalled = true
    }
}

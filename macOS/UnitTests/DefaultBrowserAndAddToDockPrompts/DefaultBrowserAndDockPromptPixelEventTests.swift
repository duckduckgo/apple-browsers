//
//  DefaultBrowserAndDockPromptPixelEventTests.swift
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

import XCTest
import PixelKit
import PixelKitTestingUtilities
@testable import DuckDuckGo_Privacy_Browser

final class DefaultBrowserAndDockPromptPixelEventTests: XCTestCase {
    static let popoverImpressionPixelName = "m_mac_set-as-default-add-to-dock_popover-shown"
    static let popoverConfirmationActionPixelName = "m_mac_set-as-default-add-to-dock_popover-confirm-action"
    static let popoverDismissActionPixelName = "m_mac_set-as-default-add-to-dock_popover-cancel-action"
    static let bannerImpressionPixelName = "m_mac_set-as-default-add-to-dock_banner-shown"
    static let bannerConfirmationActionPixelName = "m_mac_set-as-default-add-to-dock_banner-confirm-action"
    static let bannerDismissActionPixelName = "m_mac_set-as-default-add-to-dock_banner-cancel-action"
    static let bannerNeverAskAgainActionPixelName = "m_mac_set-as-default-add-to-dock_banner-never-ask-again-action"

    func testParametersMapsToTheRightStrings() {
        // GIVEN
        let pixels: [DefaultBrowserAndDockPromptPixelEvent: PixelFireExpectations] = [
            .popoverImpression(type: .bothDefaultBrowserAndDockPrompt): PixelFireExpectations(
                pixelName: Self.popoverImpressionPixelName,
                customFields: ["contentType": "set-as-default-and-add-to-dock"]
            ),
            .popoverImpression(type: .setAsDefaultPrompt): PixelFireExpectations(
                pixelName: Self.popoverImpressionPixelName,
                customFields: ["contentType": "set-as-default"]
            ),
            .popoverImpression(type: .addToDockPrompt): PixelFireExpectations(
                pixelName: Self.popoverImpressionPixelName, customFields: ["contentType": "add-to-dock"]
            ),
            .popoverConfirmButtonClicked(type: .bothDefaultBrowserAndDockPrompt): PixelFireExpectations(
                pixelName: Self.popoverConfirmationActionPixelName,
                customFields: ["contentType": "set-as-default-and-add-to-dock"]
            ),
            .popoverConfirmButtonClicked(type: .setAsDefaultPrompt): PixelFireExpectations(
                pixelName: Self.popoverConfirmationActionPixelName,
                customFields: ["contentType": "set-as-default"]
            ),
            .popoverConfirmButtonClicked(type: .addToDockPrompt): PixelFireExpectations(
                pixelName: Self.popoverConfirmationActionPixelName,
                customFields: ["contentType": "add-to-dock"]
            ),
            .popoverCloseButtonClicked(type: .bothDefaultBrowserAndDockPrompt): PixelFireExpectations(
                pixelName: Self.popoverDismissActionPixelName,
                customFields: ["contentType": "set-as-default-and-add-to-dock"]
            ),
            .popoverCloseButtonClicked(type: .setAsDefaultPrompt): PixelFireExpectations(
                pixelName: Self.popoverDismissActionPixelName,
                customFields: ["contentType": "set-as-default"]
            ),
            .popoverCloseButtonClicked(type: .addToDockPrompt): PixelFireExpectations(
                pixelName: Self.popoverDismissActionPixelName,
                customFields: ["contentType": "add-to-dock"]
            ),
            .bannerImpression(type: .bothDefaultBrowserAndDockPrompt): PixelFireExpectations(
                pixelName: Self.bannerImpressionPixelName,
                customFields: ["contentType": "set-as-default-and-add-to-dock"]
            ),
            .bannerImpression(type: .setAsDefaultPrompt): PixelFireExpectations(
                pixelName: Self.bannerImpressionPixelName,
                customFields: ["contentType": "set-as-default"]
            ),
            .bannerImpression(type: .addToDockPrompt): PixelFireExpectations(
                pixelName: Self.bannerImpressionPixelName,
                customFields: ["contentType": "add-to-dock"]
            ),
            .bannerConfirmButtonClicked(type: .bothDefaultBrowserAndDockPrompt, numberOfBannersShown: "5"): PixelFireExpectations(
                pixelName: Self.bannerConfirmationActionPixelName,
                customFields: [
                    "contentType": "set-as-default-and-add-to-dock",
                    "numberOfBannersShown": "5",
                ]
            ),
            .bannerConfirmButtonClicked(type: .setAsDefaultPrompt, numberOfBannersShown: "8"): PixelFireExpectations(
                pixelName: Self.bannerConfirmationActionPixelName,
                customFields: [
                    "contentType": "set-as-default",
                    "numberOfBannersShown": "8",
                ]
            ),
            .bannerConfirmButtonClicked(type: .addToDockPrompt, numberOfBannersShown: "10+"): PixelFireExpectations(
                pixelName: Self.bannerConfirmationActionPixelName,
                customFields: [
                    "contentType": "add-to-dock",
                    "numberOfBannersShown": "10+",
                ]
            ),
            .bannerCloseButtonClicked(type: .bothDefaultBrowserAndDockPrompt): PixelFireExpectations(
                pixelName: Self.bannerDismissActionPixelName,
                customFields: ["contentType": "set-as-default-and-add-to-dock"]
            ),
            .bannerCloseButtonClicked(type: .setAsDefaultPrompt): PixelFireExpectations(
                pixelName: Self.bannerDismissActionPixelName,
                customFields: ["contentType": "set-as-default"]
            ),
            .bannerCloseButtonClicked(type: .addToDockPrompt): PixelFireExpectations(
                pixelName: Self.bannerDismissActionPixelName,
                customFields: ["contentType": "add-to-dock"]
            ),
            .bannerNeverAskAgainButtonClicked(type: .bothDefaultBrowserAndDockPrompt): PixelFireExpectations(
                pixelName: Self.bannerNeverAskAgainActionPixelName,
                customFields: ["contentType": "set-as-default-and-add-to-dock"]
            ),
            .bannerNeverAskAgainButtonClicked(type: .setAsDefaultPrompt): PixelFireExpectations(
                pixelName: Self.bannerNeverAskAgainActionPixelName,
                customFields: ["contentType": "set-as-default"]
            ),
            .bannerNeverAskAgainButtonClicked(type: .addToDockPrompt): PixelFireExpectations(
                pixelName: Self.bannerNeverAskAgainActionPixelName,
                customFields: ["contentType": "add-to-dock"]
            ),
       ]

        // THEN
        for (event, expectations) in pixels {
            verifyThat(event, frequency: .standard, meets: expectations, file: #file, line: #line)
        }
    }

}

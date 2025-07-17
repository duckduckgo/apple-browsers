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
        let pixels: [DefaultBrowserAndDockPromptPixelEvent: (expectation: PixelFireExpectations, frequency: PixelKit.Frequency)] = [
            .popoverImpression(type: .bothDefaultBrowserAndDockPrompt): (
                PixelFireExpectations(
                    pixelName: Self.popoverImpressionPixelName,
                    customFields: ["contentType": "set-as-default-and-add-to-dock"]
                ),
                .standard
            ),
            .popoverImpression(type: .setAsDefaultPrompt): (
                PixelFireExpectations(
                    pixelName: Self.popoverImpressionPixelName,
                    customFields: ["contentType": "set-as-default"]
                ),
                .standard
            ),
            .popoverImpression(type: .addToDockPrompt): (
                PixelFireExpectations(
                    pixelName: Self.popoverImpressionPixelName, customFields: ["contentType": "add-to-dock"]
                ),
                .standard
            ),
            .popoverConfirmButtonClicked(type: .bothDefaultBrowserAndDockPrompt): (
                PixelFireExpectations(
                    pixelName: Self.popoverConfirmationActionPixelName,
                    customFields: ["contentType": "set-as-default-and-add-to-dock"]
                ),
                .standard
            ),
            .popoverConfirmButtonClicked(type: .setAsDefaultPrompt): (
                PixelFireExpectations(
                    pixelName: Self.popoverConfirmationActionPixelName,
                    customFields: ["contentType": "set-as-default"]
                ),
                .standard
            ),
            .popoverConfirmButtonClicked(type: .addToDockPrompt): (
                PixelFireExpectations(
                    pixelName: Self.popoverConfirmationActionPixelName,
                    customFields: ["contentType": "add-to-dock"]
                ),
                .standard
            ),
            .popoverCloseButtonClicked(type: .bothDefaultBrowserAndDockPrompt): (
                PixelFireExpectations(
                    pixelName: Self.popoverDismissActionPixelName,
                    customFields: ["contentType": "set-as-default-and-add-to-dock"]
                ),
                .standard
            ),
            .popoverCloseButtonClicked(type: .setAsDefaultPrompt): (
                PixelFireExpectations(
                    pixelName: Self.popoverDismissActionPixelName,
                    customFields: ["contentType": "set-as-default"]
                ),
                .standard
            ),
            .popoverCloseButtonClicked(type: .addToDockPrompt): (
                PixelFireExpectations(
                    pixelName: Self.popoverDismissActionPixelName,
                    customFields: ["contentType": "add-to-dock"]
                ),
                .standard
            ),
            .bannerImpression(type: .bothDefaultBrowserAndDockPrompt, numberOfBannersShown: "10+"): (
                PixelFireExpectations(
                    pixelName: Self.bannerImpressionPixelName,
                    customFields: [
                        "contentType": "set-as-default-and-add-to-dock",
                        "numberOfBannersShown": "10+",
                    ]
                ),
                .uniqueByNameAndParameters
            ),
            .bannerImpression(type: .setAsDefaultPrompt, numberOfBannersShown: "5"): (
                PixelFireExpectations(
                    pixelName: Self.bannerImpressionPixelName,
                    customFields: [
                        "contentType": "set-as-default",
                        "numberOfBannersShown": "5"
                    ]
                ),
                .uniqueByNameAndParameters
            ),
            .bannerImpression(type: .addToDockPrompt, numberOfBannersShown: "8"): (
                PixelFireExpectations(
                    pixelName: Self.bannerImpressionPixelName,
                    customFields: [
                        "contentType": "add-to-dock",
                        "numberOfBannersShown": "8"
                    ]
                ),
                .uniqueByNameAndParameters
            ),
            .bannerConfirmButtonClicked(type: .bothDefaultBrowserAndDockPrompt, numberOfBannersShown: "5"): (
                PixelFireExpectations(
                    pixelName: Self.bannerConfirmationActionPixelName,
                    customFields: [
                        "contentType": "set-as-default-and-add-to-dock",
                        "numberOfBannersShown": "5",
                    ]
                ),
                .standard
            ),
            .bannerConfirmButtonClicked(type: .setAsDefaultPrompt, numberOfBannersShown: "8"): (
                PixelFireExpectations(
                    pixelName: Self.bannerConfirmationActionPixelName,
                    customFields: [
                        "contentType": "set-as-default",
                        "numberOfBannersShown": "8",
                    ]
                ),
                .standard
            ),
            .bannerConfirmButtonClicked(type: .addToDockPrompt, numberOfBannersShown: "10+"): (
                PixelFireExpectations(
                    pixelName: Self.bannerConfirmationActionPixelName,
                    customFields: [
                        "contentType": "add-to-dock",
                        "numberOfBannersShown": "10+",
                    ]
                ),
                .standard
            ),
            .bannerCloseButtonClicked(type: .bothDefaultBrowserAndDockPrompt): (
                PixelFireExpectations(
                    pixelName: Self.bannerDismissActionPixelName,
                    customFields: ["contentType": "set-as-default-and-add-to-dock"]
                ),
                .standard
            ),
            .bannerCloseButtonClicked(type: .setAsDefaultPrompt): (
                PixelFireExpectations(
                    pixelName: Self.bannerDismissActionPixelName,
                    customFields: ["contentType": "set-as-default"]
                ),
                .standard
            ),
            .bannerCloseButtonClicked(type: .addToDockPrompt): (
                PixelFireExpectations(
                    pixelName: Self.bannerDismissActionPixelName,
                    customFields: ["contentType": "add-to-dock"]
                ),
                .standard
            ),
            .bannerNeverAskAgainButtonClicked(type: .bothDefaultBrowserAndDockPrompt): (
                PixelFireExpectations(
                    pixelName: Self.bannerNeverAskAgainActionPixelName,
                    customFields: ["contentType": "set-as-default-and-add-to-dock"]
                ),
                .standard
            ),
            .bannerNeverAskAgainButtonClicked(type: .setAsDefaultPrompt): (
                PixelFireExpectations(
                    pixelName: Self.bannerNeverAskAgainActionPixelName,
                    customFields: ["contentType": "set-as-default"]
                ),
                .standard
            ),
            .bannerNeverAskAgainButtonClicked(type: .addToDockPrompt): (
                PixelFireExpectations(
                    pixelName: Self.bannerNeverAskAgainActionPixelName,
                    customFields: ["contentType": "add-to-dock"]
                ),
                .standard
            ),
        ]

        // THEN
        for (event, context) in pixels {
            verifyThat(event, frequency: context.frequency, meets: context.expectation, file: #file, line: #line)
        }
    }

}

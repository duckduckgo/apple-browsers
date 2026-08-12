//
//  DuckAIPromptPixelFiringTests.swift
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

import PixelKit
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class DuckAIPromptPixelFiringTests: XCTestCase {

    /// Add a row whenever a case is added: associated values rule out `CaseIterable`, so nothing
    /// makes a gap here fail to compile.
    private static let addressBarMapping: [(event: DuckAIPromptPixelEvent, pixel: AIChatPixel?)] = [
        (.promptSubmitted, .aiChatAddressBarAIChatSubmitPrompt),
        (.urlSubmitted, .aiChatAddressBarAIChatSubmitURL),
        (.imageGenerationSubmitted, .aiChatAddressBarImageGenerationSubmitted),
        (.webSearchSubmitted, .aiChatAddressBarWebSearchSubmitted),
        (.submittedWithImages(count: 2), .aiChatAddressBarSubmitWithImage(imageCount: 2)),
        (.submittedWithFiles(count: 3), .aiChatAddressBarSubmitWithFiles(fileCount: 3)),
        (.submittedWithTabs(count: 4), .aiChatAddressBarSubmitWithTabs(tabCount: 4)),
        (.imageGenerationActivated, .aiChatAddressBarImageGenerationActivated),
        (.imageGenerationDeactivated, .aiChatAddressBarImageGenerationDeactivated),
        (.webSearchActivated, .aiChatAddressBarWebSearchActivated),
        (.webSearchDeactivated, .aiChatAddressBarWebSearchDeactivated),
        (.customizeResponsesOpened, .aiChatAddressBarCustomizeResponsesOpened),
        (.imageAttached, .aiChatAddressBarImageAttached),
        (.imageRemoved, .aiChatAddressBarImageRemoved),
        (.fileAttached, .aiChatAddressBarFileAttached),
        (.fileRemoved, .aiChatAddressBarFileRemoved),
        (.fileValidationFailed(reason: "tooLarge"), .aiChatAddressBarFileValidationFailed(reason: "tooLarge")),
        (.tabAttachmentRemoved, .aiChatAddressBarAttachTabRemoved),
        (.tabPickerShown, .aiChatAddressBarAttachTabsPickerShown),
        (.tabChosen, .aiChatAddressBarAttachTabChosen),
        (.tabPickerCanceled, .aiChatAddressBarAttachPickerCanceled),
        (.modelSelected, .aiChatAddressBarModelSelected),
        (.reasoningEffortSelected, .aiChatAddressBarReasoningEffortSelected),
        (.modelPickerShown, .aiChatAddressBarModelPickerShown(origin: "funnel_addressbar_macos__modelpicker")),
        (.reasoningPickerShown, .aiChatAddressBarReasoningPickerShown(origin: "funnel_addressbar_macos__reasoningdropdown")),
        (.subscriptionUpsellShown(origin: "funnel_addressbar_macos__modelpicker"),
         .aiChatAddressBarSubscriptionUpsellShown(origin: "funnel_addressbar_macos__modelpicker")),
        (.subscriptionUpsellTriggered(currentTier: "free", requiredTier: "plus", flowType: "modal", origin: "funnel_addressbar_macos__modelpicker"),
         .aiChatAddressBarSubscriptionUpsellTriggered(currentTier: "free", requiredTier: "plus", flowType: "modal",
                                                      origin: "funnel_addressbar_macos__modelpicker")),
        (.voiceChatOpened, nil)
    ]

    /// `nil` where `DuckAIPromptSurface` turns the feature off for the Prompt Bar — page context,
    /// Customize Responses and the subscription upsell. Same rule as above: add a row per case.
    private static let promptBarMapping: [(event: DuckAIPromptPixelEvent, pixel: PromptBarPixel?)] = [
        (.promptSubmitted, .submitPrompt),
        (.urlSubmitted, .submitURL),
        (.imageGenerationSubmitted, .imageGenerationSubmitted),
        (.webSearchSubmitted, .webSearchSubmitted),
        (.submittedWithImages(count: 2), .submitWithImage(imageCount: 2)),
        (.submittedWithFiles(count: 3), .submitWithFiles(fileCount: 3)),
        (.submittedWithTabs(count: 4), nil),
        (.imageGenerationActivated, .imageGenerationActivated),
        (.imageGenerationDeactivated, .imageGenerationDeactivated),
        (.webSearchActivated, .webSearchActivated),
        (.webSearchDeactivated, .webSearchDeactivated),
        (.customizeResponsesOpened, nil),
        (.imageAttached, .imageAttached),
        (.imageRemoved, .imageRemoved),
        (.fileAttached, .fileAttached),
        (.fileRemoved, .fileRemoved),
        (.fileValidationFailed(reason: "tooLarge"), .fileValidationFailed(reason: "tooLarge")),
        (.tabAttachmentRemoved, nil),
        (.tabPickerShown, nil),
        (.tabChosen, nil),
        (.tabPickerCanceled, nil),
        (.modelSelected, .modelSelected),
        (.reasoningEffortSelected, .reasoningEffortSelected),
        (.modelPickerShown, .modelPickerShown(origin: "funnel_promptbar_macos__modelpicker")),
        (.reasoningPickerShown, .reasoningPickerShown(origin: "funnel_promptbar_macos__reasoningdropdown")),
        (.subscriptionUpsellShown(origin: "x"), nil),
        (.subscriptionUpsellTriggered(currentTier: "free", requiredTier: "plus", flowType: "modal", origin: "x"), nil),
        (.voiceChatOpened, .newVoiceChat)
    ]

    /// Names are asserted as literals because the mapping tables build expected and actual from the
    /// same enum; they have to stay in step with the keys in the pixel definition files.
    private static let pickerImpressionNames: [(AIChatPixel, String)] = [
        (.aiChatAddressBarModelPickerShown(origin: "x"), "aichat_addressbar_model_picker_shown"),
        (.aiChatAddressBarReasoningPickerShown(origin: "x"), "aichat_addressbar_reasoning_picker_shown")
    ]

    func testPickerImpressionPixelNames() {
        for (pixel, expectedName) in Self.pickerImpressionNames {
            XCTAssertEqual(pixel.name, expectedName)
        }
        XCTAssertEqual(PromptBarPixel.modelPickerShown(origin: "x").name, "aichat_promptbar_model_picker_shown")
        XCTAssertEqual(PromptBarPixel.reasoningPickerShown(origin: "x").name, "aichat_promptbar_reasoning_picker_shown")
        XCTAssertEqual(PromptBarPixel.modelPickerShown(origin: "x").parameters, ["origin": "x"])
    }

    func testWhenAddressBarHandlerMapsAnEvent_ThenItKeepsThePixelItFiredBefore() {
        for (event, expected) in Self.addressBarMapping {
            let mapped = AddressBarPromptPixelHandler.addressBarPixel(for: event)

            XCTAssertEqual(mapped?.name, expected?.name, "Wrong pixel name for \(event)")
            XCTAssertEqual(mapped?.parameters, expected?.parameters, "Wrong pixel parameters for \(event)")
        }
    }

    func testWhenPromptBarHandlerMapsAnEvent_ThenItReportsUnderItsOwnName() {
        for (event, expected) in Self.promptBarMapping {
            let mapped = PromptBarPixelHandler.promptBarPixel(for: event)

            XCTAssertEqual(mapped?.name, expected?.name, "Wrong pixel name for \(event)")
            XCTAssertEqual(mapped?.parameters, expected?.parameters, "Wrong pixel parameters for \(event)")
        }
    }

    /// The two surfaces must never share a name, or the Prompt Bar's numbers fold into the address
    /// bar's and the comparison the prefix exists for becomes impossible.
    func testWhenBothHandlersMapTheSameEvent_ThenTheNamesDiffer() {
        for (event, promptBarPixel) in Self.promptBarMapping {
            guard let promptBarPixel,
                  let addressBarPixel = AddressBarPromptPixelHandler.addressBarPixel(for: event) else { continue }

            XCTAssertNotEqual(promptBarPixel.name, addressBarPixel.name, "Shared pixel name for \(event)")
            XCTAssertTrue(promptBarPixel.name.hasPrefix("aichat_promptbar_"),
                          "\(promptBarPixel.name) is not under the Prompt Bar prefix")
        }
    }

    func testWhenPromptBarHandlerFiresAnUnsupportedEvent_ThenNothingReachesPixelKit() {
        var firedNames: [String] = []
        PixelKit.setUp(dryRun: false,
                       appVersion: "1.0.0",
                       session: "test",
                       defaultHeaders: [:],
                       defaults: UserDefaults()) { name, _, _, _, _, onComplete in
            firedNames.append(name)
            onComplete(true, nil)
        }
        defer { PixelKit.tearDown() }

        let handler = PromptBarPixelHandler()
        for (event, pixel) in Self.promptBarMapping where pixel == nil {
            handler.fire(event)
        }

        XCTAssertTrue(firedNames.isEmpty,
                      "Events the Prompt Bar can't produce must stay silent, but fired: \(firedNames)")
    }
}

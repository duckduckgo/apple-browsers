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

    /// Every case of `DuckAIPromptPixelEvent` paired with the `aiChatAddressBar*` pixel it fired
    /// directly before the handler existed. Add a row whenever a case is added — the enum carries
    /// associated values, so it can't be `CaseIterable` and the compiler won't flag a gap here.
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
        (.subscriptionUpsellTriggered(currentTier: "free", requiredTier: "plus", flowType: "modal"),
         .aiChatAddressBarSubscriptionUpsellTriggered(currentTier: "free", requiredTier: "plus", flowType: "modal")),
        // Fired under a surface-neutral name, so it has no `aiChatAddressBar*` counterpart.
        (.voiceChatOpened, nil)
    ]

    func testWhenAddressBarHandlerMapsAnEvent_ThenItKeepsThePixelItFiredBefore() {
        for (event, expected) in Self.addressBarMapping {
            let mapped = AddressBarPromptPixelHandler.addressBarPixel(for: event)

            XCTAssertEqual(mapped?.name, expected?.name, "Wrong pixel name for \(event)")
            XCTAssertEqual(mapped?.parameters, expected?.parameters, "Wrong pixel parameters for \(event)")
        }
    }

    func testWhenPromptBarHandlerFiresEveryEvent_ThenNothingReachesPixelKit() {
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
        for (event, _) in Self.addressBarMapping {
            handler.fire(event)
        }

        XCTAssertTrue(firedNames.isEmpty,
                      "The Prompt Bar handler must stay silent, but fired: \(firedNames)")
    }
}

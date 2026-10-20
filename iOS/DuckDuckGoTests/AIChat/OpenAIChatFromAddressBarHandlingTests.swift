//
//  OpenAIChatFromAddressBarHandlingTests.swift
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

import XCTest
@testable import Core
@testable import DuckDuckGo
import AIChat
@_spi(Testing) import Persistence

final class OpenAIChatFromAddressBarHandlingTests: XCTestCase {

    func testWhenTextFieldIsBlankThenJustOpen() {
        let sut = OpenAIChatFromAddressBarHandling()

        let ex = expectation(description: "expected action called")
        sut.determineOpeningStrategy(isTextFieldEditing: true, textFieldValue: "   ", currentURL: .example) {
            XCTFail("Incorrect action called with prompt \($0)")
        } open: {
            ex.fulfill()
        }

        wait(for: [ex], timeout: 1.0) // Timeout not strictly needed as it's sync
    }

    func testWhenTextFieldIsNilThenJustOpen() {
        let sut = OpenAIChatFromAddressBarHandling()

        let ex = expectation(description: "expected action called")
        sut.determineOpeningStrategy(isTextFieldEditing: true, textFieldValue: nil, currentURL: .example) {
            XCTFail("Incorrect action called with prompt \($0)")
        } open: {
            ex.fulfill()
        }

        wait(for: [ex], timeout: 1.0) // Timeout not strictly needed as it's sync
    }

    func testWhenNotEditingThenJustOpen() {
        let sut = OpenAIChatFromAddressBarHandling()

        let ex = expectation(description: "expected action called")
        sut.determineOpeningStrategy(isTextFieldEditing: false, textFieldValue: "https://www.example.com", currentURL: .example) {
            XCTFail("Incorrect action called with prompt \($0)")
        } open: {
            ex.fulfill()
        }

        wait(for: [ex], timeout: 1.0) // Timeout not strictly needed as it's sync
    }

    func testWhenEditingAndRandomTextIsSubmittedWithNoURLThenOpenAndSendTextAsPrompt() {
        let sut = OpenAIChatFromAddressBarHandling()

        let ex = expectation(description: "expected action called")
        sut.determineOpeningStrategy(isTextFieldEditing: true, textFieldValue: "moonlight", currentURL: nil) {
            XCTAssertEqual($0, "moonlight")
            ex.fulfill()
        } open: {
            XCTFail("Incorrect action called")
        }

        wait(for: [ex], timeout: 1.0) // Timeout not strictly needed as it's sync
    }

    func testWhenEditingAndRandomTextIsSubmittedThenOpenAndSendTextAsPrompt() {
        let sut = OpenAIChatFromAddressBarHandling()

        let ex = expectation(description: "expected action called")
        sut.determineOpeningStrategy(isTextFieldEditing: true, textFieldValue: "moonlight", currentURL: .example) {
            XCTAssertEqual($0, "moonlight")
            ex.fulfill()
        } open: {
            XCTFail("Incorrect action called")
        }

        wait(for: [ex], timeout: 1.0) // Timeout not strictly needed as it's sync
    }

    func testWhenEditingAndCurrentURLIsSubmittedThenOpenAndSendURLAsPromptDroppingScheme() {
        let sut = OpenAIChatFromAddressBarHandling()

        let ex = expectation(description: "expected action called")
        sut.determineOpeningStrategy(isTextFieldEditing: true, textFieldValue: "https://www.example.com", currentURL: .example) {
            XCTAssertEqual($0, "www.example.com")
            ex.fulfill()
        } open: {
            XCTFail("Incorrect action called")
        }

        wait(for: [ex], timeout: 1.0) // Timeout not strictly needed as it's sync
    }

    func testAutoSubmittedDuckAIPromptRequiresContentAndAutoSend() {
        XCTAssertFalse(MainViewController.hasAutoSubmittedDuckAIPrompt(query: nil, autoSend: true, hasAttachments: false))
        XCTAssertFalse(MainViewController.hasAutoSubmittedDuckAIPrompt(query: "   ", autoSend: true, hasAttachments: false))
        XCTAssertFalse(MainViewController.hasAutoSubmittedDuckAIPrompt(query: "prompt", autoSend: false, hasAttachments: false))
        XCTAssertFalse(MainViewController.hasAutoSubmittedDuckAIPrompt(query: nil, autoSend: false, hasAttachments: true))
        XCTAssertTrue(MainViewController.hasAutoSubmittedDuckAIPrompt(query: "prompt", autoSend: true, hasAttachments: false))
        XCTAssertTrue(MainViewController.hasAutoSubmittedDuckAIPrompt(query: nil, autoSend: true, hasAttachments: true))
    }

    func testOpeningPromptInfoIncludesImagesFilesContextsAndSelections() {
        let context = AIChatPageContextData(title: "Page", favicon: [], url: "https://example.com", content: "content",
                                            truncated: false, fullContentLength: 7, tabId: "tab")
        let selection = AIChatSelectionContextData(id: "selection", title: "Page", url: "https://example.com",
                                                  content: "selected", truncated: false, fullContentLength: 8, wordCount: 1)
        let prompts: [AIChatNativePrompt] = [
            .queryPrompt("", autoSubmit: true, images: [.init(data: "image", format: "png")]),
            .queryPrompt("", autoSubmit: true, files: [.init(data: "file", fileName: "file.txt", mimeType: "text/plain")]),
            .queryPrompt("", autoSubmit: true, pageContext: .single(context)),
            .queryPrompt("", autoSubmit: true, pageContext: .multiple([context])),
            .queryPrompt("", autoSubmit: true, selections: [selection])
        ]
        for prompt in prompts {
            let info = AIChatOpeningPromptInfo(prompt: prompt)
            XCTAssertTrue(info.hasContent)
            XCTAssertTrue(info.hasAutoSubmittedPrompt)
        }
        let empty = AIChatNativePrompt.queryPrompt(" \n ", autoSubmit: true, images: [], files: [], pageContext: .multiple([]), selections: [])
        XCTAssertFalse(AIChatOpeningPromptInfo(prompt: empty).hasContent)
        XCTAssertFalse(AIChatOpeningPromptInfo(prompt: empty).hasAutoSubmittedPrompt)
        let draft = AIChatNativePrompt.queryPrompt("", autoSubmit: false, pageContext: .multiple([context]))
        XCTAssertTrue(AIChatOpeningPromptInfo(prompt: draft).hasContent)
        XCTAssertFalse(AIChatOpeningPromptInfo(prompt: draft).hasAutoSubmittedPrompt)
    }

    @MainActor
    func testOpeningQueryOnlyStagesContentAndPreservesNativePromptConfiguration() {
        let emptyQueries: [String?] = [nil, "", " \n "]
        for query in emptyQueries {
            let opening = AIChatOpeningRequest.Query(query: query, autoSend: true, flowType: .mobileAppOnboarding,
                                                      tools: [.webSearch], modelId: "model", reasoningEffort: .medium,
                                                      images: [], files: [], termsAccepted: true)
            XCTAssertNil(opening.sharedPrompt)
        }
        let images: [AIChatNativePrompt.NativePromptImage] = [.init(data: "image", format: "png")]
        let files: [AIChatNativePrompt.NativePromptFile] = [.init(data: "file", fileName: "file.txt", mimeType: "text/plain")]
        for autoSend in [false, true] {
            let opening = AIChatOpeningRequest.Query(query: nil, autoSend: autoSend, flowType: .mobileAppOnboarding,
                                                      tools: [.webSearch], modelId: "model", reasoningEffort: .medium,
                                                      images: images, files: files, termsAccepted: true)
            XCTAssertEqual(opening.sharedPrompt, .queryPrompt("", autoSubmit: autoSend, toolChoice: [AIChatRAGTool.webSearch.rawValue],
                                                               images: images, files: files, modelId: "model", reasoningEffort: .medium)
                .withTermsAccepted(true))
            XCTAssertEqual(opening.promptInfo.hasAutoSubmittedPrompt, autoSend)
        }
    }

    func testAddressBarHandoverRequiresQueryContentWhileOpeningCountsContextsAndSelections() {
        let context = AIChatPageContextData(title: "Page", favicon: [], url: "https://example.com", content: "content",
                                            truncated: false, fullContentLength: 7, tabId: "tab")
        let selection = AIChatSelectionContextData(id: "selection", title: "Page", url: "https://example.com",
                                                  content: "selected", truncated: false, fullContentLength: 8, wordCount: 1)
        let cases: [(prompt: AIChatNativePrompt, handsOverQuery: Bool)] = [
            (.queryPrompt("", autoSubmit: true, pageContext: .multiple([context])), false),
            (.queryPrompt(" \n ", autoSubmit: true, selections: [selection]), false),
            (.queryPrompt("text", autoSubmit: true, pageContext: .multiple([context])), true),
            (.queryPrompt("", autoSubmit: true, images: [.init(data: "image", format: "png")], pageContext: .multiple([context])), true),
            (.queryPrompt("", autoSubmit: true, files: [.init(data: "file", fileName: "file.txt", mimeType: "text/plain")]), true)
        ]
        for (prompt, handsOverQuery) in cases {
            let info = AIChatOpeningPromptInfo(prompt: prompt)
            XCTAssertTrue(info.hasAutoSubmittedPrompt)
            XCTAssertEqual(info.hasAutoSubmittedQuery, handsOverQuery)
        }
        let draft = AIChatOpeningPromptInfo(prompt: .queryPrompt("text", autoSubmit: false, pageContext: .multiple([context])))
        XCTAssertFalse(draft.hasAutoSubmittedPrompt)
        XCTAssertFalse(draft.hasAutoSubmittedQuery)
        let empty = AIChatOpeningPromptInfo(prompt: .queryPrompt("", autoSubmit: true))
        XCTAssertFalse(empty.hasAutoSubmittedPrompt)
        XCTAssertFalse(empty.hasAutoSubmittedQuery)
    }

    @MainActor
    func testOrdinaryOpeningKeepsEntryPixelAndDeepLinkMeasurementRules() {
        let query = AIChatOpeningRequest.Query(query: "   ", autoSend: true, flowType: .default, tools: nil,
                                               modelId: nil, reasoningEffort: nil, images: nil, files: nil, termsAccepted: false)
        let deepLink = AIChatOpeningRequest(url: .example, payload: nil, source: .addressBarPrompt, opensNewTab: true,
                                            prompt: .sharedHandler(query, reportsNewTab: false, fromDeepLink: true))
        XCTAssertFalse(deepLink.shouldMeasureOpening)
        XCTAssertFalse(deepLink.reportsNewTab)
        XCTAssertTrue(deepLink.hasEntryPrompt)
        XCTAssertFalse(deepLink.promptInfo.hasAutoSubmittedPrompt)
        let sameTab = AIChatOpeningRequest(url: .example, payload: nil, source: .addressBarPrompt, opensNewTab: false,
                                           prompt: .sharedHandler(query, reportsNewTab: true, fromDeepLink: true))
        XCTAssertTrue(sameTab.shouldMeasureOpening)
        XCTAssertTrue(sameTab.reportsNewTab)
        let inApp = AIChatOpeningRequest(url: .example, payload: nil, source: .addressBarPrompt, opensNewTab: true,
                                         prompt: .sharedHandler(query, reportsNewTab: nil, fromDeepLink: false))
        XCTAssertTrue(inApp.shouldMeasureOpening)
        XCTAssertTrue(inApp.reportsNewTab)
    }

    @MainActor
    func testPreparedOpeningMeasuresOnlyPresentedResultsAndKeepsEntryPixelSemantics() {
        let delivery = AIChatInitialPromptDelivery(prompt: .queryPrompt("", autoSubmit: true)) {
            XCTFail("Opening rules must not consume delivery")
        }
        let tabsModel = TabsModel(desktop: false)
        for shouldPresent in [false, true] {
            let context = AIChatOpeningRequest.PreparedContext(tabsModel: tabsModel, shouldPresent: shouldPresent,
                                                                selectedModelID: "saved-model", selectedReasoningMode: nil,
                                                                promptModelID: "prompt-model")
            let opening = AIChatOpeningRequest(url: .example, payload: nil, source: .addressBarPrompt, opensNewTab: true,
                                               prompt: .tabSession(delivery, context))
            XCTAssertEqual(opening.shouldMeasureOpening, shouldPresent)
            XCTAssertTrue(opening.hasEntryPrompt)
            XCTAssertFalse(opening.promptInfo.hasAutoSubmittedPrompt)
            XCTAssertEqual(opening.modelID, "prompt-model")
        }
        XCTAssertTrue(delivery.hasPendingPrompt)
    }

}

private extension URL {

    static let example = URL(string: "https://www.example.com")!

}

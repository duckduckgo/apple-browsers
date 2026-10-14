//
//  AIChatPastedTextTests.swift
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

import Foundation
import Testing
@testable import AIChat

struct AIChatPastedTextTests {

    // MARK: - Payload

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func queryEncodesTextPastedAsContentObjects() throws {
        let prompt = AIChatNativePrompt.queryPrompt("summarise", autoSubmit: true, textPasted: [.init(content: "first"), .init(content: "second")])

        let query = try #require(try jsonObject(prompt)["query"] as? [String: Any])
        let pasted = try #require(query["textPasted"] as? [[String: Any]])
        #expect(pasted.count == 2)
        #expect(pasted[0]["content"] as? String == "first")
        #expect(pasted[1]["content"] as? String == "second")
        #expect(Set(pasted[0].keys) == ["content"])
        #expect(query["prompt"] as? String == "summarise")
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func queryOmitsTextPastedKeyWhenNil() throws {
        let query = try #require(try jsonObject(.queryPrompt("hi", autoSubmit: true))["query"] as? [String: Any])
        #expect(query["textPasted"] == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func queryRoundTripsTextPasted() throws {
        let prompt = AIChatNativePrompt.queryPrompt("", autoSubmit: true, textPasted: [.init(content: "body")])
        let decoded = try JSONDecoder().decode(AIChatNativePrompt.self, from: JSONEncoder().encode(prompt))
        #expect(decoded == prompt)
    }

#if os(iOS)
    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func editReplyEncodesTextPasted() throws {
        let reply = EditPromptReply.submit(prompt: "p", images: nil, files: nil, textPasted: [.init(content: "body")])
        let data = try JSONEncoder().encode(reply)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let pasted = try #require(json["textPasted"] as? [[String: Any]])
        #expect(pasted.first?["content"] as? String == "body")
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func editRequestDecodesTextPasted() throws {
        let json = #"{"prompt":"p","hasResponsesToLose":false,"textPasted":[{"content":"body"}]}"#
        let request = try JSONDecoder().decode(EditPromptRequest.self, from: Data(json.utf8))
        #expect(request.textPasted == [.init(content: "body")])
    }
#endif

    // MARK: - Conversion rule

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func conversionThresholdCountsUTF16Units() {
        #expect(!AIChatPastedText.shouldConvert(String(repeating: "a", count: 4_999)))
        #expect(AIChatPastedText.shouldConvert(String(repeating: "a", count: 5_000)))
        // 2,500 emoji are 2,500 Characters but 5,000 UTF-16 units, which is what the FE measures.
        #expect(AIChatPastedText.shouldConvert(String(repeating: "😀", count: 2_500)))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func titleIsFirstNonEmptyLineTrimmedAndTruncated() {
        #expect(AIChatPastedText(content: "\n\n   Hello world  \nsecond").title == "Hello world")
        let long = String(repeating: "x", count: 61)
        #expect(AIChatPastedText(content: long).title == String(repeating: "x", count: 60) + "…")
        #expect(AIChatPastedText(content: String(repeating: "y", count: 60)).title == String(repeating: "y", count: 60))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func editLimitCountsEverythingElseButNeverDropsBelowOwnLength() {
        #expect(AIChatPastedText.editLimit(ownLength: 6_000, otherContentLength: 4_000) == 12_000)
        #expect(AIChatPastedText.editLimit(ownLength: 9_000, otherContentLength: 10_000) == 9_000)
    }

    // MARK: - Limits

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func pastedTextCountsTowardTheInputLimit() {
        #expect(validator(pastedLength: 15_000).promptValidationMessage(for: String(repeating: "a", count: 1_000)) == nil)
        #expect(validator(pastedLength: 15_000).promptValidationMessage(for: String(repeating: "a", count: 1_001)) == "promptTooLong")
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func typedPromptAloneIsNotCappedAtTheInputLimit() {
        #expect(validator(pastedLength: 0).promptValidationMessage(for: String(repeating: "a", count: 20_000)) == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func imagePlusPastedTextAlwaysExceedsTheWithAttachmentsLimit() {
        #expect(validator(pastedLength: 5_000, pendingImageCount: 1).promptValidationMessage(for: "") == "promptTooLong")
    }

    // MARK: - Helpers

    private func jsonObject(_ prompt: AIChatNativePrompt) throws -> [String: Any] {
        let data = try JSONEncoder().encode(prompt)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func validator(pastedLength: Int, pendingImageCount: Int = 0) -> AIChatAttachmentValidator {
        AIChatAttachmentValidator(
            limits: AIChatAttachmentTierLimits(
                files: AIChatAttachmentFileLimits(maxPerConversation: 3, maxFileSizeMB: 5, maxTotalFileSizeBytes: 5_242_880, maxPagesPerFile: 15),
                images: AIChatAttachmentImageLimits(maxPerTurn: 3, maxPerConversation: 5, maxInputCharsWithAttachments: 4_500)
            ),
            model: nil,
            pendingImageCount: pendingImageCount,
            pendingPastedTextLength: pastedLength,
            messages: AIChatAttachmentValidator.Messages(
                unsupportedFileType: "", unavailable: "", fileEncrypted: "", fileUnreadable: "", promptTooLong: "promptTooLong",
                unsupportedFileTypeWithAccepted: { _ in "" }, fileCountLimit: { _ in "" }, fileTooLarge: { _ in "" },
                filesExceedTotalSizeLimit: { _ in "" }, fileTooManyPages: { _ in "" }, imageTurnLimit: { _ in "" }, imageCountLimit: { _ in "" }
            )
        )
    }
}

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
    func blankPasteNeverConverts() {
        #expect(!AIChatPastedText.shouldConvert(String(repeating: " \n", count: 3_000)))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func titleIsFirstNonBlankLineTrimmed() {
        #expect(AIChatPastedText(content: "\n\n   Hello world  \nsecond").title == "Hello world")
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func editLimitCountsEverythingElseButNeverDropsBelowOwnLengthOrAboveThePerPasteCap() {
        #expect(AIChatPastedText.editLimit(ownLength: 6_000, otherContentLength: 4_000) == 12_000)
        #expect(AIChatPastedText.editLimit(ownLength: 9_000, otherContentLength: 10_000) == 9_000)
        #expect(AIChatPastedText.editLimit(ownLength: 20_000, otherContentLength: 0) == 16_000)
    }

    // MARK: - Limits

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func promptPlusPastedTextOverTheInputLimitReportsCountAndLimit() {
        #expect(AIChatPastedTextMessage(prompt: String(repeating: "a", count: 1_000), pastedTextLengths: [15_000]).violation == nil)
        #expect(AIChatPastedTextMessage(prompt: String(repeating: "a", count: 1_001), pastedTextLengths: [15_000]).violation
                == AIChatPastedTextLimitViolation(count: 16_001, limit: 16_000))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func singlePasteOverTheBackendCapIsOverTheLimit() {
        #expect(AIChatPastedTextMessage(prompt: "", pastedTextLengths: [16_800]).violation
                == AIChatPastedTextLimitViolation(count: 16_800, limit: 16_000))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func anImageLowersTheLimitButAFileDoesNot() {
        #expect(AIChatPastedTextMessage(prompt: "", pastedTextLengths: [5_000], hasImage: true, maxInputCharsWithImages: 4_500).violation
                == AIChatPastedTextLimitViolation(count: 5_000, limit: 4_500))
        #expect(AIChatPastedTextMessage(prompt: "", pastedTextLengths: [5_000], hasImage: false, maxInputCharsWithImages: 4_500).violation == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func typedPromptAloneIsNeverEvaluated() {
        #expect(AIChatPastedTextMessage(prompt: String(repeating: "a", count: 20_000), pastedTextLengths: []).violation == nil)
    }

    // MARK: - Helpers

    private func jsonObject(_ prompt: AIChatNativePrompt) throws -> [String: Any] {
        let data = try JSONEncoder().encode(prompt)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

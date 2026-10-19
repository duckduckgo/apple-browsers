//
//  AIChatPromptAttachmentsWireTests.swift
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

struct AIChatPromptAttachmentsWireTests {

    private static let image = AIChatNativePrompt.NativePromptImage(data: "aW1n", format: "png")
    private static let file = AIChatNativePrompt.NativePromptFile(data: "ZmlsZQ==", fileName: "a.pdf", mimeType: "application/pdf")
    private static let imageJSON = #"{"data":"aW1n","format":"png"}"#
    private static let fileJSON = #"{"data":"ZmlsZQ==","fileName":"a.pdf","mimeType":"application\/pdf"}"#

    private static let pastes = [
        AIChatNativePrompt.NativePromptPastedText(content: "line one 😀\n\"quoted\" line two"),
        AIChatNativePrompt.NativePromptPastedText(content: "second"),
    ]
    private static let pastesJSON = #"[{"content":"line one 😀\n\"quoted\" line two"},{"content":"second"}]"#

    private struct Case {
        let images: [AIChatNativePrompt.NativePromptImage]?
        let files: [AIChatNativePrompt.NativePromptFile]?
        var textPasted: [AIChatNativePrompt.NativePromptPastedText]?
        var keysBeforePrompt = ""
        var keysAfterPrompt = ""

        var attachments: AIChatPromptAttachments {
            AIChatPromptAttachments(images: images, files: files, textPasted: textPasted)
        }

        var description: String { "images: \(String(describing: images)), files: \(String(describing: files)), textPasted: \(String(describing: textPasted))" }
    }

    private static let cases: [Case] = [
        Case(images: nil, files: nil),
        Case(images: [], files: nil, keysBeforePrompt: #","images":[]"#),
        Case(images: [image], files: nil, keysBeforePrompt: #","images":["# + imageJSON + "]"),
        Case(images: nil, files: [], keysBeforePrompt: #","files":[]"#),
        Case(images: nil, files: [file], keysBeforePrompt: #","files":["# + fileJSON + "]"),
        Case(images: [], files: [], keysBeforePrompt: #","files":[],"images":[]"#),
        Case(images: [image], files: [file], keysBeforePrompt: #","files":["# + fileJSON + #"],"images":["# + imageJSON + "]"),
        Case(images: nil, files: nil, textPasted: [], keysAfterPrompt: #","textPasted":[]"#),
        Case(images: nil, files: nil, textPasted: pastes, keysAfterPrompt: #","textPasted":"# + pastesJSON),
        Case(images: [image], files: [file], textPasted: pastes,
             keysBeforePrompt: #","files":["# + fileJSON + #"],"images":["# + imageJSON + "]",
             keysAfterPrompt: #","textPasted":"# + pastesJSON),
    ]

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func queryPromptEncodesEachAttachmentKindAsGiven() throws {
        for testCase in Self.cases {
            let prompt = AIChatNativePrompt.queryPrompt("p", autoSubmit: true, attachments: testCase.attachments)
            let expected = #"{"platform":"\#(Platform.name)","query":{"autoSubmit":true"# + testCase.keysBeforePrompt + #","prompt":"p""# + testCase.keysAfterPrompt + #"},"tool":"query"}"#
            #expect(try canonicalJSON(prompt) == expected, "\(testCase.description)")
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func queryPromptDecodesEachAttachmentKindAsGiven() throws {
        for testCase in Self.cases {
            let prompt = AIChatNativePrompt.queryPrompt("p", autoSubmit: true, attachments: testCase.attachments)
            let decoded = try JSONDecoder().decode(AIChatNativePrompt.self, from: try JSONEncoder().encode(prompt))
            #expect(decoded == prompt, "\(testCase.description)")
            guard case .query(let query) = decoded.tool else { Issue.record("not a query"); continue }
            #expect(query.attachments == testCase.attachments)
        }
    }

#if os(iOS)
    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func editReplyEncodesEachAttachmentKindAsGiven() throws {
        for testCase in Self.cases {
            let reply = EditPromptReply.submit(prompt: "p", attachments: testCase.attachments)
            let expected = "{" + testCase.keysBeforePrompt.dropFirst() + (testCase.keysBeforePrompt.isEmpty ? "" : ",") + #""prompt":"p""# + testCase.keysAfterPrompt + "}"
            #expect(try canonicalJSON(reply) == expected, "\(testCase.description)")
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func editRequestDecodesEachAttachmentKindAsGiven() throws {
        for testCase in Self.cases {
            let json = #"{"hasResponsesToLose":false"# + testCase.keysBeforePrompt + #","prompt":"p""# + testCase.keysAfterPrompt + "}"
            let request = try JSONDecoder().decode(EditPromptRequest.self, from: Data(json.utf8))
            #expect(request.attachments == testCase.attachments, "\(json)")
        }
    }
#endif

    private func canonicalJSON<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try #require(String(bytes: try encoder.encode(value), encoding: .utf8))
    }
}

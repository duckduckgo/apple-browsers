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

    private struct Case {
        let images: [AIChatNativePrompt.NativePromptImage]?
        let files: [AIChatNativePrompt.NativePromptFile]?
        let expectedKeys: String

        var attachments: AIChatPromptAttachments {
            AIChatPromptAttachments(images: images, files: files)
        }
    }

    private static let cases: [Case] = [
        Case(images: nil, files: nil, expectedKeys: ""),
        Case(images: [], files: nil, expectedKeys: #","images":[]"#),
        Case(images: [image], files: nil, expectedKeys: #","images":["# + imageJSON + "]"),
        Case(images: nil, files: [], expectedKeys: #","files":[]"#),
        Case(images: nil, files: [file], expectedKeys: #","files":["# + fileJSON + "]"),
        Case(images: [], files: [], expectedKeys: #","files":[],"images":[]"#),
        Case(images: [image], files: [file], expectedKeys: #","files":["# + fileJSON + #"],"images":["# + imageJSON + "]"),
    ]

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func queryPromptEncodesEachAttachmentKindAsGiven() throws {
        for testCase in Self.cases {
            let prompt = AIChatNativePrompt.queryPrompt("p", autoSubmit: true, attachments: testCase.attachments)
            let expected = #"{"platform":"\#(Platform.name)","query":{"autoSubmit":true"# + testCase.expectedKeys + #","prompt":"p"},"tool":"query"}"#
            #expect(try canonicalJSON(prompt) == expected, "images: \(String(describing: testCase.images)), files: \(String(describing: testCase.files))")
        }
    }

#if os(iOS)
    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func editReplyEncodesEachAttachmentKindAsGiven() throws {
        for testCase in Self.cases {
            let reply = EditPromptReply.submit(prompt: "p", attachments: testCase.attachments)
            let expected = "{" + testCase.expectedKeys.dropFirst() + (testCase.expectedKeys.isEmpty ? "" : ",") + #""prompt":"p"}"#
            #expect(try canonicalJSON(reply) == expected, "images: \(String(describing: testCase.images)), files: \(String(describing: testCase.files))")
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func editRequestDecodesEachAttachmentKindAsGiven() throws {
        for testCase in Self.cases {
            let json = #"{"hasResponsesToLose":false"# + testCase.expectedKeys + #","prompt":"p"}"#
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

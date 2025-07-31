//
//  AIChatNativePromptTests.swift
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

import Foundation
import Testing
@testable import AIChat

struct AIChatNativePromptTests {

    @Test
    func decodingQuery() throws {
        let json = """
            {
                "platform": "\(Platform.name)",
                "tool": "query",
                "query": {
                    "prompt": "hello",
                    "autoSubmit": true
                }
            }
            """

        let prompt = try decodePrompt(from: json)
        #expect(prompt == AIChatNativePrompt.queryPrompt("hello", autoSubmit: true))
    }

    @Test
    func decodingSummary() throws {
        let json = """
            {
                "platform": "\(Platform.name)",
                "tool": "summary",
                "summary": {
                    "text": "This is a sample text to summarize",
                    "sourceURL": "https://example.com",
                    "sourceTitle": "Example Page"
                }
            }
            """

        let prompt = try decodePrompt(from: json)
        let expectedURL = URL(string: "https://example.com")
        #expect(prompt == AIChatNativePrompt.summaryPrompt("This is a sample text to summarize", url: expectedURL, title: "Example Page"))
    }

    @Test
    func encodingQuery() throws {
        let prompt = AIChatNativePrompt.queryPrompt("hello", autoSubmit: true)
        let jsonDict = try encodePrompt(prompt)

        let expected: [String: Any] = [
            "platform": Platform.name,
            "tool": "query",
            "query": [
                "prompt": "hello",
                "autoSubmit": true
            ]
        ]

        #expect(NSDictionary(dictionary: jsonDict).isEqual(to: expected))
    }

    @Test
    func encodingSummary() throws {
        let expectedURL = URL(string: "https://example.com")
        let prompt = AIChatNativePrompt.summaryPrompt("This is a sample text to summarize", url: expectedURL, title: "Example Page")
        let jsonDict = try encodePrompt(prompt)

        let expected: [String: Any] = [
            "platform": Platform.name,
            "tool": "summary",
            "summary": [
                "text": "This is a sample text to summarize",
                "sourceURL": "https://example.com",
                "sourceTitle": "Example Page"
            ]
        ]

        #expect(NSDictionary(dictionary: jsonDict).isEqual(to: expected))
    }

    // MARK: - Helpers

    private func decodePrompt(from json: String) throws -> AIChatNativePrompt {
        let jsonData = try #require(json.data(using: .utf8))
        return try JSONDecoder().decode(AIChatNativePrompt.self, from: jsonData)
    }

    private func encodePrompt(_ prompt: AIChatNativePrompt) throws -> [String: Any] {
        let jsonData = try JSONEncoder().encode(prompt)
        let jsonObject = try JSONSerialization.jsonObject(with: jsonData, options: [])
        return try #require(jsonObject as? [String: Any])
    }
}

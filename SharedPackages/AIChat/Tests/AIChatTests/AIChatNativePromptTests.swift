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

    @Test
    func decodingTranslation() throws {
        let json = """
            {
                "platform": "\(Platform.name)",
                "tool": "translation",
                "translation": {
                    "text": "This is a sample text to translate",
                    "sourceURL": "https://example.com",
                    "sourceTitle": "Example Page",
                    "sourceTLD": ".com",
                    "sourceLanguage": "en-US",
                    "targetLanguage": "es-ES"
                }
            }
            """

        let prompt = try decodePrompt(from: json)
        let expectedURL = URL(string: "https://example.com")
        #expect(prompt == AIChatNativePrompt.translationPrompt("This is a sample text to translate", url: expectedURL, title: "Example Page", sourceTLD: ".com", sourceLanguage: "en-US", targetLanguage: "es-ES"))
    }

    @Test
    func encodingTranslation() throws {
        let expectedURL = URL(string: "https://example.com")
        let prompt = AIChatNativePrompt.translationPrompt("This is a sample text to translate", url: expectedURL, title: "Example Page", sourceTLD: ".com", sourceLanguage: "en-US", targetLanguage: "es-ES")
        let jsonDict = try encodePrompt(prompt)

        let expected: [String: Any] = [
            "platform": Platform.name,
            "tool": "translation",
            "translation": [
                "text": "This is a sample text to translate",
                "sourceURL": "https://example.com",
                "sourceTitle": "Example Page",
                "sourceTLD": ".com",
                "sourceLanguage": "en-US",
                "targetLanguage": "es-ES"
            ]
        ]

        #expect(NSDictionary(dictionary: jsonDict).isEqual(to: expected))
    }

    @Test
    func decodingTranslationWithMinimalFields() throws {
        let json = """
            {
                "platform": "\(Platform.name)",
                "tool": "translation",
                "translation": {
                    "text": "Hello world",
                    "targetLanguage": "fr-FR"
                }
            }
            """

        let prompt = try decodePrompt(from: json)
        #expect(prompt == AIChatNativePrompt.translationPrompt("Hello world", url: nil, title: nil, sourceTLD: nil, sourceLanguage: nil, targetLanguage: "fr-FR"))
    }

    @Test
    func encodingTranslationWithMinimalFields() throws {
        let prompt = AIChatNativePrompt.translationPrompt("Hello world", url: nil, title: nil, sourceTLD: nil, sourceLanguage: nil, targetLanguage: "fr-FR")
        let jsonDict = try encodePrompt(prompt)

        let expected: [String: Any] = [
            "platform": Platform.name,
            "tool": "translation",
            "translation": [
                "text": "Hello world",
                "sourceLanguage": nil,
                "sourceTLD": nil,
                "targetLanguage": "fr-FR"
            ]
        ]

        #expect(NSDictionary(dictionary: jsonDict).isEqual(to: expected))
    }

    @Test
    func encodingQueryWithPageContext() throws {
        let pageContext = AIChatPageContextData(
            title: "Example Page",
            favicon: [AIChatPageContextData.PageContextFavicon(href: "data:image/png;base64,abc", rel: "icon")],
            url: "https://example.com",
            content: "Page content here",
            truncated: false,
            fullContentLength: 100
        )
        let prompt = AIChatNativePrompt.queryPrompt("Summarize this", autoSubmit: true, pageContext: pageContext)
        let jsonDict = try encodePrompt(prompt)

        #expect(jsonDict["platform"] as? String == Platform.name)
        #expect(jsonDict["tool"] as? String == "query")

        let queryDict = try #require(jsonDict["query"] as? [String: Any])
        #expect(queryDict["prompt"] as? String == "Summarize this")
        #expect(queryDict["autoSubmit"] as? Bool == true)

        let pageContextDict = try #require(jsonDict["pageContext"] as? [String: Any])
        #expect(pageContextDict["title"] as? String == "Example Page")
        #expect(pageContextDict["url"] as? String == "https://example.com")
        #expect(pageContextDict["content"] as? String == "Page content here")
        #expect(pageContextDict["truncated"] as? Bool == false)
        #expect(pageContextDict["fullContentLength"] as? Int == 100)

        let faviconArray = try #require(pageContextDict["favicon"] as? [[String: String]])
        #expect(faviconArray.count == 1)
        #expect(faviconArray[0]["href"] == "data:image/png;base64,abc")
        #expect(faviconArray[0]["rel"] == "icon")
    }

    @Test
    func decodingQueryWithPageContext() throws {
        let json = """
            {
                "platform": "\(Platform.name)",
                "tool": "query",
                "query": {
                    "prompt": "Summarize this",
                    "autoSubmit": true
                },
                "pageContext": {
                    "title": "Example Page",
                    "favicon": [{"href": "data:image/png;base64,abc", "rel": "icon"}],
                    "url": "https://example.com",
                    "content": "Page content here",
                    "truncated": false,
                    "fullContentLength": 100
                }
            }
            """

        let prompt = try decodePrompt(from: json)

        let expectedPageContext = AIChatPageContextData(
            title: "Example Page",
            favicon: [AIChatPageContextData.PageContextFavicon(href: "data:image/png;base64,abc", rel: "icon")],
            url: "https://example.com",
            content: "Page content here",
            truncated: false,
            fullContentLength: 100
        )
        let expectedPrompt = AIChatNativePrompt.queryPrompt("Summarize this", autoSubmit: true, pageContext: expectedPageContext)

        #expect(prompt == expectedPrompt)
    }

    // MARK: - Query with Images and Model

    @Test
    func encodingQueryWithImagesAndModel() throws {
        let images = [
            AIChatNativePrompt.NativePromptImage(data: "base64data", format: "png")
        ]
        let prompt = AIChatNativePrompt.queryPrompt("Describe this", autoSubmit: true, images: images, modelId: "gpt-4o")
        let jsonDict = try encodePrompt(prompt)

        let queryDict = try #require(jsonDict["query"] as? [String: Any])
        #expect(queryDict["prompt"] as? String == "Describe this")
        #expect(queryDict["autoSubmit"] as? Bool == true)
        #expect(queryDict["modelId"] as? String == "gpt-4o")

        let imagesArray = try #require(queryDict["images"] as? [[String: String]])
        #expect(imagesArray.count == 1)
        #expect(imagesArray[0]["data"] == "base64data")
        #expect(imagesArray[0]["format"] == "png")
    }

    @Test
    func encodingQueryWithoutOptionalFields() throws {
        let prompt = AIChatNativePrompt.queryPrompt("hello", autoSubmit: true)
        let jsonDict = try encodePrompt(prompt)

        let queryDict = try #require(jsonDict["query"] as? [String: Any])
        #expect(queryDict["prompt"] as? String == "hello")
        #expect(queryDict["autoSubmit"] as? Bool == true)
        // Optional fields should be nil/absent
        #expect(queryDict["modelId"] == nil || queryDict["modelId"] is NSNull)
        #expect(queryDict["images"] == nil || queryDict["images"] is NSNull)
        #expect(queryDict["toolChoice"] == nil || queryDict["toolChoice"] is NSNull)
    }

    @Test
    func decodingQueryWithImagesAndModel() throws {
        let json = """
            {
                "platform": "\(Platform.name)",
                "tool": "query",
                "query": {
                    "prompt": "Describe this",
                    "autoSubmit": true,
                    "modelId": "gpt-4o",
                    "images": [
                        {"data": "base64data", "format": "png"}
                    ]
                }
            }
            """

        let prompt = try decodePrompt(from: json)

        let images = [AIChatNativePrompt.NativePromptImage(data: "base64data", format: "png")]
        let expected = AIChatNativePrompt.queryPrompt("Describe this", autoSubmit: true, images: images, modelId: "gpt-4o")
        #expect(prompt == expected)
    }

    @Test
    func decodingQueryWithoutOptionalFieldsIsBackwardCompatible() throws {
        // Old-format JSON without the new optional fields should still decode
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
    func encodingQueryWithMultipleImages() throws {
        let images = [
            AIChatNativePrompt.NativePromptImage(data: "img1", format: "png"),
            AIChatNativePrompt.NativePromptImage(data: "img2", format: "png"),
        ]
        let prompt = AIChatNativePrompt.queryPrompt("Compare these", autoSubmit: true, images: images)
        let jsonDict = try encodePrompt(prompt)

        let queryDict = try #require(jsonDict["query"] as? [String: Any])
        let imagesArray = try #require(queryDict["images"] as? [[String: String]])
        #expect(imagesArray.count == 2)
        #expect(imagesArray[0]["data"] == "img1")
        #expect(imagesArray[1]["data"] == "img2")
    }

    @Test
    func encodingQueryWithToolChoice() throws {
        let prompt = AIChatNativePrompt.queryPrompt("Search for this", autoSubmit: true, toolChoice: ["WebSearch"])
        let jsonDict = try encodePrompt(prompt)

        let queryDict = try #require(jsonDict["query"] as? [String: Any])
        let toolChoice = try #require(queryDict["toolChoice"] as? [String])
        #expect(toolChoice == ["WebSearch"])
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

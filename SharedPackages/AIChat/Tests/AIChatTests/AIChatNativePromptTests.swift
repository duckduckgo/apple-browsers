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
    func encodingQueryWithSinglePageContext() throws {
        let pageContext = AIChatPageContextData(
            title: "Example Page",
            favicon: [AIChatPageContextData.PageContextFavicon(href: "data:image/png;base64,abc", rel: "icon")],
            url: "https://example.com",
            content: "Page content here",
            truncated: false,
            fullContentLength: 100
        )
        let prompt = AIChatNativePrompt.queryPrompt("Summarize this", autoSubmit: true, pageContext: .single(pageContext))
        let jsonDict = try encodePrompt(prompt)

        #expect(jsonDict["platform"] as? String == Platform.name)
        #expect(jsonDict["tool"] as? String == "query")

        let queryDict = try #require(jsonDict["query"] as? [String: Any])
        #expect(queryDict["prompt"] as? String == "Summarize this")
        #expect(queryDict["autoSubmit"] as? Bool == true)

        // .single → top-level `pageContext` serializes as a JSON object (sidebar's current-page shape)
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
    func decodingQueryWithSinglePageContext() throws {
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
        let expectedPrompt = AIChatNativePrompt.queryPrompt("Summarize this", autoSubmit: true, pageContext: .single(expectedPageContext))

        #expect(prompt == expectedPrompt)
    }

    @Test
    func encodingQueryWithMultiplePageContexts() throws {
        // Omnibar case: array of contexts. The first entry has no `tabId` (the active tab's
        // page — discriminator says "current page"); the rest carry `tabId`.
        let activePage = AIChatPageContextData(
            title: "Active",
            favicon: [],
            url: "https://active.example",
            content: "active content",
            truncated: false,
            fullContentLength: 14
        )
        let pickerTabA = AIChatPageContextData(
            title: "Tab A",
            favicon: [],
            url: "https://a.example",
            content: "A content",
            truncated: false,
            fullContentLength: 9,
            tabId: "uuid-A"
        )
        let pickerTabB = AIChatPageContextData(
            title: "Tab B",
            favicon: [],
            url: "https://b.example",
            content: "B content",
            truncated: false,
            fullContentLength: 9,
            tabId: "uuid-B"
        )
        let prompt = AIChatNativePrompt.queryPrompt(
            "Summarize these",
            autoSubmit: true,
            pageContext: .multiple([activePage, pickerTabA, pickerTabB])
        )
        let jsonDict = try encodePrompt(prompt)

        // .multiple → top-level `pageContext` serializes as a JSON array (omnibar's multi shape)
        let arr = try #require(jsonDict["pageContext"] as? [[String: Any]])
        #expect(arr.count == 3)
        #expect(arr[0]["title"] as? String == "Active")
        // The discriminator: NSNull means key present but null; for an omitted key
        // `arr[0]["tabId"]` would be nil. Both are acceptable to the frontend; assert the
        // value is treated as "absence" (nil or NSNull, never a string).
        let activeTabIdValue = arr[0]["tabId"]
        let activeIsAbsent = activeTabIdValue == nil || activeTabIdValue is NSNull
        #expect(activeIsAbsent, "Active page entry must NOT carry a non-null tabId (discriminator: no tabId = current page)")
        #expect(arr[1]["tabId"] as? String == "uuid-A")
        #expect(arr[2]["tabId"] as? String == "uuid-B")
    }

    @Test
    func decodingQueryWithMultiplePageContexts() throws {
        // The decoder must round-trip the array form back into `.multiple([...])`.
        let json = """
            {
                "platform": "\(Platform.name)",
                "tool": "query",
                "query": {
                    "prompt": "Summarize these",
                    "autoSubmit": true
                },
                "pageContext": [
                    {
                        "title": "Tab A",
                        "favicon": [],
                        "url": "https://a.example",
                        "content": "A content",
                        "truncated": false,
                        "fullContentLength": 9,
                        "tabId": "uuid-A"
                    },
                    {
                        "title": "Tab B",
                        "favicon": [],
                        "url": "https://b.example",
                        "content": "B content",
                        "truncated": false,
                        "fullContentLength": 9,
                        "tabId": "uuid-B"
                    }
                ]
            }
            """
        let prompt = try decodePrompt(from: json)
        guard case .multiple(let contexts) = try #require(prompt.pageContext) else {
            Issue.record("Expected `.multiple` payload variant")
            return
        }
        #expect(contexts.count == 2)
        #expect(contexts[0].tabId == "uuid-A")
        #expect(contexts[1].tabId == "uuid-B")
    }

    @Test
    func encodingPageContextOmittedWhenNil() throws {
        // No `pageContext` → key must be absent from the JSON (the duck.ai web app sees a
        // payload identical to the pre-M8 prompt shape, so existing flows are untouched).
        let prompt = AIChatNativePrompt.queryPrompt("hello", autoSubmit: true)
        let jsonDict = try encodePrompt(prompt)
        #expect(jsonDict["pageContext"] == nil)
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
    func encodingQueryWithReasoningEffort() throws {
        let prompt = AIChatNativePrompt.queryPrompt("Describe this", autoSubmit: true, modelId: "gpt-5.2", reasoningEffort: .medium)
        let jsonDict = try encodePrompt(prompt)

        let queryDict = try #require(jsonDict["query"] as? [String: Any])
        #expect(queryDict["modelId"] as? String == "gpt-5.2")
        #expect(queryDict["reasoningEffort"] as? String == "medium")
    }

    @Test
    func encodingQueryWithNoReasoningEffort() throws {
        let prompt = AIChatNativePrompt.queryPrompt("Answer quickly", autoSubmit: true, modelId: "gpt-5.2", reasoningEffort: AIChatReasoningEffort.none)
        let jsonDict = try encodePrompt(prompt)

        let queryDict = try #require(jsonDict["query"] as? [String: Any])
        #expect(queryDict["modelId"] as? String == "gpt-5.2")
        #expect(queryDict["reasoningEffort"] as? String == "none")
    }

    @Test
    func encodingQueryWithoutOptionalFields() throws {
        let prompt = AIChatNativePrompt.queryPrompt("hello", autoSubmit: true)
        let jsonDict = try encodePrompt(prompt)

        let queryDict = try #require(jsonDict["query"] as? [String: Any])
        #expect(queryDict["prompt"] as? String == "hello")
        #expect(queryDict["autoSubmit"] as? Bool == true)
        #expect(queryDict["modelId"] == nil)
        #expect(queryDict["images"] == nil)
        #expect(queryDict["files"] == nil)
        #expect(queryDict["toolChoice"] == nil)
        #expect(queryDict["mode"] == nil)
        #expect(queryDict["reasoningEffort"] == nil)
        // M8 — `query.attachedTabIds` no longer exists; multi-tab attachments live at the
        // top-level `pageContext: PageContext[]` per the duck.ai tech design.
        #expect(queryDict["attachedTabIds"] == nil)
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
    func decodingQueryWithReasoningEffort() throws {
        let json = """
            {
                "platform": "\(Platform.name)",
                "tool": "query",
                "query": {
                    "prompt": "Think through this",
                    "autoSubmit": true,
                    "modelId": "claude-opus-4-6",
                    "reasoningEffort": "low"
                }
            }
            """

        let prompt = try decodePrompt(from: json)
        let expected = AIChatNativePrompt.queryPrompt("Think through this", autoSubmit: true, modelId: "claude-opus-4-6", reasoningEffort: .low)
        #expect(prompt == expected)
    }

    @Test
    func decodingQueryWithUnknownReasoningEffortIgnoresReasoningEffort() throws {
        let json = """
            {
                "platform": "\(Platform.name)",
                "tool": "query",
                "query": {
                    "prompt": "Think through this",
                    "autoSubmit": true,
                    "modelId": "future-model",
                    "reasoningEffort": "future-effort"
                }
            }
            """

        let prompt = try decodePrompt(from: json)
        let expected = AIChatNativePrompt.queryPrompt("Think through this", autoSubmit: true, modelId: "future-model")
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
    func encodingQueryWithFiles() throws {
        let files = [
            AIChatNativePrompt.NativePromptFile(data: "base64pdf", fileName: "test.pdf", mimeType: "application/pdf")
        ]
        let prompt = AIChatNativePrompt.queryPrompt("Summarize this file", autoSubmit: true, files: files, modelId: "gpt-4o")
        let jsonDict = try encodePrompt(prompt)

        let queryDict = try #require(jsonDict["query"] as? [String: Any])
        let filesArray = try #require(queryDict["files"] as? [[String: String]])
        #expect(filesArray.count == 1)
        #expect(filesArray[0]["data"] == "base64pdf")
        #expect(filesArray[0]["fileName"] == "test.pdf")
        #expect(filesArray[0]["mimeType"] == "application/pdf")
    }

    @Test
    func encodingQueryWithImagesAndFiles() throws {
        let images = [
            AIChatNativePrompt.NativePromptImage(data: "base64image", format: "png")
        ]
        let files = [
            AIChatNativePrompt.NativePromptFile(data: "base64pdf", fileName: "test.pdf", mimeType: "application/pdf")
        ]
        let prompt = AIChatNativePrompt.queryPrompt("Compare these attachments", autoSubmit: true, images: images, files: files, modelId: "gpt-5-mini")
        let jsonDict = try encodePrompt(prompt)

        let queryDict = try #require(jsonDict["query"] as? [String: Any])
        let imagesArray = try #require(queryDict["images"] as? [[String: String]])
        let filesArray = try #require(queryDict["files"] as? [[String: String]])
        #expect(imagesArray.count == 1)
        #expect(filesArray.count == 1)
        #expect(imagesArray[0]["data"] == "base64image")
        #expect(filesArray[0]["data"] == "base64pdf")
    }

    @Test
    func decodingQueryWithFiles() throws {
        let json = """
            {
                "platform": "\(Platform.name)",
                "tool": "query",
                "query": {
                    "prompt": "Summarize this file",
                    "autoSubmit": true,
                    "files": [
                        {
                            "data": "base64pdf",
                            "fileName": "test.pdf",
                            "mimeType": "application/pdf"
                        }
                    ]
                }
            }
            """

        let prompt = try decodePrompt(from: json)
        let files = [AIChatNativePrompt.NativePromptFile(data: "base64pdf", fileName: "test.pdf", mimeType: "application/pdf")]
        let expected = AIChatNativePrompt.queryPrompt("Summarize this file", autoSubmit: true, files: files)
        #expect(prompt == expected)
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

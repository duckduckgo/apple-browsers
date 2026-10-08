//
//  DuckAiChatDecodeTests.swift
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

import XCTest
@testable import AIChat

final class DuckAiChatDecodeTests: XCTestCase {

    // MARK: - isImageGeneration

    func testIsImageGeneration_trueWhenAssistantHasGenerateImageUiComponent() throws {
        let json = """
            {
              "chatId": "c1",
              "model": "gpt-5-mini",
              "messages": [
                {"role":"user","content":"draw a duck"},
                {"role":"assistant","content":"","parts":[
                  {"type":"ui-component","name":"generate-image"}
                ]}
              ]
            }
            """

        let decoded = try DuckAiChat.decode(from: Data(json.utf8))
        XCTAssertTrue(decoded.chat.isImageGeneration)
    }

    func testIsImageGeneration_falseForRegularDiscussion() throws {
        let json = """
            {
              "chatId": "c1",
              "model": "gpt-5-mini",
              "messages": [
                {"role":"user","content":"hi"},
                {"role":"assistant","content":"","parts":[
                  {"type":"text","text":"hello"}
                ]}
              ]
            }
            """

        let decoded = try DuckAiChat.decode(from: Data(json.utf8))
        XCTAssertFalse(decoded.chat.isImageGeneration)
    }

    func testIsImageGeneration_falseWhenUiComponentExistsButIsNotGenerateImage() throws {
        // Other tool-call components ("citation", future names, etc.) must not flip the flag.
        let json = """
            {
              "chatId": "c1",
              "model": "gpt-5-mini",
              "messages": [
                {"role":"user","content":"hi"},
                {"role":"assistant","content":"","parts":[
                  {"type":"ui-component","name":"citation"}
                ]}
              ]
            }
            """

        let decoded = try DuckAiChat.decode(from: Data(json.utf8))
        XCTAssertFalse(decoded.chat.isImageGeneration)
    }

    func testIsImageGeneration_falseWhenUserMessageHasGenerateImagePart() throws {
        // Only assistant messages count — protects against a malformed user message
        // slipping through.
        let json = """
            {
              "chatId": "c1",
              "model": "gpt-5-mini",
              "messages": [
                {"role":"user","content":"","parts":[
                  {"type":"ui-component","name":"generate-image"}
                ]}
              ]
            }
            """

        let decoded = try DuckAiChat.decode(from: Data(json.utf8))
        XCTAssertFalse(decoded.chat.isImageGeneration)
    }

    func testIsImageGeneration_falseWhenMessagesAreAbsent() throws {
        let json = #"{"chatId":"c1","model":"gpt-5-mini"}"#

        let decoded = try DuckAiChat.decode(from: Data(json.utf8))
        XCTAssertFalse(decoded.chat.isImageGeneration)
    }

    // MARK: - Resilience

    func testAssistantToolCallWithoutContentField_stillDecodes() throws {
        // Assistant messages can ship `parts` without `content`. The decoder must keep the
        // `messages` array intact (so `isImageGeneration` can still inspect it) rather than
        // failing the whole decode.
        let json = """
            {
              "chatId": "c1",
              "model": "gpt-5-mini",
              "messages": [
                {"role":"user","content":"hi"},
                {"role":"assistant","parts":[
                  {"type":"ui-component","name":"generate-image"}
                ]}
              ]
            }
            """

        let decoded = try DuckAiChat.decode(from: Data(json.utf8))
        XCTAssertTrue(decoded.chat.isImageGeneration,
                      "Assistant tool-call message without `content` must not block the detection")
    }

    // MARK: - lastMessageContent

    func testWhenLastMessageIsAssistantTextThenLastMessageContentIsAssistantText() throws {
        let json = """
            {
              "chatId": "c1",
              "model": "gpt-5-mini",
              "messages": [
                {"role":"user","content":"hello"},
                {"role":"assistant","content":"hi there!"}
              ]
            }
            """

        let decoded = try DuckAiChat.decode(from: Data(json.utf8))
        XCTAssertEqual(decoded.lastMessageContent, "hi there!")
    }

    func testWhenLastMessageIsUserTextThenLastMessageContentIsUserText() throws {
        let json = """
            {
              "chatId": "c1",
              "model": "gpt-5-mini",
              "messages": [
                {"role":"assistant","content":"earlier reply"},
                {"role":"user","content":"a follow up"}
              ]
            }
            """

        let decoded = try DuckAiChat.decode(from: Data(json.utf8))
        XCTAssertEqual(decoded.lastMessageContent, "a follow up")
    }

    func testWhenLastMessageContentIsRichObjectThenTextValueIsExtracted() throws {
        let json = """
            {
              "chatId": "c1",
              "model": "gpt-5-mini",
              "messages": [
                {"role":"user","content":"what's this?"},
                {"role":"assistant","content":{"text":"a duck","images":[]}}
              ]
            }
            """

        let decoded = try DuckAiChat.decode(from: Data(json.utf8))
        XCTAssertEqual(decoded.lastMessageContent, "a duck")
    }

    func testWhenLastMessageHasOnlyPartsThenLastMessageContentIsNil() throws {
        let json = """
            {
              "chatId": "c1",
              "model": "gpt-5-mini",
              "messages": [
                {"role":"user","content":"draw a duck"},
                {"role":"assistant","parts":[
                  {"type":"ui-component","name":"generate-image"}
                ]}
              ]
            }
            """

        let decoded = try DuckAiChat.decode(from: Data(json.utf8))
        XCTAssertNil(decoded.lastMessageContent)
    }

    func testWhenLastMessageHasEmptyContentAndTextPartThenLastMessageContentIsExtractedFromParts() throws {
        // Reasoning models (e.g. `gpt-5-mini`) ship assistant responses with `content == ""`
        // and the visible text inside `parts[].text` where `type == "text"`. Consecutive text
        // parts are streaming chunks, which the web app shows as one block.
        let json = """
            {
              "chatId": "c1",
              "model": "gpt-5-mini",
              "messages": [
                {"role":"user","content":"hello"},
                {"role":"assistant","content":"","parts":[
                  {"type":"reasoning","encryptedText":"opaque"},
                  {"type":"text","text":"the actual "},
                  {"type":"text","text":"reply"}
                ]}
              ]
            }
            """

        let decoded = try DuckAiChat.decode(from: Data(json.utf8))
        XCTAssertEqual(decoded.lastMessageContent, "the actual reply")
    }

    func testWhenLastMessageHasContentAndTextPartThenContentWins() throws {
        // When both fields are populated the top-level `content` is authoritative (it's what
        // every non-reasoning chat uses). `parts` is only consulted as a fallback.
        let json = """
            {
              "chatId": "c1",
              "model": "gpt-5-mini",
              "messages": [
                {"role":"user","content":"hello"},
                {"role":"assistant","content":"top level","parts":[
                  {"type":"text","text":"from parts"}
                ]}
              ]
            }
            """

        let decoded = try DuckAiChat.decode(from: Data(json.utf8))
        XCTAssertEqual(decoded.lastMessageContent, "top level")
    }

    func testWhenMessagesArrayIsAbsentThenLastMessageContentIsNil() throws {
        let json = #"{"chatId":"c1","model":"gpt-5-mini"}"#

        let decoded = try DuckAiChat.decode(from: Data(json.utf8))
        XCTAssertNil(decoded.lastMessageContent)
    }

    func testWhenMessagesArrayIsEmptyThenLastMessageContentIsNil() throws {
        let json = #"{"chatId":"c1","model":"gpt-5-mini","messages":[]}"#

        let decoded = try DuckAiChat.decode(from: Data(json.utf8))
        XCTAssertNil(decoded.lastMessageContent)
    }

    // MARK: - Canonical format

    func testWhenContentIsCanonicalPartsArrayThenChatDecodesWithTextFromTextParts() throws {
        let json = """
            {
              "version": "1.2",
              "chatId": "c1",
              "title": "Capital of France",
              "model": "gpt-4o-mini",
              "pinned": true,
              "lastEdit": "2026-07-08T15:04:03.000Z",
              "messages": [
                {"id":"m1","role":"user","createdAt":"2026-07-08T15:04:00.000Z",
                 "content":[{"type":"text","text":"What's the capital of France?"}]},
                {"id":"m2","role":"assistant","createdAt":"2026-07-08T15:04:03.000Z",
                 "content":[{"type":"text","text":"The capital of France is Paris."}]}
              ]
            }
            """

        let decoded = try DuckAiChat.decode(from: Data(json.utf8))
        XCTAssertEqual(decoded.chat.chatId, "c1")
        XCTAssertEqual(decoded.chat.title, "Capital of France")
        XCTAssertTrue(decoded.chat.pinned)
        XCTAssertEqual(decoded.firstUserMessageContent, "What's the capital of France?")
        XCTAssertEqual(decoded.lastMessageContent, "The capital of France is Paris.")
    }

    func testWhenCanonicalContentHasNonTextPartsThenOnlyTextPartsAreUsed() throws {
        // `reasoning-progress` parts carry `text` too, but it's reasoning rather than the reply,
        // and `text-pasted` parts hold pasted attachments rather than the prompt.
        let json = """
            {
              "chatId": "c1",
              "messages": [
                {"id":"m1","role":"user","createdAt":"2026-09-30T12:00:00.000Z","content":[
                  {"type":"text-pasted","id":"p1","content":"a long pasted log"},
                  {"type":"text","text":"Summarize this."}
                ]},
                {"id":"m2","role":"assistant","createdAt":"2026-09-30T12:00:05.000Z","content":[
                  {"type":"reasoning-progress","id":"r1","partIndex":0,"text":"thinking it over","complete":true},
                  {"type":"tool-call","toolCallId":"tc1","toolName":"web_search","toolArguments":"{}"},
                  {"type":"text","text":"Here's a summary."}
                ]}
              ]
            }
            """

        let decoded = try DuckAiChat.decode(from: Data(json.utf8))
        XCTAssertEqual(decoded.firstUserMessageContent, "Summarize this.")
        XCTAssertEqual(decoded.lastMessageContent, "Here's a summary.")
    }

    func testIsImageGeneration_trueWhenCanonicalAssistantContentHasGenerateImageUiComponent() throws {
        let json = """
            {
              "chatId": "c1",
              "model": "gpt-5-mini",
              "messages": [
                {"id":"m1","role":"user","createdAt":"2026-10-01T10:00:00.000Z",
                 "content":[{"type":"text","text":"draw a duck"}]},
                {"id":"m2","role":"assistant","createdAt":"2026-10-01T10:00:05.000Z","content":[
                  {"type":"ui-component","id":"ui1","name":"generate-image"}
                ]}
              ]
            }
            """

        let decoded = try DuckAiChat.decode(from: Data(json.utf8))
        XCTAssertTrue(decoded.chat.isImageGeneration)
    }

    func testWhenCanonicalTextPartsAreSplitByToolCallThenEachRunIsOneBlock() throws {
        // The web app shows consecutive text parts (streaming chunks) as one block, and starts a
        // new block after a tool call or search results.
        let json = """
            {
              "chatId": "c1",
              "messages": [
                {"id":"m1","role":"assistant","createdAt":"2026-10-01T10:00:05.000Z","content":[
                  {"type":"text","text":"Let me "},
                  {"type":"text","text":"look that up."},
                  {"type":"tool-call","toolCallId":"tc1","toolName":"web_search","toolArguments":"{}"},
                  {"type":"tool-result","toolCallId":"tc1","result":"ok"},
                  {"type":"text","text":"Here's what "},
                  {"type":"text","text":"I found."}
                ]}
              ]
            }
            """

        let decoded = try DuckAiChat.decode(from: Data(json.utf8))
        XCTAssertEqual(decoded.lastMessageContent, "Let me look that up.\n\nHere's what I found.")
    }

    func testWhenMessageContentHasUnknownShapeThenChatStillDecodesWithoutPreviews() throws {
        // The chat header always decodes, so the chat stays listed; content in a shape this
        // build doesn't know only costs the previews.
        let json = """
            {
              "version": "2.0",
              "chatId": "c1",
              "title": "From a newer client",
              "pinned": true,
              "messages": [
                {"id":"m1","role":"user","createdAt":"2026-12-01T10:00:00.000Z","content":{"blocks":[]}}
              ]
            }
            """

        let decoded = try DuckAiChat.decode(from: Data(json.utf8))
        XCTAssertEqual(decoded.chat.title, "From a newer client")
        XCTAssertTrue(decoded.chat.pinned)
        XCTAssertNil(decoded.firstUserMessageContent)
        XCTAssertNil(decoded.lastMessageContent)
    }
}

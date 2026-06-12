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
        // and the visible text inside `parts[].text` where `type == "text"`.
        let json = """
            {
              "chatId": "c1",
              "model": "gpt-5-mini",
              "messages": [
                {"role":"user","content":"hello"},
                {"role":"assistant","content":"","parts":[
                  {"type":"reasoning","encryptedText":"opaque"},
                  {"type":"text","text":"the actual reply"},
                  {"type":"text","text":"second line"}
                ]}
              ]
            }
            """

        let decoded = try DuckAiChat.decode(from: Data(json.utf8))
        XCTAssertEqual(decoded.lastMessageContent, "the actual reply\n\nsecond line")
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
}

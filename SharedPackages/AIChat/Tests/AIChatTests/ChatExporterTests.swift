//
//  ChatExporterTests.swift
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

final class ChatExporterTests: XCTestCase {

    /// Fixed TimeZone so the asserted "4:23:15 PM" timestamps reproduce on any CI machine
    /// (Europe/Paris = UTC+2 in May 2026; the test JSON's 14:23:15 UTC renders as 4:23:15 PM local).
    private let exporter = ChatExporter(timeZone: TimeZone(identifier: "Europe/Paris")!)

    private let gpt5MiniDisplay = ModelDisplay(
        fullName: "GPT-5 mini",
        shortName: "GPT-5 mini",
        providerPossessive: "OpenAI's"
    )

    // MARK: - Discussion

    func testDiscussion_singleTurn_matchesCrossPlatformReferenceOutput() throws {
        let result = try exporter.export(rawJson: Self.specChatJSON, chatType: .discussion, modelDisplay: gpt5MiniDisplay)

        let expected = """
            This conversation was generated with Duck.ai (https://duck.ai) using OpenAI's GPT-5 mini Model. AI chats may display inaccurate or offensive information (see https://duckduckgo.com/duckai/privacy-terms for more info).

            ====================

            User prompt 1 of 1 - 5/15/2026, 4:23:15 PM:
            cat

            GPT-5 mini:
            Do you want a picture, facts, care tips, behavior explanation, name ideas, or something else about cats?
            """

        guard case .text(let content) = result else {
            XCTFail("Expected `.text`, got \(result)"); return
        }
        XCTAssertEqual(content, expected)
    }

    func testDiscussion_multiTurn_insertsTurnSeparatorBetweenTurns() throws {
        let result = try exporter.export(rawJson: Self.twoTurnJSON, chatType: .discussion, modelDisplay: gpt5MiniDisplay)

        guard case .text(let output) = result else {
            XCTFail("Expected `.text`, got \(result)"); return
        }
        XCTAssertTrue(output.contains("User prompt 1 of 2 - 5/15/2026, 4:00:00 PM:"), "turn 1 numbering")
        XCTAssertTrue(output.contains("User prompt 2 of 2 - 5/15/2026, 4:01:00 PM:"), "turn 2 numbering")
        XCTAssertTrue(output.contains("Hello!\n\n--------------------\n\nUser prompt 2"),
                      "turn separator sits between turns")
    }

    func testDiscussion_assistantText_fallsBackToContentWhenPartsArrayAbsent() throws {
        let json = """
            {
              "model": "gpt-5-mini",
              "messages": [
                {"role":"user","createdAt":"2026-05-15T14:00:00.000Z","content":"hello"},
                {"role":"assistant","createdAt":"2026-05-15T14:00:01.000Z","content":"plain-content fallback"}
              ]
            }
            """

        let result = try exporter.export(rawJson: Data(json.utf8), chatType: .discussion, modelDisplay: gpt5MiniDisplay)

        guard case .text(let content) = result else {
            XCTFail("Expected `.text`, got \(result)"); return
        }
        XCTAssertTrue(content.contains("GPT-5 mini:\nplain-content fallback"))
    }

    func testDiscussion_multipleTextParts_joinedWithoutSeparator() throws {
        // FE stores streaming response chunks as individual text parts; they must be
        // concatenated without any separator so mid-word splits don't appear in the export.
        let json = """
            {
              "model": "gpt-5-mini",
              "messages": [
                {"role":"user","createdAt":"2026-05-15T14:00:00.000Z","content":"hi"},
                {"role":"assistant","content":"","parts":[
                  {"type":"text","text":"Ass"},
                  {"type":"text","text":"uming"},
                  {"type":"text","text":" you mean a dog breed."}
                ]}
              ]
            }
            """

        let result = try exporter.export(rawJson: Data(json.utf8), chatType: .discussion, modelDisplay: gpt5MiniDisplay)

        guard case .text(let content) = result else {
            XCTFail("Expected `.text`, got \(result)"); return
        }
        XCTAssertTrue(content.contains("GPT-5 mini:\nAssuming you mean a dog breed."),
                      "streaming chunks must be joined without newlines")
    }

    func testDiscussion_reasoningParts_areIgnored_onlyTextPartsAreIncluded() throws {
        let json = """
            {
              "model": "gpt-5-mini",
              "messages": [
                {"role":"user","createdAt":"2026-05-15T14:00:00.000Z","content":"hi"},
                {"role":"assistant","content":"","parts":[
                  {"type":"reasoning","encryptedText":"secret"},
                  {"type":"text","text":"only this is visible"}
                ]}
              ]
            }
            """

        let result = try exporter.export(rawJson: Data(json.utf8), chatType: .discussion, modelDisplay: gpt5MiniDisplay)

        guard case .text(let content) = result else {
            XCTFail("Expected `.text`, got \(result)"); return
        }
        XCTAssertTrue(content.contains("only this is visible"))
        XCTAssertFalse(content.contains("secret"), "reasoning text is omitted")
    }

    // MARK: - Voice

    func testVoice_assistantPrefix_isTheLiteralVoiceChatLabel() throws {
        let result = try exporter.export(rawJson: Self.twoTurnJSON, chatType: .voice, modelDisplay: gpt5MiniDisplay)

        guard case .text(let output) = result else {
            XCTFail("Expected `.text`, got \(result)"); return
        }
        XCTAssertTrue(output.contains("Voice Chat:\nHello!"), "uses literal Voice Chat prefix")
        XCTAssertFalse(output.contains("GPT-5 mini:"), "does not use the model name as prefix")
    }

    func testVoice_skipsAssistantBlock_whenThereIsNoModelResponse() throws {
        let json = """
            {
              "model": "voice-mode",
              "messages": [
                {"role":"user","createdAt":"2026-05-15T14:00:00.000Z","content":"hi"},
                {"role":"user","createdAt":"2026-05-15T14:01:00.000Z","content":"bye"},
                {"role":"assistant","createdAt":"2026-05-15T14:01:01.000Z","content":"","parts":[{"type":"text","text":"Goodbye!"}]}
              ]
            }
            """

        let result = try exporter.export(rawJson: Data(json.utf8), chatType: .voice, modelDisplay: gpt5MiniDisplay)

        guard case .text(let output) = result else {
            XCTFail("Expected `.text`, got \(result)"); return
        }
        XCTAssertTrue(output.contains("hi\n\n--------------------"), "user-only turn has no assistant block")
        XCTAssertTrue(output.contains("Voice Chat:\nGoodbye!"), "responded turn keeps Voice Chat block")
    }

    // MARK: - Image generation

    func testImageGeneration_replacesAssistantTextWithPlaceholder_andConsumesFileRefsPositionally() throws {
        let result = try exporter.export(
            rawJson: Self.twoTurnJSON,
            chatType: .imageGeneration,
            fileRefs: ["uuid-1", "uuid-2"],
            modelDisplay: gpt5MiniDisplay
        )

        guard case .zip(let content, let consumed) = result else {
            XCTFail("Expected `.zip`, got \(result)"); return
        }
        XCTAssertEqual(consumed, ["uuid-1", "uuid-2"])
        XCTAssertTrue(content.contains("GPT-5 mini:\n\n[Generated image: image-1.jpeg]"),
                      "turn 1 carries the image-1 placeholder")
        XCTAssertTrue(content.contains("GPT-5 mini:\n\n[Generated image: image-2.jpeg]"),
                      "turn 2 carries the image-2 placeholder")
        XCTAssertFalse(content.contains("Hello!"), "model's text response is replaced by the placeholder")
        XCTAssertFalse(content.contains("Goodbye!"))
    }

    func testImageGeneration_handlesMissingFileRefsGracefully() throws {
        let result = try exporter.export(
            rawJson: Self.twoTurnJSON,
            chatType: .imageGeneration,
            fileRefs: [],
            modelDisplay: gpt5MiniDisplay
        )

        guard case .zip(let content, let consumed) = result else {
            XCTFail("Expected `.zip`, got \(result)"); return
        }
        XCTAssertTrue(consumed.isEmpty, "no fileRefs consumed")
        XCTAssertTrue(content.contains("GPT-5 mini:"), "model header is still emitted")
        XCTAssertFalse(content.contains("[Generated image:"), "no placeholder line without a fileRef")
    }

    // MARK: - Header / fallback behaviour

    func testNullModelDisplay_fallsBackToRawIdAndGenericProviderWording() throws {
        let json = """
            {
              "model": "some-future-model-v2",
              "messages": [
                {"role":"user","createdAt":"2026-05-15T14:00:00.000Z","content":"hi"},
                {"role":"assistant","content":"hello"}
              ]
            }
            """

        let result = try exporter.export(rawJson: Data(json.utf8), chatType: .discussion)

        guard case .text(let content) = result else {
            XCTFail("Expected `.text`, got \(result)"); return
        }
        XCTAssertTrue(content.contains("using the some-future-model-v2 Model"), "header uses raw id")
        XCTAssertTrue(content.contains("some-future-model-v2:"), "per-turn label uses raw id")
    }

    func testEmptyMessagesArray_yieldsHeaderAndSeparatorOnly() throws {
        let json = #"{"model":"gpt-5-mini","messages":[]}"#

        let result = try exporter.export(rawJson: Data(json.utf8), chatType: .discussion, modelDisplay: gpt5MiniDisplay)

        guard case .text(let content) = result else {
            XCTFail("Expected `.text`, got \(result)"); return
        }
        XCTAssertTrue(content.hasPrefix("This conversation was generated"))
        XCTAssertTrue(content.hasSuffix("===================="))
    }

    // MARK: - Fixtures

    private static let specChatJSON = Data(
        """
        {
          "title" : "cat name",
          "model" : "gpt-5-mini",
          "messages" : [ {
            "createdAt" : "2026-05-15T14:23:15.150Z",
            "content" : "cat",
            "role" : "user",
            "messageId" : "26030492-4a59-47f9-b860-80e8716e9d4a",
            "generationTimestamp" : 1778854995150
          }, {
            "role" : "assistant",
            "createdAt" : "2026-05-15T14:23:15.244Z",
            "content" : "",
            "parts" : [ {
              "type" : "reasoning",
              "id" : "rs_abc",
              "state" : "done",
              "summaryText" : [ ],
              "encryptedText" : "redacted"
            }, {
              "type" : "text",
              "text" : "Do you want a picture, facts, care tips, behavior explanation, name ideas, or something else about cats?"
            } ],
            "status" : "active",
            "model" : "gpt-5-mini",
            "origin" : "text"
          } ],
          "chatId" : "52386ba8-7a9d-4307-950e-05cd7d74917a",
          "lastEdit" : "2026-05-15T14:23:16.313Z",
          "lastEditType" : "user",
          "pinned" : true,
          "pendingSync" : true
        }
        """.utf8
    )

    private static let twoTurnJSON = Data(
        """
        {
          "model": "gpt-5-mini",
          "messages": [
            {"role":"user","createdAt":"2026-05-15T14:00:00.000Z","content":"hi"},
            {"role":"assistant","createdAt":"2026-05-15T14:00:01.000Z","content":"","parts":[{"type":"text","text":"Hello!"}]},
            {"role":"user","createdAt":"2026-05-15T14:01:00.000Z","content":"bye"},
            {"role":"assistant","createdAt":"2026-05-15T14:01:01.000Z","content":"","parts":[{"type":"text","text":"Goodbye!"}]}
          ]
        }
        """.utf8
    )
}

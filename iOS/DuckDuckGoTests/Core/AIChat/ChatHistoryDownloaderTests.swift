//
//  ChatHistoryDownloaderTests.swift
//  DuckDuckGo
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
import AIChat
@testable import DuckDuckGo

@MainActor
final class ChatHistoryDownloaderTests: XCTestCase {

    // MARK: - Error paths

    func testDownload_throwsStorageUnavailable_whenStorageHandlerIsNil() async throws {
        let writer = SpyChatExportWriter()
        let downloader = ChatHistoryDownloader(storageHandler: nil, writer: writer)

        XCTAssertThrowsError(try downloader.downloadChat(chatId: "anything")) { error in
            XCTAssertEqual(error as? ChatHistoryDownloader.DownloadError, .storageUnavailable)
        }
        XCTAssertEqual(writer.writtenPayloads.count, 0)
    }

    func testDownload_throwsChatNotFound_whenChatIdIsAbsent() async throws {
        let storage = DuckAiNativeMemoryStorageHandler()
        let writer = SpyChatExportWriter()
        let downloader = ChatHistoryDownloader(storageHandler: storage, writer: writer)

        XCTAssertThrowsError(try downloader.downloadChat(chatId: "missing")) { error in
            XCTAssertEqual(error as? ChatHistoryDownloader.DownloadError, .chatNotFound)
        }
    }

    func testDownload_throwsFileDecodeFailed_whenImageStorageDataIsNotFEParamsJSON() async throws {
        let storage = DuckAiNativeMemoryStorageHandler()
        try storage.putChat(chatId: "c1", data: Self.imageGenChatJSON(fileRefs: [Self.imageUUID]))
        // Put raw bytes (not the FE's `{ "data": "<base64>", ... }` wrapper) so the unwrap fails.
        try storage.putFile(uuid: Self.imageUUID, chatId: "c1", data: Data([0xFF, 0xD8, 0xFF, 0xE0]))

        let writer = SpyChatExportWriter()
        let downloader = ChatHistoryDownloader(storageHandler: storage, writer: writer)

        XCTAssertThrowsError(try downloader.downloadChat(chatId: "c1")) { error in
            guard case .fileDecodeFailed(let uuid) = error as? ChatHistoryDownloader.DownloadError else {
                XCTFail("Expected .fileDecodeFailed, got \(error)"); return
            }
            XCTAssertEqual(uuid, Self.imageUUID)
        }
        XCTAssertEqual(writer.writtenPayloads.count, 0)
    }

    // MARK: - Success paths

    func testDownload_discussionChat_handsTextPayloadToWriter() async throws {
        let storage = DuckAiNativeMemoryStorageHandler()
        let json = """
            {
              "chatId":"c1",
              "model":"gpt-5-mini",
              "messages":[
                {"role":"user","createdAt":"2026-05-15T14:00:00.000Z","content":"hi"},
                {"role":"assistant","content":"hello"}
              ]
            }
            """
        try storage.putChat(chatId: "c1", data: Data(json.utf8))

        let writer = SpyChatExportWriter()
        let downloader = ChatHistoryDownloader(storageHandler: storage, writer: writer)

        _ = try downloader.downloadChat(chatId: "c1")

        XCTAssertEqual(writer.writtenPayloads.count, 1)
        guard case .text(let content) = writer.writtenPayloads[0] else {
            XCTFail("Expected `.text` payload, got \(writer.writtenPayloads[0])"); return
        }
        XCTAssertTrue(content.contains("User prompt 1 of 1"))
        XCTAssertTrue(content.contains("hello"))
    }

    func testDownload_imageGenerationChat_unwrapsFEPayloadAndPassesImageBytesToWriter() async throws {
        let storage = DuckAiNativeMemoryStorageHandler()
        try storage.putChat(chatId: "c1", data: Self.imageGenChatJSON(fileRefs: [Self.imageUUID]))
        // The FE wraps file content as a JSON dict with a base64 `data` field. Three
        // JPEG-magic bytes (FF D8 FF) round-tripped through the FE wrapper become the
        // payload the storage layer holds.
        let imageBytes = Data([0xFF, 0xD8, 0xFF, 0xE0])
        let wrapper: [String: Any] = [
            "uuid": Self.imageUUID,
            "chatId": "c1",
            "mimeType": "image/jpeg",
            "data": imageBytes.base64EncodedString()
        ]
        let wrapped = try JSONSerialization.data(withJSONObject: wrapper)
        try storage.putFile(uuid: Self.imageUUID, chatId: "c1", data: wrapped)

        let writer = SpyChatExportWriter()
        let downloader = ChatHistoryDownloader(storageHandler: storage, writer: writer)

        _ = try downloader.downloadChat(chatId: "c1")

        XCTAssertEqual(writer.writtenPayloads.count, 1)
        guard case .zip(let content, let images) = writer.writtenPayloads[0] else {
            XCTFail("Expected `.zip` payload, got \(writer.writtenPayloads[0])"); return
        }
        XCTAssertTrue(content.contains("[Generated image: image-1.jpeg]"),
                      "exporter emitted the image placeholder")
        XCTAssertEqual(images.count, 1)
        XCTAssertEqual(images[0].name, "image-1.jpeg")
        XCTAssertEqual(images[0].bytes, imageBytes,
                       "downloader unwrapped the FE JSON + base64-decoded back to the raw bytes")
    }

    func testDownload_acceptsDataURLPrefixedBase64ForImageBytes() async throws {
        // Some FE shapes use `data:image/jpeg;base64,...` instead of bare base64; both work.
        let storage = DuckAiNativeMemoryStorageHandler()
        try storage.putChat(chatId: "c1", data: Self.imageGenChatJSON(fileRefs: [Self.imageUUID]))
        let imageBytes = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x10, 0x20])
        let wrapper: [String: Any] = [
            "data": "data:image/jpeg;base64,\(imageBytes.base64EncodedString())"
        ]
        let wrapped = try JSONSerialization.data(withJSONObject: wrapper)
        try storage.putFile(uuid: Self.imageUUID, chatId: "c1", data: wrapped)

        let writer = SpyChatExportWriter()
        let downloader = ChatHistoryDownloader(storageHandler: storage, writer: writer)

        _ = try downloader.downloadChat(chatId: "c1")

        guard case .zip(_, let images) = writer.writtenPayloads.first else {
            XCTFail("Expected `.zip` payload"); return
        }
        XCTAssertEqual(images.first?.bytes, imageBytes)
    }

    // MARK: - Model display resolution

    func testDownload_resolvesModelDisplayFromSnapshot_andPassesToExporter() async throws {
        let storage = DuckAiNativeMemoryStorageHandler()
        let json = """
            {
              "chatId":"c1",
              "model":"gpt-5-mini",
              "messages":[
                {"role":"user","createdAt":"2026-05-15T14:00:00.000Z","content":"hi"},
                {"role":"assistant","content":"hello"}
              ]
            }
            """
        try storage.putChat(chatId: "c1", data: Data(json.utf8))

        let writer = SpyChatExportWriter()
        let downloader = ChatHistoryDownloader(
            storageHandler: storage,
            writer: writer,
            modelDisplays: [
                "gpt-5-mini": ModelDisplay(
                    fullName: "GPT-5 mini",
                    shortName: "GPT-5 mini",
                    providerPossessive: "OpenAI's"
                )
            ]
        )

        _ = try downloader.downloadChat(chatId: "c1")

        guard case .text(let content) = writer.writtenPayloads.first else {
            XCTFail("Expected `.text` payload"); return
        }
        XCTAssertTrue(content.contains("using OpenAI's GPT-5 mini Model"),
                      "header should render the resolved ModelDisplay, not the raw id")
        XCTAssertFalse(content.contains("the gpt-5-mini Model"),
                       "header should NOT fall back to the raw id when a ModelDisplay is supplied")
    }

    func testDownload_fallsBackToRawId_whenSnapshotHasNoEntryForModel() async throws {
        let storage = DuckAiNativeMemoryStorageHandler()
        let json = """
            {
              "chatId":"c1",
              "model":"gpt-5-mini",
              "messages":[
                {"role":"user","createdAt":"2026-05-15T14:00:00.000Z","content":"hi"},
                {"role":"assistant","content":"hello"}
              ]
            }
            """
        try storage.putChat(chatId: "c1", data: Data(json.utf8))

        let writer = SpyChatExportWriter()
        // Snapshot is empty (e.g. UTI off) — exporter must produce a usable header without
        // provider attribution.
        let downloader = ChatHistoryDownloader(storageHandler: storage, writer: writer)

        _ = try downloader.downloadChat(chatId: "c1")

        guard case .text(let content) = writer.writtenPayloads.first else {
            XCTFail("Expected `.text` payload"); return
        }
        XCTAssertTrue(content.contains("using the gpt-5-mini Model"),
                      "header should fall back to the raw model id when no ModelDisplay is available")
    }

    // MARK: - Fixtures

    /// Memory storage validates UUIDs strictly via `UUID(uuidString:)`. Reuse a single
    /// well-formed UUID across the image-gen tests so the fileRefs in the chat JSON match
    /// the file we put into storage.
    private static let imageUUID = "11111111-2222-3333-4444-555555555555"

    private static func imageGenChatJSON(fileRefs: [String]) -> Data {
        let fileRefsString = fileRefs.map { "\"\($0)\"" }.joined(separator: ",")
        let json = """
            {
              "chatId":"c1",
              "model":"gpt-5-mini",
              "fileRefs":[\(fileRefsString)],
              "messages":[
                {"role":"user","createdAt":"2026-05-15T14:00:00.000Z","content":"draw a duck"},
                {"role":"assistant","content":"","parts":[
                  {"type":"ui-component","name":"generate-image"}
                ]}
              ]
            }
            """
        return Data(json.utf8)
    }
}

// MARK: - Spy writer

/// Captures the payloads handed to `ChatExportWriting` so tests can assert what the
/// downloader produced without doing any actual file I/O.
@MainActor
private final class SpyChatExportWriter: ChatExportWriting {
    private(set) var writtenPayloads: [ChatExportPayload] = []
    var stubbedURL = URL(fileURLWithPath: "/tmp/duck.ai-test.txt")

    func write(_ payload: ChatExportPayload) throws -> URL {
        writtenPayloads.append(payload)
        return stubbedURL
    }
}

//
//  ChatHistoryDownloader.swift
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

import AIChat
import Foundation

/// Orchestrates a chat export: pulls the raw chat record from native storage, runs the
/// pure `ChatExporter`, gathers any image bytes referenced by image-generation chats, and
/// hands the resulting payload to the file writer. Mirrors Android's
/// `ChatHistoryRepository.exportChat` flow.
@MainActor
protocol ChatHistoryDownloading {
    /// Export the chat identified by `chatId` to the Downloads directory. Returns the
    /// URL of the written file on success; throws on storage / format / I/O failure.
    func downloadChat(chatId: String) throws -> URL
}

@MainActor
struct ChatHistoryDownloader: ChatHistoryDownloading {

    enum DownloadError: Error {
        /// Native storage failed to configure at launch, so we can't fetch the chat record.
        case storageUnavailable
        /// The chatId was not present in storage by the time the download fired (deleted
        /// between gesture start and commit, or a race with a sync wipe).
        case chatNotFound
        /// An image referenced by an image-generation chat was missing from the file store.
        case fileNotFound(uuid: String)
    }

    private let storageHandler: DuckAiNativeStorageHandling?
    private let exporter: ChatExporter
    private let writer: ChatExportWriting

    init(
        storageHandler: DuckAiNativeStorageHandling?,
        exporter: ChatExporter = ChatExporter(),
        writer: ChatExportWriting = ChatExportWriter()
    ) {
        self.storageHandler = storageHandler
        self.exporter = exporter
        self.writer = writer
    }

    func downloadChat(chatId: String) throws -> URL {
        guard let storageHandler else { throw DownloadError.storageUnavailable }
        guard let record = try storageHandler.getChat(chatId: chatId) else {
            throw DownloadError.chatNotFound
        }
        // Decode to derive model + fileRefs + chatType; the exporter still consumes the
        // raw JSON for content rendering so we don't double-encode.
        let chat = try DuckAiChat.decode(from: record.data).chat
        // ModelDisplay resolution (model id → "OpenAI's GPT-4o Model" attribution) needs
        // a network round-trip via `AIChatModelsService`; the exporter's `rawIdFallback`
        // keeps the export header useful in the meantime. Resolve as a follow-up.
        let result = try exporter.export(
            rawJson: record.data,
            chatType: chat.chatType,
            fileRefs: chat.fileRefs,
            modelDisplay: nil
        )

        let payload: ChatExportPayload
        switch result {
        case .text(let content):
            payload = .text(content)
        case .zip(let content, let imageFileRefs):
            var images: [ChatExportPayload.Image] = []
            for (index, uuid) in imageFileRefs.enumerated() {
                guard let file = try storageHandler.getFile(uuid: uuid) else {
                    throw DownloadError.fileNotFound(uuid: uuid)
                }
                images.append(.init(name: "image-\(index + 1).jpeg", bytes: file.data))
            }
            payload = .zip(content: content, images: images)
        }

        return try writer.write(payload)
    }
}

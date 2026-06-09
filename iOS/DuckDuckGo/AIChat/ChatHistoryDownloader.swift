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
protocol ChatHistoryDownloading {
    /// Export the chat identified by `chatId` to the Downloads directory. Returns the
    /// URL of the written file on success; throws on storage / format / I/O failure.
    ///
    /// Implementations may do meaningful I/O — native-storage reads, base64 image decoding,
    /// zip writing. Callers should invoke off the main thread for image-generation chats so
    /// the UI doesn't freeze during the export.
    func downloadChat(chatId: String) throws -> URL
}

struct ChatHistoryDownloader: ChatHistoryDownloading {

    enum DownloadError: Error, Equatable {
        /// Native storage failed to configure at launch, so we can't fetch the chat record.
        case storageUnavailable
        /// The chatId was not present in storage by the time the download fired (deleted
        /// between gesture start and commit, or a race with a sync wipe).
        case chatNotFound
        /// An image referenced by an image-generation chat was missing from the file store.
        case fileNotFound(uuid: String)
        /// The stored file payload couldn't be decoded into raw image bytes (the FE
        /// wraps each file as a JSON params dict with a base64-encoded `data` field; this
        /// fires when that shape isn't what we got back).
        case fileDecodeFailed(uuid: String)
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
                guard let bytes = Self.decodeImageBytes(from: file.data) else {
                    throw DownloadError.fileDecodeFailed(uuid: uuid)
                }
                images.append(.init(name: "image-\(index + 1).jpeg", bytes: bytes))
            }
            payload = .zip(content: content, images: images)
        }

        return try writer.write(payload)
    }

    /// The FE-stored file payload is a JSON params dict (see `DuckAiNativeStorageUserScript`),
    /// where the actual bytes live in `data` as a base64 string — sometimes prefixed with a
    /// `data:image/jpeg;base64,` URL header. Strip the header (if present) and base64-decode
    /// to recover the raw image bytes.
    private static func decodeImageBytes(from storedData: Data) -> Data? {
        guard let dict = try? JSONSerialization.jsonObject(with: storedData) as? [String: Any],
              let dataString = dict["data"] as? String else {
            return nil
        }
        let base64 = dataString.split(separator: ",", maxSplits: 1).last.map(String.init) ?? dataString
        return Data(base64Encoded: base64)
    }
}

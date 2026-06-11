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

/// Call off the main thread — image-generation exports do storage reads, base64 decoding,
/// and zip writing.
protocol ChatHistoryDownloading {
    func downloadChat(chatId: String) throws -> URL
}

struct ChatHistoryDownloader: ChatHistoryDownloading {

    enum DownloadError: Error, Equatable {
        case storageUnavailable
        case chatNotFound
        case fileNotFound(uuid: String)
        /// FE wraps each file as a JSON params dict with a base64 `data` field; fires when
        /// that shape isn't what we got back.
        case fileDecodeFailed(uuid: String)
    }

    private let storageHandler: DuckAiNativeStorageHandling?
    private let exporter: ChatExporter
    private let writer: ChatExportWriting
    /// Snapshot lookup taken at construction time. The exporter's `rawIdFallback` kicks in
    /// for any model id that's not in this dict, so an empty dict still produces a usable
    /// header — just without provider attribution.
    private let modelDisplays: [String: ModelDisplay]

    init(
        storageHandler: DuckAiNativeStorageHandling?,
        exporter: ChatExporter = ChatExporter(),
        writer: ChatExportWriting = ChatExportWriter(),
        modelDisplays: [String: ModelDisplay] = [:]
    ) {
        self.storageHandler = storageHandler
        self.exporter = exporter
        self.writer = writer
        self.modelDisplays = modelDisplays
    }

    func downloadChat(chatId: String) throws -> URL {
        guard let storageHandler else { throw DownloadError.storageUnavailable }
        guard let record = try storageHandler.getChat(chatId: chatId) else {
            throw DownloadError.chatNotFound
        }
        // We decode to derive metadata (chatType, fileRefs) but hand the raw JSON to the
        // exporter — no double-encoding.
        let chat = try DuckAiChat.decode(from: record.data).chat
        let result = try exporter.export(
            rawJson: record.data,
            chatType: chat.chatType,
            fileRefs: chat.fileRefs,
            modelDisplay: modelDisplays[chat.model]
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

    /// Unwraps the FE's `{ "data": "<base64>", ... }` storage payload to recover raw image
    /// bytes. Accepts both bare base64 and `data:image/jpeg;base64,…` URL-prefixed forms.
    private static func decodeImageBytes(from storedData: Data) -> Data? {
        guard let dict = try? JSONSerialization.jsonObject(with: storedData) as? [String: Any],
              let dataString = dict["data"] as? String else {
            return nil
        }
        // `omittingEmptySubsequences: false` keeps a trailing comma from producing an empty
        // last element we'd then try to base64-decode.
        let base64 = dataString.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false).last.map(String.init) ?? dataString
        return Data(base64Encoded: base64)
    }
}

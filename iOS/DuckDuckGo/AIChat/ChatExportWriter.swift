//
//  ChatExportWriter.swift
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

import Foundation
import ZIPFoundation

/// Writes a chat export to the app's Downloads directory as
/// `duck.ai_yyyy-MM-dd_HH-mm-ss.<txt|zip>`. The Downloads list view reads files straight
/// from this directory — no separate registration needed.
protocol ChatExportWriting {
    func write(_ payload: ChatExportPayload) throws -> URL
}

enum ChatExportPayload {
    case text(String)
    case zip(content: String, images: [Image])

    struct Image {
        let name: String
        let bytes: Data
    }
}

struct ChatExportWriter: ChatExportWriting {

    private let directoryHandler: DownloadsDirectoryHandling
    private let clock: () -> Date

    init(
        directoryHandler: DownloadsDirectoryHandling = DownloadsDirectoryHandler(),
        clock: @escaping () -> Date = Date.init
    ) {
        self.directoryHandler = directoryHandler
        self.clock = clock
    }

    func write(_ payload: ChatExportPayload) throws -> URL {
        directoryHandler.createDownloadsDirectoryIfNeeded()
        switch payload {
        case .text(let content):
            return try writeText(content)
        case .zip(let content, let images):
            return try writeZip(content: content, images: images)
        }
    }

    // MARK: - Text

    private func writeText(_ content: String) throws -> URL {
        let url = resolveAvailableFile(extension: Constants.txtExtension)
        // `Data(content.utf8)` is infallible; `data(using:)?.write` could silently no-op.
        try Data(content.utf8).write(to: url, options: .atomic)
        return url
    }

    // MARK: - Zip

    private func writeZip(content: String, images: [ChatExportPayload.Image]) throws -> URL {
        let url = resolveAvailableFile(extension: Constants.zipExtension)
        let archive = try Archive(url: url, accessMode: .create)

        // UTF-8 BOM prefix so `chat.txt` opens cleanly in Windows Notepad.
        let textBytes = Constants.utf8BOM + Data(content.utf8)
        try archive.addEntry(
            with: Constants.zipTextEntryName,
            type: .file,
            uncompressedSize: Int64(textBytes.count),
            provider: { position, size in
                let start = Int(position)
                let end = min(start + size, textBytes.count)
                return textBytes.subdata(in: start..<end)
            }
        )

        // `addEntry(with:fileURL:)` via a temp file is more reliable than the closure
        // provider variant for image bytes — getting the last short chunk right in the
        // provider was producing JPEGs that wouldn't decode.
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("chat-history-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        for image in images {
            let tempURL = tempDir.appendingPathComponent(image.name)
            try image.bytes.write(to: tempURL, options: .atomic)
            try archive.addEntry(with: image.name, fileURL: tempURL)
        }

        return url
    }

    // MARK: - Filename

    private func resolveAvailableFile(extension fileExtension: String) -> URL {
        let dir = directoryHandler.downloadsDirectory
        let baseName = "duck.ai_\(formattedTimestamp())"
        let initial = dir.appendingPathComponent("\(baseName).\(fileExtension)")
        if !FileManager.default.fileExists(atPath: initial.path) {
            return initial
        }
        var count = 1
        while true {
            let candidate = dir.appendingPathComponent("\(baseName)-\(count).\(fileExtension)")
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            count += 1
        }
    }

    private func formattedTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter.string(from: clock())
    }

    // MARK: - Constants

    private enum Constants {
        static let txtExtension = "txt"
        static let zipExtension = "zip"
        static let zipTextEntryName = "chat.txt"
        static let utf8BOM = Data([0xEF, 0xBB, 0xBF])
    }
}

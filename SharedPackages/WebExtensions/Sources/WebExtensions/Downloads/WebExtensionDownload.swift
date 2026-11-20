//
//  WebExtensionDownload.swift
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

#if os(macOS)

import CoreServices
import Foundation

/// The download subset used by extension attachments. No URLs are fetched by the browser.
struct WebExtensionDownload {
    static let maximumByteCount = 16 * 1024 * 1024
    private static let maximumHeaderLength = 128
    // Base64 uses four characters for each group of up to three bytes.
    static let maximumURLLength = maximumHeaderLength + 4 * ((maximumByteCount + 2) / 3)
    let filename: String
    private let encodedData: Substring

    init?(options: Any) {
        guard let options = options as? [String: Any],
              options.count == 2,
              let url = options["url"] as? String,
              let filename = options["filename"] as? String else { return nil }

        guard Self.isSafeFilename(filename), let encodedData = Self.base64Payload(in: url) else { return nil }
        self.filename = filename
        self.encodedData = encodedData
    }

    private static func base64Payload(in url: String) -> Substring? {
        guard url.utf8.count <= maximumURLLength,
              let comma = url.prefix(maximumHeaderLength).firstIndex(of: ",") else { return nil }

        let header = url[..<comma]
        let scheme = "data:"
        let encoding = ";base64"
        guard header.hasPrefix(scheme), header.hasSuffix(encoding) else { return nil }

        // The optional media type allows visible ASCII and no additional parameters.
        let mediaType = header.dropFirst(scheme.count).dropLast(encoding.count)
        guard mediaType.unicodeScalars.allSatisfy({ ("!"..."~").contains($0) && $0 != ";" }) else { return nil }

        return url[url.index(after: comma)...]
    }

    private static func isSafeFilename(_ name: String) -> Bool {
        guard !name.isEmpty, name.utf8.count <= 255, !name.hasPrefix("."), !name.hasSuffix("."),
              name == name.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        let disallowed = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/\\:"))
            .union(.newlines).union(.illegalCharacters)
        return name.rangeOfCharacter(from: disallowed) == nil
    }

    func decode() throws -> Data {
        guard let data = Data(base64Encoded: String(encodedData)), data.count <= Self.maximumByteCount else {
            throw DownloadError.invalid
        }
        return data
    }

    enum DownloadError: Error {
        case invalid, saveFailed, fileExists
    }

    /// Prepare the complete, quarantined file on the destination volume. Its final name is
    /// published only after the caller rechecks consent, without following or replacing a collision.
    struct StagedFile {
        let directory: URL
        private var file: URL { directory.appendingPathComponent("attachment") }

        init(data: Data, destination: URL) throws {
            directory = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                                     appropriateFor: destination, create: true)
            do {
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
                try data.write(to: file, options: .withoutOverwriting)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
                try (file as NSURL).setResourceValue([kLSQuarantineTypeKey as String: kLSQuarantineTypeOtherDownload],
                                                      forKey: .quarantinePropertiesKey)
                guard try file.resourceValues(forKeys: [.quarantinePropertiesKey]).quarantineProperties != nil else {
                    throw DownloadError.saveFailed
                }
            } catch {
                cleanUp()
                throw error
            }
        }

        func publish(to destination: URL) throws {
            guard renamex_np(file.path, destination.path, UInt32(RENAME_EXCL)) == 0 else {
                throw errno == EEXIST ? DownloadError.fileExists : DownloadError.saveFailed
            }
        }

        func cleanUp() {
            try? FileManager.default.removeItem(at: directory)
        }
    }
}

#endif

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
import FoundationExtensions

/// Local attachment URLs supported by the macOS downloads bridge.
struct WebExtensionDownload: Sendable {
    // v8::String::kMaxLength on 64-bit Chrome, in UTF-16 code units. Blob contents never enter this string.
    static let maximumDataURLLength = (1 << 29) - 24
    let filename: String
    private let urlString: String

    init?(options: Any, extensionBaseURL: URL) {
        guard let options = options as? [String: Any],
              options.count == 2,
              let url = options["url"] as? String,
              let filename = options["filename"] as? String else { return nil }

        guard Self.isSafeFilename(filename), Self.isAttachmentURL(url, for: extensionBaseURL) else { return nil }
        self.filename = filename
        self.urlString = url
    }

    private static func isAttachmentURL(_ string: String, for baseURL: URL) -> Bool {
        if string.prefix(5).lowercased() == "data:" {
            return string.utf16.count <= maximumDataURLLength &&
                string.utf8.first { $0 == UInt8(ascii: ",") || $0 == UInt8(ascii: "#") } == UInt8(ascii: ",")
        }
        // WebKit creates object URLs as blob:<serialized origin>/<UUID>. Require the entire origin,
        // including the trailing slash, before letting the originating web view resolve the reference.
        let prefix = "blob:" + baseURL.absoluteString
        guard let origin = string.range(of: prefix, options: [.anchored, .caseInsensitive]) else { return false }
        let objectID = string[origin.upperBound...].prefix { $0 != "#" }
        return objectID.utf8.count == 36 && UUID(uuidString: String(objectID)) != nil
    }

    /// WebKit's native downloader includes literal fragments and requires padded base64.
    /// Chromium omits the fragment and accepts forgiving base64. Keep escaped %23 as file data.
    func makeDownloadURL() -> URL? {
        let resource = urlString.utf8.firstIndex(of: UInt8(ascii: "#")).map { String(urlString[..<$0]) } ?? urlString
        guard resource.prefix(5).lowercased() == "data:",
              let comma = resource.utf8.firstIndex(of: UInt8(ascii: ",")) else { return URL(string: resource) }
        let header = resource[..<comma]
        let payload = resource[resource.utf8.index(after: comma)...]
        guard let separator = header.lastIndex(of: ";"),
              header[header.index(after: separator)...].trimmingCharacters(in: Self.headerWhitespace).lowercased() == "base64"
        else {
            // Only a final base64 marker changes the file bytes in Chrome. WebKit also honors earlier markers.
            // The payload may mix %HH escapes with literal UTF-8. Preserve the escapes when constructing the URL.
            var dataURL = Data("data:,".utf8)
            dataURL.append(contentsOf: payload.utf8)
            return URL(dataRepresentation: dataURL, relativeTo: nil)
        }

        guard let normalized = Self.normalizedBase64(payload) else { return nil }
        return URL(string: "data:;base64," + normalized)
    }

    private static let headerWhitespace = CharacterSet(charactersIn: " \t\n\u{000B}\u{000C}\r")
    private static let base64Whitespace: Set<UInt8> = [9, 10, 12, 13, 32]
    private static let invalidBase64 = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/").inverted

    private static func normalizedBase64(_ payload: Substring) -> Substring? {
        var compact = payload
        if payload.utf8.contains(where: { $0 == UInt8(ascii: "%") || $0 <= UInt8(ascii: " ") }) {
            guard let unescaped = payload.removingPercentEncoding,
                  let stripped = String(bytes: unescaped.utf8.filter { !base64Whitespace.contains($0) }, encoding: .utf8) else { return nil }
            compact = stripped[...]
        }
        let firstPadding = compact.utf8.firstIndex(of: UInt8(ascii: "=")) ?? compact.endIndex
        let body = compact[..<firstPadding]
        guard body.rangeOfCharacter(from: invalidBase64) == nil else { return nil }
        let required = (4 - body.utf8.count % 4) % 4
        guard required <= 2 else { return nil }
        let suffix = compact[firstPadding...]
        if suffix.isEmpty {
            return required == 0 ? compact : (compact + String(repeating: "=", count: required))[...]
        }
        guard suffix.utf8.count == required, suffix.utf8.allSatisfy({ $0 == UInt8(ascii: "=") }) else { return nil }
        return compact
    }

    private static func isSafeFilename(_ name: String) -> Bool {
        guard name.utf8.count <= 255 else { return false }
        // Join controls shape text and emoji. Ignore them during validation so they cannot mask an unsafe name.
        let nameWithoutJoiners = String(name.unicodeScalars.filter { !$0.properties.isJoinControl })
        guard !nameWithoutJoiners.isEmpty, !nameWithoutJoiners.hasPrefix("."), !nameWithoutJoiners.hasSuffix("."),
              nameWithoutJoiners == nameWithoutJoiners.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        let disallowed = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/\\:"))
            .union(.newlines).union(.illegalCharacters)
        return nameWithoutJoiners.rangeOfCharacter(from: disallowed) == nil
    }

    enum DownloadError: Error {
        case invalid, canceled, saveFailed, fileExists
    }

    /// Prepare the complete, quarantined file on the destination volume. Its final name is
    /// published only after the caller rechecks consent, without following or replacing a collision.
    struct StagedFile: Sendable {
        private let directory: URL
        var file: URL { directory.appendingPathComponent("attachment") }

        init(destination: URL) throws {
            directory = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                                     appropriateFor: destination, create: true)
            do {
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            } catch {
                cleanUp()
                throw error
            }
        }

        func prepareForPublication() throws {
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            // A data URL contains the attachment itself. Never publish source URLs as file metadata.
            guard removexattr(file.path, "com.apple.metadata:kMDItemWhereFroms", XATTR_NOFOLLOW) == 0 || errno == ENOATTR else {
                throw DownloadError.saveFailed
            }
            try (file as NSURL).setResourceValue([kLSQuarantineTypeKey as String: kLSQuarantineTypeOtherDownload],
                                                 forKey: .quarantinePropertiesKey)
            guard let quarantine = try file.resourceValues(forKeys: [.quarantinePropertiesKey]).quarantineProperties,
                  quarantine[kLSQuarantineDataURLKey as String] == nil,
                  quarantine[kLSQuarantineOriginURLKey as String] == nil else { throw DownloadError.saveFailed }
        }

        @discardableResult
        func publish(to destination: URL, uniquify: Bool = false) throws -> URL {
            func publishExclusively(at url: URL) throws -> URL {
                guard renamex_np(file.path, url.path, UInt32(RENAME_EXCL)) == 0 else {
                    throw errno == EEXIST ? DownloadError.fileExists : DownloadError.saveFailed
                }
                return url
            }

            guard uniquify else { return try publishExclusively(at: destination) }
            return try FileManager.default.withNonExistentUrl(for: destination, incrementingIndexIfExistsUpTo: 10000,
                                                              continueOn: { ($0 as? DownloadError) == .fileExists },
                                                              perform: publishExclusively)
        }

        func cleanUp() {
            try? FileManager.default.removeItem(at: directory)
        }
    }
}

#endif

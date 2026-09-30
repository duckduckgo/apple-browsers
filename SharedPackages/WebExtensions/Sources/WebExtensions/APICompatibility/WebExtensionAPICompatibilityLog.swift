//
//  WebExtensionAPICompatibilityLog.swift
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
import os.log

/// How a web extension ran into a `chrome.*` API WebKit does not fully support.
public enum WebExtensionAPICompatibilityKind: String, CaseIterable, Sendable {
    /// The extension used an API that is not available.
    case missing
    /// The extension called one of our no-op stubs.
    case stubbed
    /// WebKit implements the API but rejected the call ("Invalid call to X()").
    case invalidArgs
}

/// The API compatibility log: which unsupported `chrome.*` APIs the loaded extensions touched.
///
/// A line holds the kind, the API path and the extension's name and version, nothing else. No URL,
/// error message or call argument ever reaches the log. The Debug Menu reads the lines back from
/// the current process's log store.
public enum WebExtensionAPICompatibilityLog {

    public static let subsystem = "WebExtensions"
    public static let category = "APICompatibility"

    static let logger = Logger(subsystem: subsystem, category: category)

    /// Makes an extension's name or version safe to put on a single log line.
    static func sanitizedField(_ value: String?) -> String {
        let cleaned = String(String.UnicodeScalarView((value ?? "").unicodeScalars.map {
            CharacterSet.controlCharacters.contains($0) ? " " : $0
        })).trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "unknown" : String(cleaned.prefix(80))
    }

    /// `<kind> <api> ext=<name> v=<version>`
    static func line(kind: WebExtensionAPICompatibilityKind,
                     api: String,
                     extensionName: String,
                     version: String) -> String {
        "\(kind.rawValue) \(api) ext=\(extensionName) v=\(version)"
    }

    public struct Entry: Equatable, Sendable {
        public let kind: WebExtensionAPICompatibilityKind
        public let api: String
        public let extensionName: String
        public let version: String

        init(kind: WebExtensionAPICompatibilityKind, api: String, extensionName: String, version: String) {
            self.kind = kind
            self.api = api
            self.extensionName = extensionName
            self.version = version
        }

        /// Parses a line written by `line(kind:api:extensionName:version:)`; `nil` for any other text.
        public init?(line: String) {
            // The name can contain spaces, so the version is taken from the end of the line.
            guard let versionRange = line.range(of: " v=", options: .backwards),
                  let nameRange = line.range(of: " ext=") else {
                return nil
            }
            let head = line[..<nameRange.lowerBound].split(separator: " ", omittingEmptySubsequences: true)
            guard head.count == 2,
                  let kind = WebExtensionAPICompatibilityKind(rawValue: String(head[0])),
                  nameRange.upperBound <= versionRange.lowerBound else {
                return nil
            }
            self.init(kind: kind,
                      api: String(head[1]),
                      extensionName: String(line[nameRange.upperBound..<versionRange.lowerBound]),
                      version: String(line[versionRange.upperBound...]))
        }
    }
}

/// Writes the first occurrence of each (extension, version, kind, API) to the log, once per launch.
final class WebExtensionAPICompatibilityReporter: @unchecked Sendable {

    static let shared = WebExtensionAPICompatibilityReporter()

    private let write: (String) -> Void
    private let lock = NSLock()
    private var reported = Set<String>()

    init(write: @escaping (String) -> Void = { line in
        WebExtensionAPICompatibilityLog.logger.notice("\(line, privacy: .public)")
    }) {
        self.write = write
    }

    func report(kind: WebExtensionAPICompatibilityKind, api: String, extensionName: String, version: String) {
        let key = "\(extensionName)|\(version)|\(kind.rawValue)|\(api)"
        lock.lock()
        let isFirst = reported.insert(key).inserted
        lock.unlock()
        guard isFirst else { return }

        write(WebExtensionAPICompatibilityLog.line(kind: kind, api: api, extensionName: extensionName, version: version))
    }
}

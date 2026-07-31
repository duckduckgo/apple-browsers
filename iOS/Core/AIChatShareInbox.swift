//
//  AIChatShareInbox.swift
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

/// Describes a set of shared items handed from the "Ask Duck.ai" action extension to the main app.
///
/// The payload is written as `manifest.json` inside a token directory in the shared app-group inbox.
/// Attachment bytes live alongside the manifest and are addressed by `Item.relativePath`.
public struct AIChatSharePayload: Codable, Equatable {

    public struct Item: Codable, Equatable {

        public enum Kind: String, Codable {
            case image
            case file
        }

        public let kind: Kind
        public let fileName: String
        public let mimeType: String
        public let relativePath: String

        public init(kind: Kind, fileName: String, mimeType: String, relativePath: String) {
            self.kind = kind
            self.fileName = fileName
            self.mimeType = mimeType
            self.relativePath = relativePath
        }
    }

    public let version: Int
    public let createdAt: Date
    public let prompt: String?
    public let items: [Item]

    public init(version: Int = 1, createdAt: Date = Date(), prompt: String?, items: [Item]) {
        self.version = version
        self.createdAt = createdAt
        self.prompt = prompt
        self.items = items
    }
}

/// Shared app-group storage used to pass Duck.ai share payloads that are too large for a deep link.
public enum AIChatShareInbox {

    private enum Constants {
        static let directoryName = "AskDuckAIInbox"
        static let manifestName = "manifest.json"
    }

    /// Largest single shared item the extension will stage and the app will read back.
    public static let maximumItemByteCount = 50 * 1024 * 1024

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// The root inbox directory inside the shared app-group container, or nil when the container is unavailable.
    public static func inboxDirectoryURL() -> URL? {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Global.appConfigurationGroupName) else {
            return nil
        }
        return container.appendingPathComponent(Constants.directoryName, isDirectory: true)
    }

    /// Creates a fresh token directory ready to receive attachment bytes and a manifest.
    public static func makePayloadDirectory() throws -> (token: String, directory: URL) {
        guard let inbox = inboxDirectoryURL() else {
            throw AIChatShareInboxError.appGroupUnavailable
        }
        let token = UUID().uuidString
        let directory = inbox.appendingPathComponent(token, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (token, directory)
    }

    public static func writeManifest(_ payload: AIChatSharePayload, to directory: URL) throws {
        let data = try encoder.encode(payload)
        try data.write(to: directory.appendingPathComponent(Constants.manifestName), options: .atomic)
    }

    /// Reads back a payload previously written by the action extension.
    public static func loadPayload(token: String) -> (payload: AIChatSharePayload, directory: URL)? {
        guard UUID(uuidString: token) != nil,
              let inbox = inboxDirectoryURL() else {
            return nil
        }
        let directory = inbox.appendingPathComponent(token, isDirectory: true)
        let manifestURL = directory.appendingPathComponent(Constants.manifestName)
        guard let data = try? Data(contentsOf: manifestURL),
              let payload = try? decoder.decode(AIChatSharePayload.self, from: data) else {
            return nil
        }
        return (payload, directory)
    }

    public static func deletePayload(token: String) {
        guard UUID(uuidString: token) != nil,
              let inbox = inboxDirectoryURL() else {
            return
        }
        try? FileManager.default.removeItem(at: inbox.appendingPathComponent(token, isDirectory: true))
    }

    /// Removes payload directories older than `age`, using the manifest date when it can be read.
    public static func collectGarbage(olderThan age: TimeInterval) {
        guard let inbox = inboxDirectoryURL() else { return }
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(at: inbox,
                                                                  includingPropertiesForKeys: [.creationDateKey, .isDirectoryKey],
                                                                  options: [.skipsHiddenFiles]) else {
            return
        }

        let cutoff = Date().addingTimeInterval(-age)
        for directory in contents {
            guard let date = payloadDate(for: directory) else { continue }
            if date < cutoff {
                try? fileManager.removeItem(at: directory)
            }
        }
    }

    private static func payloadDate(for directory: URL) -> Date? {
        let manifestURL = directory.appendingPathComponent(Constants.manifestName)
        if let data = try? Data(contentsOf: manifestURL),
           let payload = try? decoder.decode(AIChatSharePayload.self, from: data) {
            return payload.createdAt
        }
        return (try? directory.resourceValues(forKeys: [.creationDateKey]))?.creationDate
    }
}

public enum AIChatShareInboxError: Error {
    case appGroupUnavailable
}

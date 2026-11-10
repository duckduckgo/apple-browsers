//
//  ChromeWebStorePendingUpdateStore.swift
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

/// A verified ZIP archive ready for the installation flow. The receiver owns accepted files.
public struct ChromeWebStoreVerifiedUpdate: Equatable, Sendable {
    public let extensionID: String
    public let version: String
    public let fileURL: URL

    public init(extensionID: String, version: String, fileURL: URL) {
        self.extensionID = extensionID
        self.version = version
        self.fileURL = fileURL
    }
}

public protocol ChromeWebStorePendingUpdateStoring: Sendable {
    func pendingUpdate(for extensionID: String) async -> ChromeWebStoreVerifiedUpdate?
    /// Takes ownership of the file only when returning true. An older or equal version is rejected.
    func store(_ update: ChromeWebStoreVerifiedUpdate) async throws -> Bool
}

/// Retains one package per extension for this session; replacing it removes the previous archive.
@available(macOS 15.4, iOS 18.4, *)
public actor ChromeWebStorePendingUpdateStore: ChromeWebStorePendingUpdateStoring {
    private let directory: URL
    private var updates: [String: ChromeWebStoreVerifiedUpdate] = [:]

    public init(directory: URL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)) {
        self.directory = directory
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    public func pendingUpdate(for extensionID: String) -> ChromeWebStoreVerifiedUpdate? {
        guard let update = updates[extensionID] else { return nil }
        guard FileManager.default.fileExists(atPath: update.fileURL.path) else {
            updates.removeValue(forKey: extensionID)
            return nil
        }
        return update
    }

    public func store(_ update: ChromeWebStoreVerifiedUpdate) throws -> Bool {
        try Task.checkCancellation()
        if let previous = pendingUpdate(for: update.extensionID),
           !SemanticVersionComparator().isVersion(update.version, newerThan: previous.version) { return false }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let destination = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("zip")
        // Keep the old package until the replacement is fully staged.
        try FileManager.default.moveItem(at: update.fileURL, to: destination)
        let previous = updates.updateValue(.init(extensionID: update.extensionID, version: update.version, fileURL: destination),
                                           forKey: update.extensionID)
        if let previous { try? FileManager.default.removeItem(at: previous.fileURL) }
        return true
    }
}

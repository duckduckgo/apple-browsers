//
//  PIRDebugTokenStore.swift
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
import Networking

/// A file-backed ``AuthTokenStoring`` for debug tooling.
///
/// The app keeps its token container in the data-protection keychain under an access-group, which a
/// bare unsigned executable cannot read. This stores a container the caller supplies (exported from
/// a signed, logged-in app) in a plain file instead, so the CLI can hold — and refresh — its own
/// copy with no entitlements.
///
/// The file holds a **refresh token**: a credential that outlives the 4-minute access token. It is
/// written `0600` (owner read/write only) and never logged.
public final class PIRDebugTokenStore: AuthTokenStoring {

    public enum StoreError: Error, LocalizedError {
        case unreadable(URL, underlying: Error)
        case undecodable(URL)
        case unwritable(URL, underlying: Error)

        public var errorDescription: String? {
            switch self {
            case .unreadable(let url, let underlying):
                return "Could not read the stored token at \(url.path): \(underlying.localizedDescription)"
            case .undecodable(let url):
                return "The stored token at \(url.path) is not a token container; re-import it"
            case .unwritable(let url, let underlying):
                return "Could not write the token to \(url.path): \(underlying.localizedDescription)"
            }
        }
    }

    /// `~/.config/pir-debug/token.json` — the path the app's export writes and the CLI reads.
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/pir-debug/token.json")
    }

    public let url: URL

    public init(url: URL = PIRDebugTokenStore.defaultURL) {
        self.url = url
    }

    public var hasToken: Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    public func getTokenContainer() throws -> TokenContainer? {
        guard hasToken else { return nil }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw StoreError.unreadable(url, underlying: error)
        }
        guard let container = try? JSONDecoder().decode(TokenContainer.self, from: data) else {
            throw StoreError.undecodable(url)
        }
        return container
    }

    public func saveTokenContainer(_ tokenContainer: TokenContainer?) throws {
        guard let tokenContainer else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            let data = try JSONEncoder().encode(tokenContainer)
            // Create at 0600 before writing, so the token is never briefly world-readable, and
            // re-apply for a pre-existing file whose mode the caller may have loosened.
            if !FileManager.default.createFile(atPath: url.path,
                                               contents: data,
                                               attributes: [.posixPermissions: 0o600]) {
                try data.write(to: url, options: .atomic)
            }
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            throw StoreError.unwritable(url, underlying: error)
        }
    }
}

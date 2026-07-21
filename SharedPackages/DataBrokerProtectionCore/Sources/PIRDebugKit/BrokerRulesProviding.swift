//
//  BrokerRulesProviding.swift
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
import DataBrokerProtectionCore

/// A source of broker rule JSON, decoded into `DataBroker`s. Implementations never touch the
/// secure vault or keychain.
public protocol BrokerRulesProviding {
    func fetchBrokers() async throws -> [DataBroker]
}

/// A `DataBroker` decoder matching the app's runtime decode (`.millisecondsSince1970`), so that
/// `validate` / local / inline sources catch exactly what the running app would reject or accept —
/// notably `removedAt`, the only date-typed field.
func makeBrokerRulesDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .millisecondsSince1970
    return decoder
}

/// A per-file decoding failure, surfaced instead of failing a whole batch.
public struct BrokerRulesDecodingError: Error, CustomStringConvertible {
    public let fileURL: URL
    public let underlyingError: Error

    public var description: String {
        "\(fileURL.lastPathComponent): \(underlyingError.localizedDescription)"
    }
}

/// Decodes a single broker from an inline JSON string/`Data` — what the debug window's editor uses.
public struct InlineJSONBrokerRulesProvider: BrokerRulesProviding {
    private let data: Data

    public init(json: String) {
        self.data = Data(json.utf8)
    }

    public init(data: Data) {
        self.data = data
    }

    public func fetchBrokers() async throws -> [DataBroker] {
        [try makeBrokerRulesDecoder().decode(DataBroker.self, from: data)]
    }
}

/// Decodes brokers from a single `.json` file or a directory of them (e.g. a dbp-api checkout's
/// `dbp-json/data/json/`). Per-file decode errors are collected in ``errors`` rather than failing
/// the whole batch.
public final class LocalFileBrokerRulesProvider: BrokerRulesProviding {

    public let url: URL
    public private(set) var errors: [BrokerRulesDecodingError] = []

    public init(url: URL) {
        self.url = url
    }

    public func fetchBrokers() async throws -> [DataBroker] {
        errors = []

        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw PIRDebugError.unreadableRulesSource(url)
        }

        let fileURLs: [URL]
        if isDirectory.boolValue {
            let contents = try fileManager.contentsOfDirectory(at: url,
                                                               includingPropertiesForKeys: nil,
                                                               options: [.skipsHiddenFiles])
            fileURLs = contents.filter { $0.pathExtension.lowercased() == "json" }.sorted { $0.path < $1.path }
        } else {
            fileURLs = [url]
        }

        let decoder = makeBrokerRulesDecoder()
        var brokers: [DataBroker] = []
        for fileURL in fileURLs {
            do {
                let data = try Data(contentsOf: fileURL)
                brokers.append(try decoder.decode(DataBroker.self, from: data))
            } catch {
                errors.append(BrokerRulesDecodingError(fileURL: fileURL, underlyingError: error))
            }
        }
        return brokers
    }
}

//
//  AIChatLocalModelSpec.swift
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

/// The GGUF file llama.cpp runs. Remote config's `localModels` settings carry one under
/// `models.llamaCpp`.
public struct AIChatLocalModelSpec: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let bytes: Int64
    public let url: URL
    /// Lowercase hex. The file is named after it, so remote config can't choose a path.
    public let sha256: String

    public init(id: String, name: String, bytes: Int64, url: URL, sha256: String) {
        self.id = id
        self.name = name
        self.bytes = bytes
        self.url = url
        self.sha256 = sha256
    }

    public var info: AIChatLocalModelInfo {
        AIChatLocalModelInfo(id: id, name: name)
    }

    var fileName: String { "\(sha256).gguf" }

    /// IBM's Granite 4.0 1B, Q4_0, pinned to one commit of IBM's repository, used until remote
    /// config names a model.
    public static let granite = AIChatLocalModelSpec(
        id: "granite-4.0-1b",
        name: "Granite 4.0 1B",
        bytes: 974_984_960,
        url: URL(string: "https://huggingface.co/ibm-granite/granite-4.0-1b-GGUF/resolve/b27c2fe3f211b7f44e80fa620177aea371099aaa/granite-4.0-1b-Q4_0.gguf")!,
        sha256: "227e78e2fb9a3e5699190be0ce0885fd2ea72a242ed1bf718c2148c45dd090b5"
    )

    /// The model in remote config's `localModels` settings, or nil when there's none or it isn't
    /// usable: llama.cpp needs an https URL, a size and a SHA-256.
    public static func fromRemoteSettings(_ settingsJSON: String?) -> AIChatLocalModelSpec? {
        struct Settings: Decodable {
            struct Models: Decodable {
                let llamaCpp: AIChatLocalModelSpec?
            }
            let models: Models?
        }
        guard let data = settingsJSON?.data(using: .utf8),
              let spec = (try? JSONDecoder().decode(Settings.self, from: data))?.models?.llamaCpp,
              spec.url.scheme == "https",
              spec.bytes > 0,
              spec.sha256.count == 64,
              spec.sha256.allSatisfy(\.isHexDigit) else {
            return nil
        }
        return AIChatLocalModelSpec(id: spec.id, name: spec.name, bytes: spec.bytes, url: spec.url, sha256: spec.sha256.lowercased())
    }
}

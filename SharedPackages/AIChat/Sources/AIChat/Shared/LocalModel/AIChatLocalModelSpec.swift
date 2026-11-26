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

    /// Google's Gemma 4 E2B, Q4_0, pinned to one commit of ggml-org's repository, used until remote
    /// config names a model.
    public static let gemma4E2B = AIChatLocalModelSpec(
        id: "gemma-4-e2b",
        name: "Gemma 4 E2B",
        bytes: 2_841_481_184,
        url: URL(string: "https://huggingface.co/ggml-org/gemma-4-E2B-it-GGUF/resolve/2a8538c2e2d4687953a86c422c7c623cfd022880/gemma-4-E2B-it-Q4_0.gguf")!,
        sha256: "8e30dff3ac4c8434c49a7036fa15564bdbb6044e42bf04550bf1a096ad7e6a52"
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

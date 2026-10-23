//
//  ModelCatalog.swift
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
import DuckAIChatCore

/// A downloadable MLX model.
public struct Model: Identifiable, Equatable, Sendable {
    /// Hugging Face repository id.
    public let id: String
    public let displayName: String
    /// Download size as listed on Hugging Face (weights, config, tokenizer).
                                               public let approximateBytes: Int64
    public let licence: String
    /// End-of-turn markers the model's config doesn't declare as EOS.
    public let extraEOSTokens: Set<String>
    public var contextWindowTokens: Int {
        if id.contains("Qwen3.5") { return 262_144 }
        return 131_072
    }

    public enum InferenceFamily: Sendable { case language, vision }
    public var inferenceFamily: InferenceFamily {
        switch id {
        case "mlx-community/Qwen3.5-0.8B-4bit", "mlx-community/Qwen3.5-2B-4bit", "mlx-community/Qwen3.5-4B-4bit": .vision
        default: .language
        }
    }
    public var capabilities: InputCapabilities { inferenceFamily == .vision ? .vision : .textOnly }

    public var runtimeUnsupportedReason: String? {
        guard id == "mlx-community/gemma-4-e2b-it-4bit" else { return nil }
        return "Gemma 4 is unavailable with this app's current model runtime."
    }

    /// Below this much physical memory the model is too big to share the browser's budget.
    public let minimumPhysicalMemoryGB: Int
}

public enum ModelCatalog {

    public static let qwen35Mini = Model(id: "mlx-community/Qwen3.5-0.8B-4bit", displayName: "Qwen3.5 0.8B (4-bit)",
                                               approximateBytes: 650_000_000, licence: "Apache-2.0",
                                               extraEOSTokens: ["<|im_end|>"], minimumPhysicalMemoryGB: 4)
    public static let qwen35 = Model(id: "mlx-community/Qwen3.5-2B-4bit", displayName: "Qwen3.5 2B (4-bit)",
                                               approximateBytes: 1_750_000_000, licence: "Apache-2.0",
                                               extraEOSTokens: ["<|im_end|>"], minimumPhysicalMemoryGB: 6)
    public static let qwen35Large = Model(id: "mlx-community/Qwen3.5-4B-4bit", displayName: "Qwen3.5 4B (4-bit)",
                                               approximateBytes: 3_060_000_000, licence: "Apache-2.0 (upstream)",
                                               extraEOSTokens: ["<|im_end|>"], minimumPhysicalMemoryGB: 8)
    public static let gemma4E2B = Model(id: "mlx-community/gemma-4-e2b-it-4bit", displayName: "Gemma 4 E2B it (4-bit)",
                                               approximateBytes: 3_580_000_000, licence: "Gemma",
                                               extraEOSTokens: ["<turn|>"], minimumPhysicalMemoryGB: 8)
    public static let llama32Mini = Model(id: "mlx-community/Llama-3.2-1B-Instruct-4bit", displayName: "Llama 3.2 1B Instruct (4-bit)",
                                               approximateBytes: 710_000_000, licence: "Llama 3.2",
                                               extraEOSTokens: ["<|eot_id|>"], minimumPhysicalMemoryGB: 4)
    public static let llama32 = Model(id: "mlx-community/Llama-3.2-3B-Instruct-4bit", displayName: "Llama 3.2 3B Instruct (4-bit)",
                                               approximateBytes: 1_820_000_000, licence: "Llama 3.2",
                                               extraEOSTokens: ["<|eot_id|>"], minimumPhysicalMemoryGB: 6)

    // Keep unsupported downloads visible so they can still be deleted.
    public static let all: [Model] = [qwen35Mini, qwen35, qwen35Large, gemma4E2B, llama32Mini, llama32]

    public static func model(withID id: String) -> Model? {
        all.first { $0.id == id }
    }

    public static func recommended(physicalMemory: UInt64) -> Model {
        fits(qwen35, physicalMemory: physicalMemory) ? qwen35 : qwen35Mini
    }

    public static func fits(_ model: Model, physicalMemory: UInt64) -> Bool {
        nominalGigabytes(physicalMemory) >= model.minimumPhysicalMemoryGB
    }

    /// Devices report a little less than their marketed RAM (a 6 GB iPhone shows under 6 × 10⁹ bytes), so round up.
    static func nominalGigabytes(_ physicalMemory: UInt64) -> Int {
        Int((Double(physicalMemory) / 1_000_000_000).rounded(.up))
    }
}

//
//  AIChatModelLabel.swift
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

public enum AIChatModelLabel: Equatable, Sendable {
    case everydayUse
    case usesLimitsFaster
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "EVERYDAY_USE": self = .everydayUse
        case "USES_LIMITS_FASTER": self = .usesLimitsFaster
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .everydayUse: return "EVERYDAY_USE"
        case .usesLimitsFaster: return "USES_LIMITS_FASTER"
        case .unknown(let rawValue): return rawValue
        }
    }

    #if os(iOS)
    public var localizedText: String? {
        switch self {
        case .everydayUse: return UserText.modelPickerLabelEverydayUse
        case .usesLimitsFaster: return UserText.modelPickerLabelUsesLimitsFaster
        case .unknown: return nil
        }
    }
    #endif
}

extension AIChatModelLabel: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }
}

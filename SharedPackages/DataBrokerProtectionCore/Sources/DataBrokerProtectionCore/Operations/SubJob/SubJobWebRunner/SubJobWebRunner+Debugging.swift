//
//  SubJobWebRunner+Debugging.swift
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

public enum DebugEventKind: String {
    case actionPayload = "Action"
    case actionResponse = "Response"
    case actionRetry = "Retry"
    case wait = "Wait"
    case history = "History"
}

public protocol DebugEventReporting {
    func recordDebugEvent(kind: DebugEventKind, actionType: ActionType?, details: String)
}

public extension DebugEventReporting {
    func recordDebugEvent(kind: DebugEventKind, details: String) {
        recordDebugEvent(kind: kind, actionType: nil, details: details)
    }
}

public extension SubJobWebRunning {
    func recordDebugEvent(kind: DebugEventKind,
                          actionType: ActionType? = nil,
                          details: String) {
        guard let reporter = stageCalculator as? DebugEventReporting else { return }
        reporter.recordDebugEvent(kind: kind, actionType: actionType, details: details)
    }

    func errorDetails(_ error: Error) -> String {
        prettyPrintedJSON(from: [
            "type": String(describing: type(of: error)),
            "description": error.localizedDescription
        ])
    }

    func prettyPrintedJSON(from profiles: [ExtractedProfile], meta: [String: Any]?) -> String {
        let profiles = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(profiles)))

        return prettyPrintedJSON(from: [
            "profiles": profiles ?? "unknown",
            "meta": meta ?? [:]
        ])
    }

    func prettyPrintedJSON(from value: Any) -> String {
        let encoder = JSONEncoder()
        let fallback = String(describing: value)

        // Encodable
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let encodable = value as? Encodable,
           let data = try? encoder.encode(AnyEncodable(encodable)) {
            return String(data: data, encoding: .utf8) ?? fallback
        }

        // Foundation object
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]) {
            return String(data: data, encoding: .utf8) ?? fallback
        }

        return fallback
    }
}

private struct AnyEncodable: Encodable {
    private let encode: (Encoder) throws -> Void

    init<T: Encodable>(_ value: T) {
        self.encode = value.encode(to:)
    }

    func encode(to encoder: Encoder) throws {
        try encode(encoder)
    }
}

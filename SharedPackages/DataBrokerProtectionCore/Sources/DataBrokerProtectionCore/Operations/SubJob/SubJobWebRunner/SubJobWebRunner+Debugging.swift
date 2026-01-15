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
}

public protocol DebugEventReporting {
    func recordDebugEvent(kind: DebugEventKind,
                          stepType: StepType?,
                          actionType: ActionType?,
                          details: String)
}

public extension DebugEventReporting {
    func recordDebugEvent(kind: DebugEventKind,
                          stepType: StepType?,
                          actionType: ActionType? = nil,
                          details: String) {
        recordDebugEvent(kind: kind,
                         stepType: stepType,
                         actionType: actionType,
                         details: details)
    }
}

public extension SubJobWebRunning {
    func recordDebugEvent(kind: DebugEventKind,
                          stepType: StepType?,
                          actionType: ActionType? = nil,
                          details: String) {
        guard let reporter = stageCalculator as? DebugEventReporting else { return }
        reporter.recordDebugEvent(kind: kind,
                                  stepType: stepType,
                                  actionType: actionType,
                                  details: details)
    }

    func errorDetails(_ error: Error) -> String {
        guard let dbpError = error as? DataBrokerProtectionError,
              case .actionFailed(let actionID, let message) = dbpError else {
            return prettyPrintedJSON(from: [
                "type": String(describing: type(of: error)),
                "description": error.localizedDescription
            ])
        }

        return prettyPrintedJSON(from: [
            "type": dbpError.name,
            "actionId": actionID,
            "message": message,
            "description": dbpError.localizedDescription
        ])
    }

    func prettyPrintedJSON(from profiles: [ExtractedProfile], meta: [String: Any]?) -> String {
        let profilesJSON = prettyPrintedJSON(from: profiles)

        var payloadObject: [String: Any] = [:]
        if let profilesData = profilesJSON.data(using: .utf8),
           let profilesObject = try? JSONSerialization.jsonObject(with: profilesData) {
            payloadObject["profiles"] = profilesObject
        } else {
            payloadObject["profiles"] = profiles.map { $0.id.map(String.init) ?? "unknown" }
        }
        if let meta {
            payloadObject["meta"] = meta
        }

        return prettyPrintedJSON(from: payloadObject)
    }

    func prettyPrintedJSON(from encodable: Encodable) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(AnyEncodable(encodable))
            return String(data: data, encoding: .utf8) ?? String(describing: encodable)
        } catch {
            return String(describing: encodable)
        }
    }

    func prettyPrintedJSON(from object: [String: Any]) -> String {
        let description = String(describing: self)

        guard JSONSerialization.isValidJSONObject(object) else { return description }
        do {
            let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            return String(data: data, encoding: .utf8) ?? description
        } catch {
            return description
        }
    }
}

private struct AnyEncodable: Encodable {
    private let encoder: (Encoder) throws -> Void

    init(_ encodable: Encodable) {
        encoder = encodable.encode
    }

    func encode(to encoder: Encoder) throws {
        try self.encoder(encoder)
    }
}

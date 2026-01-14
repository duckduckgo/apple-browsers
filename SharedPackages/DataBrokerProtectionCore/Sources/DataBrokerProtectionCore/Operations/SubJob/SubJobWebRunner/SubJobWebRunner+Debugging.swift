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

public protocol ActionEventReportingForDebug {
    func recordActionPayload(stepType: StepType?, actionId: String?, actionType: ActionType?, payloadJSON: String)
    func recordActionResponse(stepType: StepType?, actionId: String?, actionType: ActionType?, payloadJSON: String)
}

public extension SubJobWebRunning {
    func recordActionPayloadForDebug(action: Action, stepType: StepType?, data: CCFRequestData) {
        guard let reporter = stageCalculator as? ActionEventReportingForDebug else { return }
        let params = Params(state: ActionRequest(action: action, data: data))
        let payloadJSON = prettyPrintedJSON(from: params) ?? String(describing: params)
        reporter.recordActionPayload(stepType: stepType,
                                     actionId: action.id,
                                     actionType: action.actionType,
                                     payloadJSON: payloadJSON)
    }

    func recordActionResponseForDebug(stepType: StepType?, actionId: String?, actionType: ActionType?, payloadJSON: String) {
        guard let reporter = stageCalculator as? ActionEventReportingForDebug else { return }
        reporter.recordActionResponse(stepType: stepType,
                                      actionId: actionId,
                                      actionType: actionType,
                                      payloadJSON: payloadJSON)
    }

    func errorActionId(_ error: Error) -> String? {
        guard let dbpError = error as? DataBrokerProtectionError else { return nil }
        if case let .actionFailed(actionID, _) = dbpError {
            return actionID
        }
        return nil
    }

    func errorPayloadJSON(_ error: Error) -> String {
        if let dbpError = error as? DataBrokerProtectionError {
            switch dbpError {
            case let .actionFailed(actionID, message):
                return prettyPrintedJSON(from: [
                    "type": dbpError.name,
                    "actionId": actionID,
                    "message": message,
                    "description": dbpError.localizedDescription
                ]) ?? dbpError.localizedDescription
            default:
                return prettyPrintedJSON(from: [
                    "type": dbpError.name,
                    "description": dbpError.localizedDescription
                ]) ?? dbpError.localizedDescription
            }
        }
        return prettyPrintedJSON(from: [
            "type": String(describing: type(of: error)),
            "description": error.localizedDescription
        ]) ?? error.localizedDescription
    }

    func prettyPrintedJSON(from encodable: Encodable) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(AnyEncodable(encodable))
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    func prettyPrintedJSON(from object: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(object) else { return nil }
        do {
            let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
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

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
    case snapshot = "Snapshot"
    case actionRetry = "Retry"
    case challenge = "Challenge"
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
        let description: String
        if let error = error as? DataBrokerProtectionError {
            description = error.debugDescription
        } else if let error = error as? EmailError {
            description = error.debugDescription
        } else {
            description = error.localizedDescription
        }

        return DebugHelper.prettyPrintedJSON(from: [
            "type": String(describing: type(of: error)),
            "description": description
        ])
    }
}

#if DEBUG
extension SubJobWebRunning {
    /// Only debug-runner jobs capture snapshots; scheduler jobs in the same process never take this path.
    var capturesDebugSnapshots: Bool {
        DebugActionSnapshots.isEnabled && stageCalculator is DebugEventReporting
    }

    @MainActor
    func captureDebugSnapshot(_ moment: DebugActionSnapshots.Moment, action: Action?) async {
        guard let snapshots = DebugActionSnapshots.current, let reporter = stageCalculator as? DebugEventReporting,
              let handler = webViewHandler as? DataBrokerProtectionWebViewHandler, let step = actionsHandler?.stepType,
              let action else { return }
        let file = await handler.captureSnapshot(using: snapshots, step: step, action: action.actionType, moment: moment)
        reporter.recordDebugEvent(kind: .snapshot, actionType: action.actionType, details: DebugHelper.prettyPrintedJSON(from: [
            "actionId": action.id, "moment": moment.rawValue, "file": file ?? "", "step": step.rawValue
        ]))
    }
}
#endif

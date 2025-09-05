//
//  ActionsHandler.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

public class ActionsHandler {
    private var lastExecutedActionIndex: Int?

    var captchaTransactionId: CaptchaTransactionId?

    public let stepType: StepType
    private var actions: [Action]

    public init(stepType: StepType, actions: [Action]) {
        self.stepType = stepType
        self.actions = actions
    }

    public func currentAction() -> Action? {
        guard let lastExecutedActionIndex = self.lastExecutedActionIndex else { return nil }

        if lastExecutedActionIndex < actions.count {
            return actions[lastExecutedActionIndex]
        } else {
            return nil
        }
    }

    public func nextAction() -> Action? {
        guard let lastExecutedActionIndex = self.lastExecutedActionIndex else {
            // If last executed action index is nil. Means we didn't execute any action, so we return the first action.
            self.lastExecutedActionIndex = 0
            return actions.first
        }

        let nextActionIndex = lastExecutedActionIndex + 1

        if nextActionIndex < actions.count {
            self.lastExecutedActionIndex = nextActionIndex
            return actions[nextActionIndex]
        } else {
            return nil // No more actions to execute
        }
    }

    public func insert(actions: [Action]) {
        if let lastExecutedActionIndex, (lastExecutedActionIndex + 1) < self.actions.count {
            self.actions.insert(contentsOf: actions, at: lastExecutedActionIndex + 1)
        } else {
            self.actions.append(contentsOf: actions)
        }
    }

    // MARK: - Factory Methods

    /// Creates an ActionsHandler for scan steps - always uses all actions
    public static func forScan(_ step: Step) -> ActionsHandler {
        guard step.type == .scan else {
            assertionFailure("Expected scan step but got \(step.type)")
            return ActionsHandler(stepType: step.type, actions: step.actions)
        }
        return ActionsHandler(stepType: .scan, actions: step.actions)
    }

    /// Creates an ActionsHandler for opt-out steps - may halt at email confirmation
    public static func forOptOut(_ step: Step, haltsAtEmailConfirmation: Bool) -> ActionsHandler {
        guard step.type == .optOut else {
            assertionFailure("Expected optOut step but got \(step.type)")
            return ActionsHandler(stepType: step.type, actions: step.actions)
        }

        let actions: [Action]
        if haltsAtEmailConfirmation,
           let emailConfirmIndex = step.actions.firstIndex(where: { $0 is EmailConfirmationAction }) {
            actions = Array(step.actions.prefix(emailConfirmIndex))
        } else {
            actions = step.actions
        }

        return ActionsHandler(stepType: .optOut, actions: actions)
    }

    /// Creates an ActionsHandler for email confirmation continuation - starts at email confirmation action,
    /// but replacing it with a navigate action to open the confirmation URL
    public static func forEmailConfirmationContinuation(_ step: Step, confirmationURL: URL) -> ActionsHandler {
        guard step.type == .optOut else {
            assertionFailure("Expected optOut step but got \(step.type)")
            return ActionsHandler(stepType: step.type, actions: step.actions)
        }

        guard let emailConfirmIndex = step.actions.firstIndex(where: { $0 is EmailConfirmationAction }),
              let emailConfirmationAction = step.actions[emailConfirmIndex] as? EmailConfirmationAction else {
            assertionFailure("Opt-out has no emailConfirmation step")
            return ActionsHandler(stepType: step.type, actions: step.actions)
        }

        let afterIndex = step.actions.index(after: emailConfirmIndex)
        var actions: [Action] = [NavigateAction(id: emailConfirmationAction.id, actionType: .navigate, url: confirmationURL.absoluteString, ageRange: nil, dataSource: nil)]
        actions.append(contentsOf: Array(step.actions.suffix(from: afterIndex)))

        return ActionsHandler(stepType: .optOut, actions: actions)
    }

}

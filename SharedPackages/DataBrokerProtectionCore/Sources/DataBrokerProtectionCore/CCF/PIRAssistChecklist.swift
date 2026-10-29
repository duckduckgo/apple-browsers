//
//  PIRAssistChecklist.swift
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

#if os(macOS) && DEBUG
import Foundation

public struct PIRAssistChecklist: Sendable, Equatable {
    public let items: [String]
    public let currentIndex: Int

    public init(items: [String], currentIndex: Int) {
        self.items = items
        self.currentIndex = currentIndex
    }

    init(stepType: StepType, actions: [Action], currentIndex: Int?, brokerName: String, profileQuery: ProfileQuery,
         isConfirmation: Bool = false) {
        let isOptOut = stepType == .optOut
        let lastClickIndex = actions.lastIndex { $0.actionType == .click }
        let firstClickIndex = actions.firstIndex { $0.actionType == .click }
        let firstNavigationIndex = actions.firstIndex { $0.actionType == .navigate }
        let context = LabelContext(isOptOut: isOptOut, isConfirmation: isConfirmation, brokerName: brokerName,
                                   person: "\(profileQuery.firstName) \(profileQuery.lastName)",
                                   place: "\(profileQuery.city), \(profileQuery.state)")
        // The first half already happened in an earlier run; show it as done so this reads as the same request.
        var items: [String] = isConfirmation ? ["Submit request", "Get \(brokerName)\u{2019}s confirmation email"] : []
        var itemIndexForAction: [Int] = []
        for (index, action) in actions.enumerated() {
            // Forms with an email field fetch one on the side, without a generateEmail action of their own.
            if (action as? FillFormAction)?.needsEmail == true, items.last != Self.createEmailLabel {
                items.append(Self.createEmailLabel)
            }
            if let label = Self.label(for: action, context: context, isFirstNavigation: index == firstNavigationIndex,
                                      isFirstClick: index == firstClickIndex, isLastClick: index == lastClickIndex),
               label != items.last {
                items.append(label)
            }
            itemIndexForAction.append(max(items.count - 1, 0))
        }
        self.items = items
        self.currentIndex = currentIndex.flatMap { itemIndexForAction.indices.contains($0) ? itemIndexForAction[$0] : nil } ?? 0
    }

    static let proveHumanLabel = "Prove you\u{2019}re human"

    func steps(userTurn: PIRAssistUserTurnKind?) -> [PIRAssistStep] {
        items.enumerated().map { index, title in
            let state: PIRAssistStepState
            if index < currentIndex {
                state = .done
            } else if index == currentIndex {
                state = userTurn == nil ? .running : .userTurn
            } else {
                state = title == Self.proveHumanLabel ? .needsUserLater : .upcoming
            }
            return PIRAssistStep(title: title, state: state)
        }
    }

    private static let createEmailLabel = "Create a private email for the reply"

    private struct LabelContext {
        let isOptOut: Bool
        let isConfirmation: Bool
        let brokerName: String
        let person: String
        let place: String
    }

    private static func label(for action: Action, context: LabelContext, isFirstNavigation: Bool, isFirstClick: Bool, isLastClick: Bool) -> String? {
        switch action.actionType {
        case .navigate:
            guard isFirstNavigation else { return "Go to the next page" }
            if context.isConfirmation { return "Open the confirmation link from your email" }
            // Scan URLs already carry the search terms, so the first page load is the search itself.
            return context.isOptOut ? "Open \(context.brokerName)\u{2019}s opt-out form" : "Search for \(context.person) in \(context.place)"
        case .fillForm:
            let fields = (action as? FillFormAction)?.elements.compactMap { fieldName(for: $0.type) } ?? []
            var unique: [String] = []
            for field in fields where !unique.contains(field) { unique.append(field) }
            guard let last = unique.last else { return "Filling in the form" }
            let list = unique.count == 1 ? last : unique.dropLast().joined(separator: ", ") + " and " + last
            return "Entering your " + list
        case .click:
            if context.isOptOut {
                guard isLastClick else { return "Continue" }
                return context.isConfirmation ? "Confirm request" : "Submit request"
            }
            return isFirstClick ? "Run the search" : "Continue"
        case .extract: return "Check the results against your profile"
        case .getCaptchaInfo, .solveCaptcha: return proveHumanLabel
        case .generateEmail: return context.isOptOut ? createEmailLabel : "Create a private email for \(context.brokerName)"
        case .getEmailData: return "Wait for \(context.brokerName)\u{2019}s email"
        case .emailConfirmation: return "Confirm the request from your email"
        case .expectation:
            // A wait for a Turnstile token is the moment a person may have to prove they are human.
            let waitsForTurnstile = action.json.flatMap { String(bytes: $0, encoding: .utf8) }?.contains(PIRAssistUserTurnKind.turnstileTokenField) == true
            return waitsForTurnstile ? proveHumanLabel : nil
        case .condition, .executeScript: return nil
        }
    }

    private static func fieldName(for type: String) -> String? {
        switch type {
        case "firstName", "lastName", "middleName", "fullName": return "name"
        case "city", "state", "fullState", "$generated_zip_code$", "$generated_street_address$": return "location"
        case "age", "birthYear": return "age"
        case "email": return "email"
        case "$generated_phone_number$": return "phone"
        case "profileUrl", "url": return "profile link"
        case "verificationCode": return "verification code"
        default: return nil
        }
    }
}
#endif

//
//  PageAnalysisPIRAction.swift
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

#if DEBUG && compiler(>=6.4) && canImport(FoundationModels)
import Foundation
import FoundationModels
import DataBrokerProtectionCore

/// Only intent is generated. Selectors, action IDs and PIR JSON are constructed by code.
@available(macOS 27.0, *)
@Generable
struct PageAnalysisPIRProposal {
    @Generable
    enum Kind {
        case configuredAction
        case fillForm
        case click
        case wait
        case unsupported
    }

    @Generable
    enum Binding {
        case none
        case firstName
        case lastName
        case email
        case profileUrl
    }

    @Guide(description: "The single next step toward the scan or opt-out goal, considering previous action outcomes. Use unsupported to return control to an existing PIR flow. Use wait for asynchronous verification.")
    var kind: Kind
    @Guide(description: "Exact captured element ID for click/fillForm; empty otherwise. Never a CSS selector.")
    var elementID: String
    @Guide(description: "For fillForm only: firstName/lastName from userProfile, email from fetchedEmail, or profileUrl from extractedProfile. Use none otherwise.")
    var binding: Binding
    @Guide(description: "Brief evidence-based reason. Do not repeat successful actions without new evidence or retry a failed action unchanged.")
    var reason: String
    @Guide(description: "For configuredAction only: copy the exact next configured action ID from the candidate menu. Empty for generated fills/clicks or pauses.")
    var configuredActionID: String = ""
}

/// The checked-in demo files are also bundled, so testing does not depend on checkout paths.
enum PageAnalysisDemo {
    static func resource(_ name: String, extension fileExtension: String) throws -> URL {
        guard let url = Bundle.main.url(forResource: name, withExtension: fileExtension, subdirectory: "PageAnalysisPrototype") else {
            throw PageAnalysisPIRValidationError.message("Missing bundled demo resource: \(name).\(fileExtension). Rebuild the macOS app.")
        }
        return url
    }

    static func json(_ name: String) throws -> String {
        try String(contentsOf: resource(name, extension: "json"), encoding: .utf8)
    }
}

/// The input is an unchanged PIR broker or Step. Progress belongs to the runner, outside that schema.
struct PageAnalysisPIRContext {
    struct Runtime: Codable {
        let stepIndex: Int
        let completedActionCount: Int
        let availableData: [String]
        let failedActionID: String?
    }

    let stepJSON: String
    let runtimeJSON: String
    let stepType: String
    let availableData: Set<String>
    let nextConfiguredAction: PageAnalysisPIRPreview.Payload?
    let runtime: Runtime
    var sequenceSummary: String {
        if let next = nextConfiguredAction {
            return "The first \(runtime.completedActionCount) actions succeeded. Next uncompleted action: \(next.id) (\(next.actionType))."
                + (runtime.failedActionID == nil ? "" : " It failed; do not select it unchanged.")
        }
        return "ALL \(runtime.completedActionCount) supplied actions have already SUCCEEDED. There is NO next configured action. Generate a missing fill/click from the candidate menu or pause. Do not replay anything in actions."
    }
    var json: String { "PIR step: \(stepJSON)\nRunner progress (not broker fields): \(runtimeJSON)\nSequence position: \(sequenceSummary)" }

    init(json: String, runtimeJSON: String) throws {
        guard json.utf8.count <= 64000, runtimeJSON.utf8.count <= 12000,
              let object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else {
            throw PageAnalysisPIRValidationError.message("Supply a PIR broker or step (up to 64 KB), plus separate runner progress (up to 12 KB).")
        }
        let runtime = try JSONDecoder().decode(Runtime.self, from: Data(runtimeJSON.utf8))
        let steps: [[String: Any]]
        if object["steps"] != nil {
            guard let brokerSteps = object["steps"] as? [[String: Any]] else {
                throw PageAnalysisPIRValidationError.message("Broker steps must be an array of PIR steps.")
            }
            steps = brokerSteps
        } else {
            steps = [object]
        }
        guard steps.indices.contains(runtime.stepIndex),
              let stepType = steps[runtime.stepIndex]["stepType"] as? String, ["scan", "optOut"].contains(stepType),
              let actions = steps[runtime.stepIndex]["actions"] as? [[String: Any]], actions.count <= 100,
              (0...actions.count).contains(runtime.completedActionCount),
              runtime.availableData.allSatisfy({ ["userProfile.firstName", "userProfile.lastName", "fetchedEmail.email", "extractedProfile.profileUrl"].contains($0) }) else {
            throw PageAnalysisPIRValidationError.message("Select a valid zero-based stepIndex, a completedActionCount within its actions, and supported binding names. A single step uses stepIndex 0. Maximum 100 actions.")
        }
        let ids = actions.compactMap { $0["id"] as? String }
        guard ids.count == actions.count, !ids.contains(""), Set(ids).count == ids.count,
              actions.allSatisfy({ $0["actionType"] is String }) else {
            throw PageAnalysisPIRValidationError.message("Each PIR action needs a unique nonempty id and an actionType.")
        }
        let next = actions.indices.contains(runtime.completedActionCount) ? actions[runtime.completedActionCount] : nil
        if let failedID = runtime.failedActionID, failedID != (next?["id"] as? String) {
            throw PageAnalysisPIRValidationError.message("failedActionID must identify the action immediately after the completed prefix. Failed actions do not count as completed.")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let stepData = try JSONSerialization.data(withJSONObject: steps[runtime.stepIndex], options: [.prettyPrinted, .sortedKeys])
        guard let stepJSON = String(data: stepData, encoding: .utf8),
              let normalizedRuntime = String(data: try encoder.encode(runtime), encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        self.stepJSON = stepJSON
        self.runtimeJSON = normalizedRuntime
        self.runtime = runtime
        self.stepType = stepType
        self.availableData = Set(runtime.availableData)
        self.nextConfiguredAction = try next.map { try .init(object: $0) }
    }
}

enum PageAnalysisPIRValidationError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message): return message
        }
    }
}

/// Diagnostics accompany the single PIR action; they are never part of the broker format.
struct PageAnalysisPIRPreview {
    let status: String
    let reason: String
    let validation: String
    let action: Payload?

    /// Keep authored fields intact, including those unknown to the generator.
    struct Payload {
        let object: [String: Any]
        let id: String
        let actionType: String

        init(object: [String: Any]) throws {
            guard let id = object["id"] as? String, let type = object["actionType"] as? String else {
                throw PageAnalysisPIRValidationError.message("A PIR action requires id and actionType.")
            }
            self.object = object
            self.id = id
            self.actionType = type
        }

        func json() throws -> String { try PageAnalysisPIRPreview.json(object) }
    }

    func json() throws -> String {
        var object: [String: Any] = ["status": status, "reason": reason, "validation": validation]
        if let action { object["action"] = action.object }
        return try Self.json(object)
    }

    private static func json(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        guard let result = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return result
    }
}

@available(macOS 27.0, *)
enum PageAnalysisPIRActionBuilder {
    struct Target: Decodable {
        let selector: String?
        let formSelector: String?
        let error: String?
    }

    /// A bounded menu of structurally eligible actions; the runner must check goal scope and action outcome.
    static func candidates(snapshot: PageAnalysisSnapshot, context: PageAnalysisPIRContext) -> [PageAnalysisPIRProposal] {
        snapshot.elements.flatMap { element in
            let fills = [PageAnalysisPIRProposal.Binding.firstName, .lastName, .email, .profileUrl].map { binding in
                PageAnalysisPIRProposal(kind: .fillForm, elementID: element.id, binding: binding, reason: "")
            }
            let click = PageAnalysisPIRProposal(kind: .click, elementID: element.id, binding: .none, reason: "")
            return (fills + [click]).filter { (try? validate($0, snapshot: snapshot, context: context)) != nil }
        }
    }

    static func candidateMenu(snapshot: PageAnalysisSnapshot, context: PageAnalysisPIRContext) -> String {
        var choices = candidates(snapshot: snapshot, context: context).map {
            "kind=\($0.kind), elementID=\($0.elementID), binding=\($0.binding)"
        }
        if let next = context.nextConfiguredAction, context.runtime.failedActionID == nil {
            choices.append("kind=configuredAction, configuredActionID=\(next.id), actionType=\(next.actionType). Existing next action; execution belongs to the PIR runner.")
        }
        return choices.isEmpty ? "No supported actions pass validation. Choose wait or unsupported." : choices.joined(separator: "\n")
    }

    /// Prefer semantic HTML; use conservative English label hints only when autocomplete is absent.
    /// Ambiguous/composite names must not be filled with just a first or last name.
    private static func supportedBinding(for element: PageAnalysisSnapshot.Element) -> PageAnalysisPIRProposal.Binding? {
        if element.type == "email" { return .email }
        if let token = element.autocomplete.lowercased().split(separator: " ").last {
            switch token {
            case "given-name": return .firstName
            case "family-name": return .lastName
            case "email": return .email
            case "url": break // A generic URL autocomplete hint does not establish that this is a listing URL.
            case "", "on", "off": break
            default: return nil
            }
        }
        let label = element.label.lowercased().split(whereSeparator: { !$0.isLetter }).joined(separator: " ")
        let profileURL = label.contains("profile url") || label.contains("listing url") || label.contains("listing link")
        if profileURL { return .profileUrl }
        if label.contains("full name") || label.contains("first and last") { return nil }
        let first = label.contains("first name") || label.contains("given name")
        let last = label.contains("last name") || label.contains("family name") || label == "surname"
        let email = label.contains("email") || label.contains("e mail")
        guard [first, last, email].filter({ $0 }).count == 1 else { return nil }
        if first { return .firstName }
        if last { return .lastName }
        return .email
    }

    static func validate(_ proposal: PageAnalysisPIRProposal, snapshot: PageAnalysisSnapshot,
                         context: PageAnalysisPIRContext) throws -> PageAnalysisSnapshot.Element {
        guard let element = snapshot.elements.first(where: { $0.id == proposal.elementID }) else {
            throw PageAnalysisPIRValidationError.message("The model referenced an element not present in its input.")
        }
        guard !element.disabled else {
            throw PageAnalysisPIRValidationError.message("The target is disabled.")
        }
        switch proposal.kind {
        case .fillForm:
            guard element.tag == "input", ["text", "email", "url", "tel", "search", ""].contains(element.type),
                  !element.readOnly, !element.form.isEmpty else {
                throw PageAnalysisPIRValidationError.message("Only writable text inputs inside a captured form are supported for filling.")
            }
            guard !element.hasValue || element.invalid else {
                throw PageAnalysisPIRValidationError.message("The field is already populated and not marked invalid. Do not overwrite it; observe the current state and choose another step.")
            }
            let binding = try binding(for: proposal)
            guard context.availableData.contains(binding.key) else {
                throw PageAnalysisPIRValidationError.message("Required runner data is unavailable: \(binding.key). Supply it through PIR before proposing this fill.")
            }
            guard supportedBinding(for: element) == proposal.binding else {
                throw PageAnalysisPIRValidationError.message("The binding does not match an unambiguous supported field. Full-name and unknown fields need a supported binding or an existing PIR step.")
            }
        case .click:
            // Only fillForm consumes a binding. Ignore irrelevant generated metadata for clicks.
            guard element.tag == "button" || (element.tag == "input" && ["submit", "button"].contains(element.type)) else {
                throw PageAnalysisPIRValidationError.message("This prototype supports native button clicks only.")
            }
            guard !element.formBlocked else {
                throw PageAnalysisPIRValidationError.message("The target's form has missing or invalid fields. Resolve them before clicking.")
            }
        default:
            throw PageAnalysisPIRValidationError.message("No executable action was proposed.")
        }
        return element
    }

    static func configuredPayload(_ proposal: PageAnalysisPIRProposal, context: PageAnalysisPIRContext) throws -> PageAnalysisPIRPreview.Payload {
        guard let next = context.nextConfiguredAction, next.id == proposal.configuredActionID,
              context.runtime.failedActionID == nil else {
            throw PageAnalysisPIRValidationError.message("Only the next configured action may be selected. Completed, later, unknown and failed actions cannot be replayed unchanged.")
        }
        return next
    }

    static func preview(_ proposal: PageAnalysisPIRProposal, snapshot: PageAnalysisSnapshot,
                        context: PageAnalysisPIRContext, target: Target?, rejection: String? = nil) -> PageAnalysisPIRPreview {
        if let rejection = rejection ?? target?.error {
            return .init(status: "rejected", reason: proposal.reason, validation: rejection, action: nil)
        }
        let payload: PageAnalysisPIRPreview.Payload
        do {
            switch proposal.kind {
            case .wait, .unsupported:
                return .init(status: String(describing: proposal.kind), reason: proposal.reason, validation: "No action emitted.", action: nil)
            case .configuredAction:
                payload = try configuredPayload(proposal, context: context)
            case .fillForm, .click:
                _ = try validate(proposal, snapshot: snapshot, context: context)
                guard let selector = target?.selector, let formSelector = target?.formSelector else {
                    throw PageAnalysisPIRValidationError.message("The live target could not be resolved.")
                }
                let isFill = proposal.kind == .fillForm
                let binding = isFill ? try binding(for: proposal) : nil
                var object: [String: Any] = [
                    "id": "model-" + UUID().uuidString,
                    "actionType": isFill ? "fillForm" : "click",
                    "elements": [["type": binding?.type ?? "button", "selector": selector]]
                ]
                if isFill {
                    object["selector"] = formSelector
                    object["dataSource"] = binding?.source
                }
                payload = try .init(object: object)
            }
            try validatePIRRoundTrip(payload, stepType: context.stepType)
        } catch {
            return .init(status: "rejected", reason: proposal.reason, validation: error.localizedDescription, action: nil)
        }
        let validation = proposal.kind == .configuredAction
            ? "Next configured action preserved. PIR JSON round-trip passed."
            : "Unique live target and unchanged control/form state. PIR JSON round-trip passed."
        return .init(status: "proposed", reason: proposal.reason, validation: validation, action: payload)
    }

    private static func binding(for proposal: PageAnalysisPIRProposal) throws -> (key: String, source: String, type: String) {
        switch proposal.binding {
        case .firstName: return ("userProfile.firstName", "userProfile", "firstName")
        case .lastName: return ("userProfile.lastName", "userProfile", "lastName")
        case .email: return ("fetchedEmail.email", "fetchedEmail", "email")
        case .profileUrl: return ("extractedProfile.profileUrl", "extractedProfile", "profileUrl")
        case .none: throw PageAnalysisPIRValidationError.message("A fill action requires a supported data binding.")
        }
    }

    static func validateInput(_ context: PageAnalysisPIRContext) throws {
        _ = try JSONDecoder().decode(Step.self, from: Data(context.stepJSON.utf8))
    }

    private static func validatePIRRoundTrip(_ payload: PageAnalysisPIRPreview.Payload, stepType: String) throws {
        let object = payload.object
        let wrapper: [String: Any] = ["stepType": stepType, "actions": [object]]
        let step = try JSONDecoder().decode(Step.self, from: JSONSerialization.data(withJSONObject: wrapper))
        // This checks serialization, not runner scheduling. Handler factories enforce step types
        // and split opt-out flows at email confirmation; neither belongs in a JSON round-trip.
        let encoded = try JSONEncoder().encode(step)
        guard let preservedStep = try JSONSerialization.jsonObject(with: encoded) as? [String: Any],
              preservedStep["stepType"] as? String == stepType,
              let actions = preservedStep["actions"] as? [NSDictionary], actions.count == 1,
              let preserved = actions.first,
              preserved.isEqual(object) else {
            throw PageAnalysisPIRValidationError.message("The PIR decoder did not preserve the complete action payload.")
        }
    }
}
#endif

//
//  PIRRecoveryGenerator.swift
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
import DataBrokerProtectionCore
import FoundationModels
import WebKit
import os.log

/// Generates a replacement for a failed debug action. The PIR runner owns execution.
@available(macOS 27.0, *)
@MainActor
final class PIRRecoveryGenerator {
    private static let contentWorld = WKContentWorld.world(name: "DuckDuckGo.Debug.PIRRecovery")
    private static let logger = Logger(subsystem: "com.duckduckgo.macos.browser", category: "PIRRecovery")
    private let shouldContinue: () -> Bool
    private let progress: (String) -> Void
    init(shouldContinue: @escaping () -> Bool, progress: @escaping (String) -> Void) {
        self.shouldContinue = shouldContinue
        self.progress = progress
    }

    func generate(in webView: WKWebView, context: PIRRecoveryContext) async throws -> PIRRecoveryPreview {
        try checkCancellation()
        guard let url = webView.url, ["https", "http", "file"].contains(url.scheme?.lowercased() ?? ""), !webView.isLoading else {
            throw PIRRecoveryValidationError.message("The PIR page is not loaded.")
        }
        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            throw PIRRecoveryValidationError.message("On-device model unavailable: \(model.availability). Check Apple Intelligence settings.")
        }
        let identifier = UUID()
        var snapshot = try await runPhase("DOM capture", identifier: identifier) {
            let value = try await webView.evaluateJavaScript(PIRRecoverySnapshot.script, in: nil, contentWorld: Self.contentWorld)
            guard let json = value as? String else { throw PIRRecoveryValidationError.message("Could not capture the page.") }
            return try JSONDecoder().decode(PIRRecoverySnapshot.self, from: Data(json.utf8))
        }
        let instructionTokens = try await model.tokenCount(for: Instructions(PIRRecoveryPrompt.instructions))
        let schemaTokens = try await model.tokenCount(for: PIRRecoveryProposal.generationSchema)
        let inputBudget = model.contextSize - instructionTokens - schemaTokens
            - PIRRecoveryPrompt.maximumResponseTokens - PIRRecoveryPrompt.contextReserveTokens
        var tokens = try await model.tokenCount(for: Prompt(try PIRRecoveryPrompt.request(snapshot: snapshot, context: context)))
        while tokens > inputBudget && !snapshot.elements.isEmpty {
            try checkCancellation()
            snapshot.elements.removeLast(min(10, snapshot.elements.count))
            tokens = try await model.tokenCount(for: Prompt(try PIRRecoveryPrompt.request(snapshot: snapshot, context: context)))
        }
        guard tokens <= inputBudget else {
            throw PIRRecoveryValidationError.message("The PIR context exceeds the on-device model window.")
        }
        let result = try await generateNextAction(webView: webView, url: url, snapshot: snapshot, context: context,
                                                   model: model, inputBudget: inputBudget, identifier: identifier)
        try await validateDocument(webView, url: url, timeOrigin: snapshot.documentTimeOrigin)
        return result
    }

    private func checkCancellation() throws {
        try Task.checkCancellation()
        guard shouldContinue() else { throw CancellationError() }
    }

    private func runPhase<Value>(_ phase: String, identifier: UUID, operation: () async throws -> Value) async throws -> Value {
        try checkCancellation()
        progress(phase)
        Self.logger.notice("[PIR Recovery] run=\(identifier.uuidString, privacy: .public) phase=\(phase, privacy: .public)")
        let value = try await operation()
        try checkCancellation()
        return value
    }

    private func generateNextAction(webView: WKWebView, url: URL, snapshot: PIRRecoverySnapshot, context: PIRRecoveryContext,
                                    model: SystemLanguageModel, inputBudget: Int,
                                    identifier: UUID) async throws -> PIRRecoveryPreview {
        var feedback: String?
        var nextAction = PIRRecoveryPreview(status: .unsupported, reason: "No action emitted.", validation: "", action: nil)
        for attempt in 1...2 {
            try await validateDocument(webView, url: url, timeOrigin: snapshot.documentTimeOrigin)
            // Retry in a fresh session so the first transcript does not consume the remaining context.
            let request = try PIRRecoveryPrompt.request(snapshot: snapshot, context: context, feedback: feedback)
            let prompt = Prompt(request)
            let tokens = try await runPhase("PIR attempt token count", identifier: identifier) {
                try await model.tokenCount(for: prompt)
            }
            guard tokens <= inputBudget else {
                progress("Retry skipped: validation feedback exceeds the remaining input budget.")
                break
            }
            let session = LanguageModelSession(model: model, instructions: Instructions(PIRRecoveryPrompt.instructions))
            let response = try await runPhase("PIR next-action generation (attempt \(attempt))", identifier: identifier) {
                try await session.respond(to: prompt, generating: PIRRecoveryProposal.self,
                                          options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: PIRRecoveryPrompt.maximumResponseTokens))
            }
            Self.logger.notice("[PIR Recovery] run=\(identifier.uuidString, privacy: .public) actualInputTokens=\(response.usage.input.totalTokenCount) actualOutputTokens=\(response.usage.output.totalTokenCount)")
            try await validateDocument(webView, url: url, timeOrigin: snapshot.documentTimeOrigin)
            let preview = try await runPhase("PIR action validation", identifier: identifier) {
                try await self.validateProposal(response.content, snapshot: snapshot, context: context, webView: webView)
            }
            nextAction = preview
            if preview.status == .rejected { progress("Proposal rejected: \(preview.validation)") }
            guard attempt == 1, preview.status == .rejected else { break }
            do {
                _ = try PIRRecoveryActionBuilder.validate(response.content, snapshot: snapshot, context: context)
                break // Live target changed or PIR decoding failed: retrying stale evidence cannot fix that.
            } catch {
                feedback = "Rejected kind=\(response.content.kind), elementID=\(response.content.elementID.prefix(30)), "
                    + "binding=\(response.content.binding): "
                    + String(error.localizedDescription.prefix(240))
                    + " Choose a different eligible candidate or pause. Do not repeat the rejected action."
            }
        }
        return nextAction
    }

    private func validateProposal(_ proposal: PIRRecoveryProposal, snapshot: PIRRecoverySnapshot,
                                  context: PIRRecoveryContext, webView: WKWebView) async throws -> PIRRecoveryPreview {
        guard proposal.kind == .fillForm || proposal.kind == .click else {
            return PIRRecoveryActionBuilder.preview(proposal, snapshot: snapshot, context: context, target: nil)
        }
        do {
            _ = try PIRRecoveryActionBuilder.validate(proposal, snapshot: snapshot, context: context)
            let script = try PIRRecoverySnapshot.targetValidationScript(captureID: snapshot.captureID, elementID: proposal.elementID)
            let value = try await webView.evaluateJavaScript(script, in: nil, contentWorld: Self.contentWorld)
            guard let json = value as? String else {
                throw PIRRecoveryValidationError.message("The captured document or target expired. Analyze again.")
            }
            let target = try JSONDecoder().decode(PIRRecoveryActionBuilder.Target.self, from: Data(json.utf8))
            return PIRRecoveryActionBuilder.preview(proposal, snapshot: snapshot, context: context, target: target)
        } catch {
            try checkCancellation()
            return PIRRecoveryActionBuilder.preview(proposal, snapshot: snapshot, context: context,
                                                            target: nil, rejection: error.localizedDescription)
        }
    }

    private func validateDocument(_ webView: WKWebView, url: URL, timeOrigin: Double) async throws {
        try checkCancellation()
        let currentTimeOrigin = try await webView.evaluateJavaScript("performance.timeOrigin", in: nil, contentWorld: Self.contentWorld) as? Double
        guard !webView.isLoading, webView.url == url, currentTimeOrigin == timeOrigin else {
            throw PIRRecoveryValidationError.message("The page navigated during analysis. Analyze it again.")
        }
    }

}

/// Injects on-device recovery only into manually launched PIR debug jobs.
@available(macOS 27.0, *)
@MainActor
enum PIRRecovery {
    static func makeSession() -> DebugPIRRecoverySession {
        DebugPIRRecoverySession { request, webView, shouldContinue, log in
            let context = try PIRRecoveryContext(stepJSON: request.stepJSON, completedActionCount: request.completedActionCount,
                                                 failedActionID: request.failedActionID, availableData: request.availableData)
            log("Recovery objective: \(context.recoveryObjective)")
            let generator = PIRRecoveryGenerator(shouldContinue: shouldContinue, progress: log)
            let preview = try await generator.generate(in: webView, context: context)
            log("Model proposal and validation:\n" + (try preview.json()))
            guard let action = preview.action else { return nil }
            let data = try JSONSerialization.data(withJSONObject: ["stepType": context.stepType, "actions": [action.object]])
            return try JSONDecoder().decode(Step.self, from: data).actions.first
        }
    }
}

#endif

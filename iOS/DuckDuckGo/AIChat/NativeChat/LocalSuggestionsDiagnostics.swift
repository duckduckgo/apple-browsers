//
//  LocalSuggestionsDiagnostics.swift
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
import DuckAILocalTasks

/// Demo branch: the last suggested-prompts attempt, shown in the debug screen so a fallback explains itself.
@MainActor
final class LocalSuggestionsDiagnostics: ObservableObject {
    static let shared = LocalSuggestionsDiagnostics()

    struct Entry: Equatable {
        let date: Date
        let outcome: String
        let modelName: String?
        let details: [String]
        let raw: String
    }

    @Published private(set) var last: Entry?

    func record(run: SuggestedPromptsRun, variant: SuggestionsVariant, source: String, sheetTime: Duration? = nil) {
        var details = Self.details(run: run, variant: variant)
        details.insert("Source \(source)", at: 0)
        if let sheetTime { details.append("Sheet cache lookup \(Self.seconds(sheetTime))") }
        record(outcome: Self.outcome(run.result), modelName: variant.method == .model ? variant.modelID : variant.method.rawValue,
               details: details, raw: run.raw)
    }

    static func details(run: SuggestedPromptsRun, variant: SuggestionsVariant) -> [String] {
        [
            "\(variant.input.rawValue) · \(variant.count) prompts · \(variant.locale) · budget \(variant.budgetSeconds) s",
            "Load \(seconds(run.stats?.loadTime)) · read \(seconds(run.stats?.promptTime)) · write \(seconds(run.stats?.generateTime))",
            "Preparation (includes queue) \(seconds(run.loadTime)) · first text \(seconds(run.timeToFirstText))",
            "First chip \(seconds(run.firstChipTime)) · total \(seconds(run.total))",
            variant.method == .templates ? "Total includes template preparation and ranking. Model phases do not apply." :
                "Unavailable phases are not estimated. Zero MLX load means a reused model. Fixed instruction cache reuse is unsupported."
        ]
    }

    static func outcome(_ result: SuggestedPromptsResult) -> String {
        switch result {
        case .generated(let prompts, _): "Generated \(prompts.count) prompts"
        case .timedOut: "Catalog fallback: budget expired"
        case .failed(let error): "Catalog fallback: \(error)"
        case .unusable: "Catalog fallback: no usable questions"
        }
    }

    private static func seconds(_ duration: Duration?) -> String {
        guard let duration else { return "unavailable" }
        return String(format: "%.3f s", Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18)
    }

    func record(outcome: String, modelName: String? = nil, details: [String] = [], raw: String = "") {
        last = Entry(date: Date(), outcome: outcome, modelName: modelName, details: details, raw: raw)
    }
}

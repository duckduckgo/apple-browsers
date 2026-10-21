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

    func record(outcome: String, modelName: String? = nil, details: [String] = [], raw: String = "") {
        last = Entry(date: Date(), outcome: outcome, modelName: modelName, details: details, raw: raw)
    }
}

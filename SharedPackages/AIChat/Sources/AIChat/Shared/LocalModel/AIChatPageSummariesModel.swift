//
//  AIChatPageSummariesModel.swift
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

import Combine

/// The model Duck.ai uses for "Summarize this page". Choosing a local model is the opt-in to local summaries.
public enum AIChatPageSummariesModel: String, CaseIterable, Sendable {
    case duckAI = "duckai"
    case appleIntelligence
}

/// Each platform keeps the choice in its own settings store.
public protocol AIChatPageSummariesModelStoring {
    var pageSummariesModel: AIChatPageSummariesModel { get set }
    var pageSummariesModelPublisher: AnyPublisher<AIChatPageSummariesModel, Never> { get }
}

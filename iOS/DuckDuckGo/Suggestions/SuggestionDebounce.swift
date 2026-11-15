//
//  SuggestionDebounce.swift
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

import Combine
import FeatureFlags_iOS
import PrivacyConfig

struct SuggestionRequest: Equatable {
    let query: String
    let includeRemoteSuggestions: Bool
}

extension Publisher where Output == String, Failure == Never {

    func debounceSuggestions<S: Scheduler>(using featureFlagger: FeatureFlagger, scheduler: S) -> AnyPublisher<SuggestionRequest, Never> {
        Deferred {
            var isFirstQuery = true
            return self.map { text -> AnyPublisher<SuggestionRequest, Never> in
                let isEnabled = featureFlagger.isFeatureOn(.suggestionDebounce200ms)
                let sendImmediately = isFirstQuery || text.isEmpty
                isFirstQuery = text.isEmpty
                let remote = SuggestionRequest(query: text, includeRemoteSuggestions: true)
                guard isEnabled else {
                    return Just(remote)
                        .delay(for: .milliseconds(100), scheduler: scheduler)
                        .eraseToAnyPublisher()
                }
                if text.isEmpty {
                    return Just(remote).eraseToAnyPublisher()
                }
                let localRequest = Just(SuggestionRequest(query: text, includeRemoteSuggestions: false))
                let local = sendImmediately ? localRequest.eraseToAnyPublisher() : localRequest
                    .delay(for: .milliseconds(100), scheduler: scheduler).eraseToAnyPublisher()
                return local.merge(with: Just(remote).delay(for: .milliseconds(150), scheduler: scheduler))
                    .eraseToAnyPublisher()
            }
            .switchToLatest()
        }
        .eraseToAnyPublisher()
    }
}

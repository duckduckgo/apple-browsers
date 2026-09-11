//
//  WebsitePermissionDefaultsMock.swift
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

#if DEBUG

import Combine
import Foundation

final class WebsitePermissionDefaultsMock: WebsitePermissionDefaultsProviding {

    private let subject: CurrentValueSubject<[WebsitePermissionCategory: PersistedPermissionDecision], Never>

    var setDefaultDecisionCalls: [(decision: PersistedPermissionDecision, category: WebsitePermissionCategory)] = []
    /// When false, reads return `.ask` and writes are ignored, mirroring the feature flag being off.
    var isFeatureEnabled = true

    var defaultsPublisher: AnyPublisher<[WebsitePermissionCategory: PersistedPermissionDecision], Never> {
        subject.removeDuplicates().eraseToAnyPublisher()
    }

    init(decisions: [WebsitePermissionCategory: PersistedPermissionDecision] = [:]) {
        var initial = WebsitePermissionCategory.allCases.reduce(into: [WebsitePermissionCategory: PersistedPermissionDecision]()) {
            $0[$1] = WebsitePermissionDefaults.fallbackDecision
        }
        initial.merge(decisions) { _, override in override }
        subject = CurrentValueSubject(initial)
    }

    func defaultDecision(for category: WebsitePermissionCategory) -> PersistedPermissionDecision {
        guard isFeatureEnabled else { return WebsitePermissionDefaults.fallbackDecision }
        return subject.value[category] ?? WebsitePermissionDefaults.fallbackDecision
    }

    func setDefaultDecision(_ decision: PersistedPermissionDecision, for category: WebsitePermissionCategory) {
        setDefaultDecisionCalls.append((decision: decision, category: category))
        guard isFeatureEnabled,
              WebsitePermissionDefaults.availableDecisions.contains(decision),
              subject.value[category] != decision
        else { return }

        var decisions = subject.value
        decisions[category] = decision
        subject.send(decisions)
    }
}

#endif

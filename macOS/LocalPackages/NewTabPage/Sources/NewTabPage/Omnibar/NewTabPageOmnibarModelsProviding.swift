//
//  NewTabPageOmnibarModelsProviding.swift
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

@MainActor
public protocol NewTabPageOmnibarModelsProviding {
    var lastFetchedSections: [NewTabPageDataModel.AIModelSection]? { get }
    /// Attachment limits resolved for the user's tier from the most recent duck.ai models fetch.
    /// `nil` until a fetch succeeds, or when the backend omits them.
    var attachmentLimits: NewTabPageDataModel.AttachmentLimits? { get }
    /// Whether a free-tier user is currently eligible for a free trial — the web uses this to pick
    /// "Try for Free" vs "Upgrade" copy independently of `AIModelItem.upsell`, which only encodes the flow.
    var isEligibleForFreeTrial: Bool { get }
    /// Fires when tier-affecting state changes upstream (e.g. a purchase completes), telling
    /// `NewTabPageOmnibarClient` to refetch — NTP reuses one webview per window, so nothing else would prompt it.
    var modelsDidChangePublisher: AnyPublisher<Void, Never> { get }
    func fetchAIModelSections() async -> [NewTabPageDataModel.AIModelSection]
}

public extension NewTabPageOmnibarModelsProviding {
    var attachmentLimits: NewTabPageDataModel.AttachmentLimits? { nil }
    var isEligibleForFreeTrial: Bool { false }
    var modelsDidChangePublisher: AnyPublisher<Void, Never> { Empty().eraseToAnyPublisher() }
}

//
//  OnboardingSuggestionsViewModel.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

public protocol OnboardingNavigationDelegate: AnyObject {
    func searchFromOnboarding(for query: String)
    func navigateFromOnboarding(to url: URL)
}

public struct OnboardingSearchSuggestionsViewModel {
    let suggestedSearchesProvider: OnboardingSuggestionsItemsProviding
    public weak var delegate: OnboardingNavigationDelegate?

    public init(
        suggestedSearchesProvider: OnboardingSuggestionsItemsProviding,
        delegate: OnboardingNavigationDelegate? = nil
    ) {
        self.suggestedSearchesProvider = suggestedSearchesProvider
        self.delegate = delegate
    }

    public var itemsList: [ContextualOnboardingListItem] {
        suggestedSearchesProvider.list
    }

    public func listItemPressed(_ item: ContextualOnboardingListItem) {
        delegate?.searchFromOnboarding(for: item.title)
    }
}

public struct OnboardingSiteSuggestionsViewModel {
    let suggestedSitesProvider: OnboardingSuggestionsItemsProviding
    public weak var delegate: OnboardingNavigationDelegate?

    public init(
        title: String,
        suggestedSitesProvider: OnboardingSuggestionsItemsProviding,
        delegate: OnboardingNavigationDelegate? = nil
) {
        self.title = title
        self.suggestedSitesProvider = suggestedSitesProvider
        self.delegate = delegate
    }

    public let title: String

    public var itemsList: [ContextualOnboardingListItem] {
        suggestedSitesProvider.list
    }

    public func listItemPressed(_ item: ContextualOnboardingListItem) {
        guard let url = URL(string: item.title) else { return }
        delegate?.navigateFromOnboarding(to: url)
    }
}

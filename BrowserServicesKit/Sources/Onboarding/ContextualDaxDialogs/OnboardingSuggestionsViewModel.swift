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

public protocol OnboardingSearchSuggestionsPixelReporting {
    func trackSearchSuggetionOptionTapped()
}

public protocol OnboardingSiteSuggestionsPixelReporting {
    func trackSiteSuggetionOptionTapped()
}

public struct OnboardingSearchSuggestionsViewModel {
    let suggestedSearchesProvider: OnboardingSuggestionsItemsProviding
    public weak var delegate: OnboardingNavigationDelegate?
    private let pixelReporter: OnboardingSearchSuggestionsPixelReporting

    public init(
        suggestedSearchesProvider: OnboardingSuggestionsItemsProviding,
        delegate: OnboardingNavigationDelegate? = nil,
        pixelReporter: OnboardingSearchSuggestionsPixelReporting
    ) {
        self.suggestedSearchesProvider = suggestedSearchesProvider
        self.delegate = delegate
        self.pixelReporter = pixelReporter
    }

    public var itemsList: [ContextualOnboardingListItem] {
        suggestedSearchesProvider.list
    }

    public func listItemPressed(_ item: ContextualOnboardingListItem) {
        pixelReporter.trackSearchSuggetionOptionTapped()
        delegate?.searchFromOnboarding(for: item.title)
    }
}

public struct OnboardingSiteSuggestionsViewModel {
    let suggestedSitesProvider: OnboardingSuggestionsItemsProviding
    public weak var delegate: OnboardingNavigationDelegate?
    private let pixelReporter: OnboardingSiteSuggestionsPixelReporting

    public init(
        title: String,
        suggestedSitesProvider: OnboardingSuggestionsItemsProviding,
        delegate: OnboardingNavigationDelegate? = nil,
        pixelReporter: OnboardingSiteSuggestionsPixelReporting
    ) {
        self.title = title
        self.suggestedSitesProvider = suggestedSitesProvider
        self.delegate = delegate
        self.pixelReporter = pixelReporter
    }

    public let title: String

    public var itemsList: [ContextualOnboardingListItem] {
        suggestedSitesProvider.list
    }

    public func listItemPressed(_ item: ContextualOnboardingListItem) {
        guard let url = URL(string: item.title) else { return }
        pixelReporter.trackSiteSuggetionOptionTapped()
        delegate?.navigateFromOnboarding(to: url)
    }
}

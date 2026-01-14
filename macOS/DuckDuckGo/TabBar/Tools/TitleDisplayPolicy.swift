//
//  TitleDisplayPolicy.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

protocol TitleDisplayPolicy {
    func mustSkipDisplayingTitle(title: String, url: URL?, previousURL: URL?, isLoading: Bool) -> Bool
    func mustAnimateTitleTransition(title: String, previousTitle: String) -> Bool
    func mustAnimateNewTitleFadeIn(targetURL: URL?, previousURL: URL?) -> Bool
}

struct DefaultTitleDisplayPolicy: TitleDisplayPolicy {

    /// When navigating to a URL within the same domain, the `Tab.title` switches to a placeholder (domain name) as soon as possible -but before Page Load completes-..
    /// In order to avoid distracting the user, in this scenario we'll avoid rendering a Placeholder Title (up until Page Load is complete)
    ///
    func mustSkipDisplayingTitle(title: String, url: URL?, previousURL: URL?, isLoading: Bool) -> Bool {
        previousURL?.host == url?.host && url?.suggestedTitlePlaceholder == title && isLoading
    }

    /// We avoid animating title transitions when the actual text didn't change
    ///
    func mustAnimateTitleTransition(title: String, previousTitle: String) -> Bool {
        title != previousTitle && previousTitle.isEmpty == false
    }

    /// Fade-In animation is only performed when visiting a different
    ///
    func mustAnimateNewTitleFadeIn(targetURL: URL?, previousURL: URL?) -> Bool {
        targetURL?.host?.dropSubdomain() != previousURL?.host?.dropSubdomain()
    }
}

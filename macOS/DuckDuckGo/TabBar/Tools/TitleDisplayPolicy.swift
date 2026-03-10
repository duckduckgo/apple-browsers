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
    func mustSkipDisplayingTitle(title: String, url: URL?, previousTitle: String?, previousURL: URL?, isLoading: Bool) -> Bool
    func mustAnimateTitleTransition(title: String, previousTitle: String) -> Bool
}

struct DefaultTitleDisplayPolicy: TitleDisplayPolicy {

    /// We'll avoid displaying a Page Title whenever:
    /// 
    ///     1. Navigating to a URL within the same Host, and `Tab.title` switches to a placeholder (domain name)
    ///     2. URL and title are both unchanged from the previous values
    ///     3. Hosts differ but the Title is the same
    ///
    func mustSkipDisplayingTitle(title: String, url: URL?, previousTitle: String?, previousURL: URL?, isLoading: Bool) -> Bool {
        let isSameHost = previousURL?.host == url?.host
        let isPlaceholderTitle = url?.suggestedTitlePlaceholder == title

        let isSameURL = url != nil && url == previousURL
        let isSameTitle = title == previousTitle
        let isDifferentHost = url != nil && previousURL != nil && url?.host != previousURL?.host

        let isLoadingPlaceholder = isSameHost && isPlaceholderTitle && isLoading
        let isRedundantUpdate = isSameURL && isSameTitle
        let isCrossHostSameTitle = isDifferentHost && isSameTitle

        return isLoadingPlaceholder || isRedundantUpdate || isCrossHostSameTitle
    }

    /// We avoid animating title transitions when the actual text didn't change
    ///
    func mustAnimateTitleTransition(title: String, previousTitle: String) -> Bool {
        title != previousTitle && previousTitle.isEmpty == false
    }
}

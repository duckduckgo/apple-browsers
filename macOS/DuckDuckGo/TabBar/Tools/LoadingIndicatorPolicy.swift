//
//  LoadingIndicatorPolicy.swift
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
import AppKit

protocol LoadingIndicatorPolicy {
    func shouldShowLoadingIndicator(isLoading: Bool, url: URL?, error: Error?) -> Bool
    func shouldCrossfadeFavicon(newFavicon: NSImage?, oldFavicon: NSImage?, displaysPlaceholder: Bool) -> Bool
}

struct DefaultLoadingIndicatorPolicy: LoadingIndicatorPolicy {

    func shouldShowLoadingIndicator(isLoading: Bool, url: URL?, error: Error?) -> Bool {
        guard isLoading, error == nil, let url else {
            return false
        }

        return !url.isDuckDuckGoSearch && !url.isDuckPlayer && url.navigationalScheme?.isHypertextScheme == true
    }

    func shouldCrossfadeFavicon(newFavicon: NSImage?, oldFavicon: NSImage?, displaysPlaceholder: Bool) -> Bool {
        displaysPlaceholder && newFavicon != nil || oldFavicon != nil && oldFavicon != newFavicon
    }
}

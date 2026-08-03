//
//  NewTabPageBurnerContextProvider.swift
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

import FeatureFlags
import NewTabPage
import PrivacyConfig
import WebKit

/// Resolves burner-ness for `NewTabPageConfigurationClient` from the requesting webView's data
/// store, rather than `webView.window`, so it works before the webView is attached to a window
/// (see `WKWebsiteDataStore.fireWindowSession`, set on the Fire Window's data store at window
/// creation time in `WindowsManager`).
final class NewTabPageBurnerContextProvider: NewTabPageBurnerContextProviding {

    private let featureFlagger: FeatureFlagger

    init(featureFlagger: FeatureFlagger) {
        self.featureFlagger = featureFlagger
    }

    func isBurner(webView: WKWebView?) -> Bool {
        guard featureFlagger.isFeatureOn(.fireWindowNewTabPage) else { return false }
        return webView?.configuration.websiteDataStore.fireWindowSession != nil
    }
}

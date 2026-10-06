//
//  TabViewController+PageSignals.swift
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

import DDGNavigation
import WebKit

// WebKit delivers these private callbacks to the tab's existing navigation delegate.
extension TabViewController {


    /// We'll conceal the `contentRuleList` selector whenever the Feature Flag is disabled
    override func responds(to aSelector: Selector!) -> Bool {
        let contentRuleListActionSelector = NSSelectorFromString("_webView:contentRuleListWithIdentifier:performedAction:forURL:")

        if aSelector == contentRuleListActionSelector {
            return featureFlagger.isFeatureOn(.pageSignals)
        }

        return super.responds(to: aSelector)
    }

    @objc(_webView:contentRuleListWithIdentifier:performedAction:forURL:)
    func webView(_ webView: WKWebView, contentRuleListWithIdentifier identifier: String, performedAction action: NSObject, forURL url: URL) {
        guard webView == self.webView else {
            return
        }

        pageSignalsMonitor.didPerformContentRuleListAction(ContentRuleListAction(webKitAction: action), for: url)
    }
}

extension TabViewController {

    /// Error pages keep the failed navigation's signals.
    func pageSignalsDidCommitNavigation(to url: URL?) {
        guard !specialErrorPageNavigationHandler.isSpecialErrorPageRequest else {
            return
        }

        pageSignalsMonitor.didCommitNavigation(to: url)
    }
}

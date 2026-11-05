//
//  FindInPage.swift
//  DuckDuckGo
//
//  Copyright © 2019 DuckDuckGo. All rights reserved.
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
import WebKit
import Core
import FeatureFlags_iOS
import PrivacyConfig

enum FindInPageImplementation {
    case system
    case legacy
    case delegateSessionExperiment

    var isDelegateSessionExperiment: Bool {
        self == .delegateSessionExperiment
    }

    init(featureFlagger: FeatureFlagger) {
        if #available(iOS 27.0, *), featureFlagger.isFeatureOn(.legacyFindInPage),
           featureFlagger.isFeatureOn(.legacyFindInPageUIWithSystemFindEngine) {
            self = .delegateSessionExperiment
            return
        }
        if #available(iOS 16.0, *), !featureFlagger.isFeatureOn(.legacyFindInPage) {
            self = .system
        } else {
            self = .legacy
        }
    }
}

protocol FindInPageDelegate: NSObjectProtocol {
    
    func updated(findInPage: any FindInPageSearching)

}

protocol FindInPageSearching: AnyObject {
    var delegate: FindInPageDelegate? { get set }
    var searchTerm: String { get }
    var current: Int { get }
    var total: Int { get }
    var diagnosticStatus: String? { get }
    func search(forText text: String) -> Bool
    func next()
    func previous()
    func done()
    func keepCurrentResultVisible(visibleBottomFraction: CGFloat)
}

extension FindInPageSearching {
    var diagnosticStatus: String? { nil }
    func keepCurrentResultVisible(visibleBottomFraction: CGFloat) {}
}

class FindInPage: NSObject, FindInPageSearching {

    weak var delegate: FindInPageDelegate?
    weak var webView: WKWebView?

    var searchTerm: String = ""
    var current: Int = 0
    var total: Int = 0

    init(webView: WKWebView) {
        self.webView = webView
        super.init()
    }

    func done() {
        evaluate(js: "window.__firefox__.findDone()")
    }

    func next() {
        evaluate(js: "window.__firefox__.findNext()")
    }

    func previous() {
        delegate?.updated(findInPage: self)
        evaluate(js: "window.__firefox__.findPrevious()")
    }

    func search(forText text: String) -> Bool {
        guard text != searchTerm else { return false }
        searchTerm = text
        
        let escaped =
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\'", with: "\\\'")

        evaluate(js: "window.__firefox__.find('\(escaped)')")

        return true
    }

    private func evaluate(js: String) {
        webView?.evaluateJavaScript(js, in: nil, in: .defaultClient)
    }

    func update(currentResult: Int?, totalResults: Int?) {
        current = currentResult ?? current
        total = totalResults ?? total
        delegate?.updated(findInPage: self)
    }

    func keepCurrentResultVisible(visibleBottomFraction: CGFloat) {
        let fraction = min(1, max(0, visibleBottomFraction))
        evaluate(js: """
            (() => {
                const match = document.querySelector('.__firefox__find-highlight-active');
                if (!match) return;
                const visibleBottom = window.innerHeight * \(fraction) - 16;
                const overflow = match.getBoundingClientRect().bottom - visibleBottom;
                if (overflow > 0) window.scrollBy(0, overflow);
            })();
            """)
    }

}

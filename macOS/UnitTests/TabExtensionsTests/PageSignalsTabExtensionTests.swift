//
//  PageSignalsTabExtensionTests.swift
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
import Common
import DDGNavigation
import FeatureFlags_macOS
import PrivacyConfig
import Testing
import WebKit

@testable import DuckDuckGo_Privacy_Browser

@MainActor
struct PageSignalsTabExtensionTests {

    private let tabExtension = PageSignalsTabExtension(webViewPublisher: Empty<WKWebView, Never>(),
                                                       featureFlagger: MockFeatureFlagger(featuresStub: [FeatureFlag.pageSignals.rawValue: true]),
                                                       tld: TLD())

    @available(macOS 13, *)
    @Test("Error page commits keep the failed navigation's signals", .timeLimit(.minutes(1)))
    func errorPageCommitKeepsFailureSignals() {
        let url = URL(string: "https://www.example.com")!

        tabExtension.navigation(makeNavigation(url: url), didFailWith: dnsError(failingURL: url))
        tabExtension.didCommit(makeNavigation(url: url, navigationType: .alternateHtmlLoad, isCommitted: true))

        #expect(tabExtension.pageSignals?.host == "example.com")
        #expect(encodedFailures() == ["example.com": ["(NSURLErrorDomain,-1003)"]])
    }

    @available(macOS 13, *)
    @Test("Failures after commit leave the page's signals untouched", .timeLimit(.minutes(1)))
    func failureAfterCommitIsIgnored() {
        let navigation = makeNavigation(url: URL(string: "https://www.example.com")!, isCommitted: true)

        tabExtension.didCommit(navigation)
        tabExtension.navigation(navigation, didFailWith: dnsError(failingURL: URL(string: "https://www.other.com")!))

        #expect(tabExtension.pageSignals?.host == "example.com")
        #expect(tabExtension.pageSignals?.resourceFailures.isEmpty == true)
    }

    @available(macOS 13, *)
    @Test("Provisional failures are recorded against the error's failing URL", .timeLimit(.minutes(1)))
    func provisionalFailureUsesFailingURL() {
        let navigation = makeNavigation(url: URL(string: "https://www.example.com")!)

        tabExtension.navigation(navigation, didFailWith: dnsError(failingURL: URL(string: "https://www.redirected.com")!))

        #expect(tabExtension.pageSignals?.host == "redirected.com")
        #expect(encodedFailures() == ["redirected.com": ["(NSURLErrorDomain,-1003)"]])
    }
}

private extension PageSignalsTabExtensionTests {

    func encodedFailures() -> [String: Set<String>]? {
        tabExtension.pageSignals?.resourceFailures.mapValues { Set($0.map(\.stringValue)) }
    }

    func makeNavigation(url: URL, navigationType: NavigationType = .custom(.userEnteredUrl), isCommitted: Bool = false) -> Navigation {
        let action = NavigationAction(request: URLRequest(url: url),
                                      navigationType: navigationType,
                                      currentHistoryItemIdentity: nil,
                                      redirectHistory: nil,
                                      isUserInitiated: true,
                                      sourceFrame: FrameInfo(frame: .mock()),
                                      targetFrame: nil,
                                      shouldDownload: false,
                                      mainFrameNavigation: nil)

        return Navigation(identity: .init(nil), responders: .init(), state: .started, redirectHistory: [action], isCurrent: true, isCommitted: isCommitted)
    }

    func dnsError(failingURL: URL) -> WKError {
        WKError(_nsError: NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotFindHost, userInfo: [NSURLErrorFailingURLErrorKey: failingURL]))
    }
}

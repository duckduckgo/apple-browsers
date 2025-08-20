//
//  MockUserAgent.swift
//  DuckDuckGo
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

import BrowserServicesKit
import Foundation
import WebKit
@testable import Core

class MockUserAgentManager: UserAgentManaging {

    private var userAgent = UserAgent()
    private var privacyConfig: PrivacyConfiguration

    var extractedAndSetDefaultUserAgent: String = "mock-UA"
    var extractAndSetDefaultUserAgentCallCount = 0
    var setUserAgentCalled: String?

    init(privacyConfig: PrivacyConfiguration) {
        self.privacyConfig = privacyConfig
    }

    func extractAndSetDefaultUserAgent() async throws -> String {
        extractAndSetDefaultUserAgentCallCount += 1
        return extractedAndSetDefaultUserAgent
    }

    func setDefaultUserAgent(_ userAgent: String) {
        setUserAgentCalled = userAgent
    }

    public func userAgent(isDesktop: Bool) -> String {
        return userAgent.agent(forUrl: nil, isDesktop: isDesktop, privacyConfig: privacyConfig)
    }

    func userAgent(isDesktop: Bool, url: URL?) -> String {
        return userAgent.agent(forUrl: url, isDesktop: isDesktop)
    }

    public func update(request: inout URLRequest, isDesktop: Bool) {
        request.addValue(userAgent.agent(forUrl: nil, isDesktop: isDesktop, privacyConfig: privacyConfig), forHTTPHeaderField: "User-Agent")
    }

    public func update(webView: WKWebView, isDesktop: Bool, url: URL?) {
        let agent = userAgent.agent(forUrl: url, isDesktop: isDesktop, privacyConfig: privacyConfig)
        webView.customUserAgent = agent
    }

}

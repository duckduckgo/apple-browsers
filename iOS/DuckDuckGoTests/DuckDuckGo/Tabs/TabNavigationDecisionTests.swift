//
//  TabNavigationDecisionTests.swift
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

import Testing
import WebKit
@testable import DuckDuckGo

@Suite("Tab navigation decisions")
struct TabNavigationDecisionTests {

    @available(iOS 16, macOS 13, *)
    @Test("Allowing app links uses WebKit's ordinary allow policy", .timeLimit(.minutes(1)))
    func whenAppLinksAreEnabledThenWebKitPolicyIsAllow() {
        let decision = TabNavigationDecision.allow(appLinks: .enabled)

        #expect(decision.webKitPolicy == .allow)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Suppressing app links uses WebKit's allow-without-app-links policy", .timeLimit(.minutes(1)))
    func whenAppLinksAreDisabledThenWebKitPolicyAllowsWithoutAppLinks() {
        let decision = TabNavigationDecision.allow(appLinks: .disabled)

        #expect(decision.webKitPolicy.rawValue == 3)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Cancelling navigation uses WebKit's cancel policy", .timeLimit(.minutes(1)))
    func whenNavigationIsCancelledThenWebKitPolicyIsCancel() {
        #expect(TabNavigationDecision.cancel.webKitPolicy == .cancel)
    }
}

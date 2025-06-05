//
//  MockSubscriptionUIHandling.swift
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
@testable import Subscription
import UserScript
@testable import DuckDuckGo_Privacy_Browser

class MockSubscriptionUIHandling: SubscriptionUIHandling {

    init() {}

    func show(alertType: DuckDuckGo_Privacy_Browser.SubscriptionAlertType, text: String?) async -> NSApplication.ModalResponse {
        return NSApplication.ModalResponse(0)
    }

    func presentProgressViewController(withTitle: String) {
    }

    func dismissProgressViewController() {
    }

    func updateProgressViewController(title: String) {
    }

    func presentSubscriptionAccessViewController(handler: any SubscriptionAccessActionHandling, message: WKScriptMessage) {
    }

    func dismissProgressViewAndShow(alertType: SubscriptionAlertType, text: String?) async -> NSApplication.ModalResponse {
        return .cancel
    }

    func showTab(with content: TabContent) {
    }

}

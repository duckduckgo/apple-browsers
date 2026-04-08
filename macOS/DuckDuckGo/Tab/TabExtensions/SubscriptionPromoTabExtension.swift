//
//  SubscriptionPromoTabExtension.swift
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

import Foundation

final class SubscriptionPromoTabExtension: TabExtension {

    private(set) var hasEvaluated = false
    private(set) var shouldShowPromo = false
    private(set) var forceDismissed = false

    func markEvaluated(shouldShowPromo: Bool) {
        hasEvaluated = true
        self.shouldShowPromo = shouldShowPromo
    }

    func markForceDismissed() {
        forceDismissed = true
    }
}

protocol SubscriptionPromoTabProtocol: AnyObject {
    var hasEvaluated: Bool { get }
    var shouldShowPromo: Bool { get }
    var forceDismissed: Bool { get }

    func markEvaluated(shouldShowPromo: Bool)
    func markForceDismissed()
}

extension SubscriptionPromoTabExtension: SubscriptionPromoTabProtocol {
    func getPublicProtocol() -> SubscriptionPromoTabProtocol { self }
}

extension TabExtensions {
    var subscriptionPromo: SubscriptionPromoTabProtocol? {
        resolve(SubscriptionPromoTabExtension.self)
    }
}

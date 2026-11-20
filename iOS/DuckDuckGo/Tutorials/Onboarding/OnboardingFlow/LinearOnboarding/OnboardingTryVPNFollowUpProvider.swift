//
//  OnboardingTryVPNFollowUpProvider.swift
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

import Foundation
import Subscription

/// What the step after Try VPN needs from the subscription and the VPN.
@MainActor
protocol OnboardingTryVPNFollowUpProviding: AnyObject {
    /// Whether the user's subscription includes the VPN, or `nil` until a check finishes.
    var hasVPNAccess: Bool? { get }

    /// Checks the subscription again, replacing any check that's still running.
    func refreshVPNAccess() async

    /// Drops a running check. With no answer yet, the user has no VPN access.
    func cancelVPNAccessCheck()
}

@MainActor
final class OnboardingTryVPNFollowUpProvider: OnboardingTryVPNFollowUpProviding {

    private(set) var hasVPNAccess: Bool?
    private let checkVPNAccess: @MainActor () async -> Bool
    private var vpnAccessCheck: Task<Void, Never>?

    convenience init(subscriptionManager: any SubscriptionManager) {
        self.init {
            (try? await subscriptionManager.isFeatureEnabled(.networkProtection)) ?? false
        }
    }

    init(checkVPNAccess: @escaping @MainActor () async -> Bool) {
        self.checkVPNAccess = checkVPNAccess
    }

    func refreshVPNAccess() async {
        vpnAccessCheck?.cancel()
        let check = Task { [weak self, checkVPNAccess] in
            let hasVPNAccess = await checkVPNAccess()
            guard !Task.isCancelled else { return }
            self?.hasVPNAccess = hasVPNAccess
        }
        vpnAccessCheck = check
        await check.value
    }

    func cancelVPNAccessCheck() {
        vpnAccessCheck?.cancel()
        vpnAccessCheck = nil
        hasVPNAccess = hasVPNAccess ?? false
    }

}

//
//  MockFeatureGatekeeper.swift
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

import Combine
import NetworkProtectionUI
@testable import DuckDuckGo_Privacy_Browser

struct MockVPNFeatureGatekeeper: VPNFeatureGatekeeper {

    var isInstalled: Bool
    var onboardStatusPublisher: AnyPublisher<NetworkProtectionUI.OnboardingStatus, Never>

    private var canStartVPNOverride: Bool
    private var isVPNVisibleOverride: Bool

    init(canStartVPN: Bool,
         isInstalled: Bool,
         isVPNVisible: Bool,
         onboardStatusPublisher: AnyPublisher<NetworkProtectionUI.OnboardingStatus, Never>) {

        canStartVPNOverride = canStartVPN
        self.isInstalled = isInstalled
        isVPNVisibleOverride = isVPNVisible
        self.onboardStatusPublisher = onboardStatusPublisher
    }

    func canStartVPN() async throws -> Bool {
        canStartVPNOverride
    }

    func isVPNVisible() -> Bool {
        isVPNVisibleOverride
    }
}

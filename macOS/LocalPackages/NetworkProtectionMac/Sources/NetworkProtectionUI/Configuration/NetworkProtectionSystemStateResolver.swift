//
//  NetworkProtectionSystemStateResolver.swift
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

import SystemExtensionManager

public enum NetworkProtectionVPNConfigurationState: CaseIterable {
    case installedAndEnabled
    case installedButDisabled
    case missingOrInvalid
}

public enum NetworkProtectionSystemStateResolver {

    public static func resolvedOnboardingStatus(usesSystemExtension: Bool,
                                                systemExtensionState: SystemExtensionActivationState,
                                                vpnConfigurationState: NetworkProtectionVPNConfigurationState,
                                                existingStatus: OnboardingStatus) -> OnboardingStatus {

        if usesSystemExtension {
            switch systemExtensionState {
            case .enabled:
                return resolvedOnboardingStatus(for: vpnConfigurationState)
            case .awaitingUserApproval,
                    .disabled,
                    .uninstalling,
                    .notInstalled:
                return .isOnboarding(step: .userNeedsToAllowExtension)
            case .unknown:
                return existingStatus
            }
        }

        return resolvedOnboardingStatus(for: vpnConfigurationState)
    }

    private static func resolvedOnboardingStatus(for vpnConfigurationState: NetworkProtectionVPNConfigurationState) -> OnboardingStatus {
        switch vpnConfigurationState {
        case .installedAndEnabled:
            return .completed
        case .installedButDisabled,
                .missingOrInvalid:
            return .isOnboarding(step: .userNeedsToAllowVPNConfiguration)
        }
    }

    public static func shouldContinueStartingTunnel(afterSystemExtensionActivation onboardingStatus: OnboardingStatus) -> Bool {
        onboardingStatus != .isOnboarding(step: .userNeedsToAllowExtension)
    }
}

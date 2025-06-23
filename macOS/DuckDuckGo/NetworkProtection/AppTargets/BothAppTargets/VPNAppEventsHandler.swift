//
//  VPNAppEventsHandler.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import Combine
import Common
import FeatureFlags
import Foundation
import LoginItems
import VPN
import NetworkProtectionUI
import NetworkProtectionIPC
import NetworkExtension
import PixelKit
import Subscription

/// Implements the sequence of steps that the VPN needs to execute when the App starts up.
///
final class VPNAppEventsHandler {

    typealias FeatureFlagOverridesPublisher = AnyPublisher<(FeatureFlag, Bool), Never>

    // MARK: - Feature Gatekeeping

    private var cancellables = Set<AnyCancellable>()
    private let defaults: UserDefaults
    private let featureGatekeeper: VPNFeatureGatekeeper
    private let ipcClient: VPNControllerXPCClient
    private let loginItemsManager: LoginItemsManaging
    private let pixelKit: PixelKit?

    // MARK: - Initializers

    init(featureGatekeeper: VPNFeatureGatekeeper,
         featureFlagOverridesPublisher: FeatureFlagOverridesPublisher,
         loginItemsManager: LoginItemsManaging,
         ipcClient: VPNControllerXPCClient = .shared,
         defaults: UserDefaults = .netP,
         pixelKit: PixelKit? = .shared) {

        self.defaults = defaults
        self.featureGatekeeper = featureGatekeeper
        self.ipcClient = ipcClient
        self.loginItemsManager = loginItemsManager
        self.pixelKit = pixelKit

        subscribeToFeatureFlagOverrideChanges(featureFlagOverridesPublisher)
    }

    /// Call this method when the app finishes launching, to run the startup logic for NetP.
    ///
    func applicationDidFinishLaunching() {
        loginItemsControlCheckpoint(canRestart: true)
    }

    func applicationDidBecomeActive() {
        loginItemsControlCheckpoint(canRestart: false)
    }

    // MARK: - Login Item Control Checkpoints

    private enum LoginItemsControlCheckpointPixel: PixelKitEventV2 {
        case cannotStopVPN(_ error: Error)

        var name: String {
            switch self {
            case .cannotStopVPN:
                return "vpn_browser_login_items_control_checkpoint_cannot_stop_vpn"
            }
        }

        var error: (any Error)? {
            switch self {
            case .cannotStopVPN(let error):
                return error
            }
        }

        var parameters: [String : String]? {
            nil
        }
    }

    /// Checks whether the VNP login items need to be disabled
    ///
    private func loginItemsControlCheckpoint(canRestart: Bool) {
        Task { @MainActor [loginItemsManager] in
            switch try? await featureGatekeeper.canStartVPN() {
            case .some(true) where loginItemsManager.isAnyEnabled(LoginItemsManager.vpnLoginItems):
                if canRestart {
                    restartLoginItem(using: loginItemsManager)
                }
            case .some(false) where loginItemsManager.isAnyInstalled(LoginItemsManager.vpnLoginItems):
                Task {
                    ipcClient.stop { error in
                        if let error {
                            self.pixelKit?.fire(LoginItemsControlCheckpointPixel.cannotStopVPN(error))
                        }
                    }
                    try await Task.sleep(interval: .seconds(2))
                    self.disableLoginItem(using: loginItemsManager)
                }
            default:
                break
            }
        }
    }

    // MARK: - Managing the VPN Login Items

    private func disableLoginItem(using loginItemsManager: LoginItemsManaging) {
        loginItemsManager.disableLoginItems(LoginItemsManager.vpnLoginItems)
    }

    private func restartLoginItem(using loginItemsManager: LoginItemsManaging) {
        loginItemsManager.restartLoginItems(LoginItemsManager.vpnLoginItems)
    }

    // MARK: - Feature Flag Overriding

    private func subscribeToFeatureFlagOverrideChanges(
        _ featureFlagOverridesPublisher: FeatureFlagOverridesPublisher) {

            featureFlagOverridesPublisher
                .filter { flag, _ in
                    flag == .networkProtectionAppStoreSysex
                }.map { _, enabled in
                    enabled
                }.sink { [defaults] enabled in
                    if enabled
                        && defaults.networkProtectionOnboardingStatus == .isOnboarding(step: .userNeedsToAllowVPNConfiguration) {

                        defaults.networkProtectionOnboardingStatus = .isOnboarding(step: .userNeedsToAllowExtension)
                    } else if !enabled && defaults.networkProtectionOnboardingStatus == .isOnboarding(step: .userNeedsToAllowExtension) {

                        defaults.networkProtectionOnboardingStatus = .isOnboarding(step: .userNeedsToAllowVPNConfiguration)
                    }
                }
                .store(in: &cancellables)
    }
}

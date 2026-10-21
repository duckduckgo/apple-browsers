//
//  NetworkExtensionController.swift
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

import PrivacyConfig
import Foundation
import NetworkExtension
import VPN
import NetworkProtectionUI
import SystemExtensionManager
import SystemExtensions

/// The VPN's network extension session object.
///
/// Through this class the app that owns the VPN can interact with the network extension.
///
final class NetworkExtensionController {

    private let featureFlagger: FeatureFlagger
    private let systemExtensionManager: SystemExtensionManager
    private let defaults: UserDefaults

    init(sysexBundleID: String, featureFlagger: FeatureFlagger, defaults: UserDefaults = .netP) {

        self.defaults = defaults
        self.featureFlagger = featureFlagger
        systemExtensionManager = SystemExtensionManager(extensionBundleID: sysexBundleID)
    }
}

extension NetworkExtensionController {

    func activateSystemExtension(waitingForUserApproval: @escaping () -> Void) async throws {
        do {
            if let extensionVersion = try await systemExtensionManager.activate(waitingForUserApproval: waitingForUserApproval) {

                NetworkProtectionLastVersionRunStore(userDefaults: defaults).lastExtensionVersionRun = extensionVersion
            }

            try await Task.sleep(nanoseconds: 300 * NSEC_PER_MSEC)
        } catch OSSystemExtensionError.requestCanceled {
            // The user cancelled the system extension approval. Surface it as a cancellation so callers
            // treat it as one rather than a system extension activation failure.
            throw CancellationError()
        }
    }

    func deactivateSystemExtension() async throws {
        do {
            try await systemExtensionManager.deactivate()
        } catch OSSystemExtensionError.extensionNotFound {
            // This is an intentional no-op to silence this type of error
            // since on deactivation this is ok.
        } catch {
            throw error
        }
    }

    func openSystemExtensionSettings() {
        systemExtensionManager.openSystemExtensionSettings()
    }

    func systemExtensionActivationState() async -> SystemExtensionActivationState {
        await systemExtensionManager.activationState()
    }

    @available(macOS 15.1, *)
    func makeSystemExtensionActivationStateObserver(onStateChange: @escaping () -> Void) -> SystemExtensionActivationStateObserver {
        systemExtensionManager.makeActivationStateObserver(onStateChange: onStateChange)
    }

}

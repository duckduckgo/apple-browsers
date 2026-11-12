//
//  VPNSignedOutRemover.swift
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
import os.log
import Subscription
import VPN

/// Stops and removes the installed VPN when the user is signed out.
struct VPNSignedOutRemover {

    private let subscriptionManager: any SubscriptionManager
    private let isVPNInstalled: () async -> Bool
    private let stopAndRemoveVPN: () async -> Void

    /// - Parameters:
    ///   - subscriptionManager: Provides the stored token, restoring a missing one from the backup.
    ///   - isVPNInstalled: Returns whether a VPN configuration is installed.
    ///   - stopAndRemoveVPN: Stops the tunnel and removes the VPN configuration.
    init(subscriptionManager: any SubscriptionManager,
         isVPNInstalled: @escaping () async -> Bool,
         stopAndRemoveVPN: @escaping () async -> Void) {
        self.subscriptionManager = subscriptionManager
        self.isVPNInstalled = isVPNInstalled
        self.stopAndRemoveVPN = stopAndRemoveVPN
    }

    /// Removes the installed VPN when no token is stored and none can be restored from the backup.
    /// Keeps the VPN when a token is stored, when one is restored, and when the stored token can't be read.
    func removeVPNIfSignedOut() async {
        do {
            // `.local` reads the stored token without any network call. When none is stored, it waits for the
            // restore from the backup, so a token that is being restored doesn't remove the VPN.
            // Not `.localValid`: it refreshes an expired access token, and a rejected refresh runs the token
            // recovery and can sign the user out. That is too much to run each time the app becomes active.
            _ = try await subscriptionManager.getTokenContainer(policy: .local)
            Logger.networkProtection.log("Signed-out VPN check: a token is stored or was restored, keeping the VPN")
        } catch SubscriptionManagerError.noTokenAvailable {
            // No token is stored and the backup restore didn't produce one: the user is signed out
            guard await isVPNInstalled() else {
                Logger.networkProtection.log("Signed-out VPN check: no token available and no VPN installed, nothing to remove")
                return
            }
            Logger.networkProtection.log("Signed-out VPN check: no token available, stopping and removing the VPN")
            await stopAndRemoveVPN()
        } catch {
            // The stored token couldn't be read, for example while the keychain is locked: it may still exist,
            // so keep the VPN
            Logger.networkProtection.error("Signed-out VPN check: the token couldn't be read, keeping the VPN: \(String(describing: error), privacy: .public)")
        }
    }
}

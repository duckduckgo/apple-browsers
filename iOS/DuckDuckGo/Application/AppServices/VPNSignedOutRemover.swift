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
import Subscription

/// Stops and removes the installed VPN when the user is signed out.
struct VPNSignedOutRemover {

    private let subscriptionManager: any SubscriptionManager
    private let isVPNInstalled: () async -> Bool
    private let stopAndRemoveVPN: () async -> Void

    /// - Parameters:
    ///   - subscriptionManager: Reports whether the user is signed in, and restores a missing token from the backup.
    ///   - isVPNInstalled: Returns whether a VPN configuration is installed.
    ///   - stopAndRemoveVPN: Stops the tunnel and removes the VPN configuration.
    init(subscriptionManager: any SubscriptionManager,
         isVPNInstalled: @escaping () async -> Bool,
         stopAndRemoveVPN: @escaping () async -> Void) {
        self.subscriptionManager = subscriptionManager
        self.isVPNInstalled = isVPNInstalled
        self.stopAndRemoveVPN = stopAndRemoveVPN
    }

    /// Removes the installed VPN when the user is signed out.
    /// When the user appears signed out, waits for `SubscriptionManager.restoreMissingTokenIfPossible()` first,
    /// and keeps the VPN when the restore signs the user back in.
    func removeVPNIfSignedOut() async {
        guard !subscriptionManager.isUserAuthenticated else { return }

        await subscriptionManager.restoreMissingTokenIfPossible()

        guard !subscriptionManager.isUserAuthenticated, await isVPNInstalled() else { return }
        await stopAndRemoveVPN()
    }
}

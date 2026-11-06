//
//  DataBrokerProtectionSubscriptionEventHandler.swift
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

import Combine
import Foundation
import Subscription
import DataBrokerProtection_macOS
import DataBrokerProtectionCore
import PixelKit
import Common
import FoundationExtensions
import Networking
import os.log

final class DataBrokerProtectionSubscriptionEventHandler {

    private let authenticationManager: DataBrokerProtectionAuthenticationManaging
    private let featureDisabler: DataBrokerProtectionFeatureDisabling
    private let pixelHandler: EventMapping<DataBrokerProtectionMacOSPixels>
    private var cancellables = Set<AnyCancellable>()

    /// - Parameters:
    ///   - featureDisabler: Disables PIR and deletes its data.
    ///   - authenticationManager: Checks the current token's PIR entitlement when the entitlements change.
    ///   - pixelHandler: Receives the entitlement check pixels.
    init(featureDisabler: DataBrokerProtectionFeatureDisabling,
         authenticationManager: DataBrokerProtectionAuthenticationManaging,
         pixelHandler: EventMapping<DataBrokerProtectionMacOSPixels>) {
        self.featureDisabler = featureDisabler
        self.authenticationManager = authenticationManager
        self.pixelHandler = pixelHandler
    }

    func registerForSubscriptionAccountManagerEvents() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleAccountDidSignOut),
                                               name: .accountDidSignOut,
                                               object: nil)

        NotificationCenter.default
            .publisher(for: .entitlementsDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.entitlementsDidChange(notification)
            }
            .store(in: &cancellables)
    }

    /// Disables PIR and deletes its data.
    @objc func handleAccountDidSignOut() {
        featureDisabler.disableAndDelete()
    }

    private func entitlementsDidChange(_ notification: Notification) {
        Task {
            guard let userInfo = notification.userInfo,
                  let payload = EntitlementsDidChangePayload(notificationUserInfo: userInfo) else {
                assertionFailure("Missing entitlements payload")
                Logger.dataBrokerProtection.fault("Missing entitlements payload")
                return
            }
            let hasEntitlements = payload.entitlements.contains(.dataBrokerProtection)
            await entitlementsDidChange(hasEntitlements: hasEntitlements)
        }
    }

    /// Handles a change of the cached entitlements. When they no longer include PIR, PIR is disabled and its data deleted only if
    /// `entitlementStatus()` reports the current token lacks the PIR entitlement. When no token can be read, the data is kept and
    /// `entitlementCheckError` is fired.
    /// - Parameter hasEntitlements: Whether the new cached entitlements include PIR.
    @MainActor
    func entitlementsDidChange(hasEntitlements: Bool) async {
        if hasEntitlements {
            pixelHandler.fire(.entitlementCheckValid)
            return
        }

        switch await authenticationManager.entitlementStatus() {
        case .enabled:
            pixelHandler.fire(.entitlementCheckValid)
        case .disabled:
            pixelHandler.fire(.entitlementCheckInvalid)
            featureDisabler.disableAndDelete()
        case .error:
            Logger.dataBrokerProtection.error("PIR entitlement lost but the current token can't be read, keeping the PIR data")
            pixelHandler.fire(.entitlementCheckError)
        }
    }
}

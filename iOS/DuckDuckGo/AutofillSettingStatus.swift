//
//  AutofillSettingStatus.swift
//  DuckDuckGo
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

import Foundation
import Core
import LocalAuthentication
import UIKit

struct AutofillSettingStatus {

    static var isAutofillEnabledInSettings: Bool {
        setupNotificationObserversIfNeeded()

        let currentStatus = authenticationStatus

        if currentStatus == nil || currentStatus == .otherFailure {
            refreshAuthenticationStatusAsync()
        }

        // Default to .canAuthenticate while waiting for the authentication result
        let effectiveStatus = currentStatus ?? .canAuthenticate

        return appSettings.autofillCredentialsEnabled && (effectiveStatus == .canAuthenticate)
    }
    
    static var isDeviceAuthenticationEnabled: Bool {
        return authenticationStatus != .noPasscodeSet
    }

    private enum AuthenticationStatus {
       case canAuthenticate
       case noPasscodeSet
       case otherFailure
    }

    private static let appSettings = AppDependencyProvider.shared.appSettings

    private static var observersSetUp = false
    private static var authenticationStatus: AuthenticationStatus?

    private static func refreshAuthenticationStatusAsync() {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = checkAuthenticationStatus()
            DispatchQueue.main.async {
                authenticationStatus = result
            }
        }
    }

    private static func checkAuthenticationStatus() -> AuthenticationStatus {
        var error: NSError?

        guard LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            if let error = error as? LAError, error.code == .passcodeNotSet {
                DailyPixel.fire(pixel: .autofillDeviceCapabilityDeviceAuthDisabled)
                return .noPasscodeSet
            }
            return .otherFailure
        }

        return .canAuthenticate
    }

    /// Clears the cached device authentication status when the app goes to the background
    /// to ensure that the next time the app is brought to the foreground, the authentication
    /// status is re-evaluated.
    private static func setupNotificationObserversIfNeeded() {
        guard !observersSetUp else { return }
        observersSetUp = true

        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            authenticationStatus = nil
        }
    }

}

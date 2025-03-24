//
//  UserDefaults+vpnIsUsingSystemExtension.swift
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

extension UserDefaults {

    // Stores whether a System Extension is being used for the VPN.
    //
    // This default field helps the Apps know whether they should show the onboarding
    // prompt that asks users to update to the System Extension to support
    // VPN exclusions.  Since only the main tunnel controller can know whether a
    // system extension is being used, that's likely where this will be set each time
    // the VPN is started.
    //
    // Ref: https://app.asana.com/0/0/1209568433228372
    //
    @objc
    dynamic var vpnIsUsingSystemExtension: Bool {
        get {
            bool(forKey: #keyPath(vpnIsUsingSystemExtension))
        }

        set {
            set(newValue, forKey: #keyPath(vpnIsUsingSystemExtension))
        }
    }

    func resetVPNIsUsingSystemExtension() {
        removeObject(forKey: #keyPath(vpnIsUsingSystemExtension))
    }

    var vpnIsUsingSystemExtensionPublisher: AnyPublisher<Bool, Never> {
        publisher(for: \.vpnIsUsingSystemExtension).eraseToAnyPublisher()
    }
}

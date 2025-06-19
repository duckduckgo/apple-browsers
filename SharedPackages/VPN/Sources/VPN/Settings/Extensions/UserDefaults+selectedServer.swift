//
//  UserDefaults+selectedServer.swift
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
    private var selectedServerKey: String {
        "networkProtectionSettingSelectedServerRawValue"
    }

    @objc
    dynamic var networkProtectionSettingSelectedServerRawValue: String? {
        get {
            value(forKey: selectedServerKey) as? String
        }

        set {
            set(newValue, forKey: selectedServerKey)
        }
    }

    private func selectedServerFromRawValue(_ rawValue: String?) -> VPNSettings.SelectedServer {
        guard let selectedEndpoint = networkProtectionSettingSelectedServerRawValue else {
            return .automatic
        }

        return .endpoint(selectedEndpoint)
    }

    var networkProtectionSettingSelectedServer: VPNSettings.SelectedServer {
        get {
            selectedServerFromRawValue(networkProtectionSettingSelectedServerRawValue)
        }

        set {
            switch newValue {
            case .automatic:
                networkProtectionSettingSelectedServerRawValue = nil
            case .endpoint(let serverName):
                networkProtectionSettingSelectedServerRawValue = serverName
            }
        }
    }

    var networkProtectionSettingSelectedServerPublisher: AnyPublisher<VPNSettings.SelectedServer, Never> {
        let selectedServerFromRawValue = self.selectedServerFromRawValue

        return publisher(for: \.networkProtectionSettingSelectedServerRawValue).map { serverName in
            selectedServerFromRawValue(serverName)
        }.eraseToAnyPublisher()
    }

    func resetNetworkProtectionSettingSelectedServer() {
        networkProtectionSettingSelectedServerRawValue = nil
    }
}

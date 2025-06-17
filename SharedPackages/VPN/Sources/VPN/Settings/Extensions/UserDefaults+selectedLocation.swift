//
//  UserDefaults+selectedLocation.swift
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
    final class StorableLocation: NSObject, Codable {
        let country: String
        let city: String?

        init(country: String, city: String?) {
            self.country = country
            self.city = city
        }
    }

    @objc
    dynamic var networkProtectionSettingSelectedLocationStorageValue: StorableLocation? {
        get {
            guard let data = data(forKey: #keyPath(networkProtectionSettingSelectedLocationStorageValue)) else { return nil }
            do {
                return try JSONDecoder().decode(StorableLocation?.self, from: data)
            } catch {
                assertionFailure("Errored while decoding location")
                return nil
            }
        }

        set {
            do {
                let data = try JSONEncoder().encode(newValue)
                set(data, forKey: #keyPath(networkProtectionSettingSelectedLocationStorageValue))
            } catch {
                assertionFailure("Errored while encoding location")
            }
        }
    }

    private static func selectedLocationFromStorageValue(_ storageValue: StorableLocation?) -> VPNSettings.SelectedLocation {
        guard let storageValue else {
            return .nearest
        }

        // To handle a bug where a UI element's title was set for nearest cities rather than nil
        let city = storageValue.city == "Nearest" ? nil : storageValue.city

        let selectedLocation = NetworkProtectionSelectedLocation(country: storageValue.country, city: city)

        return .location(selectedLocation)
    }

    var networkProtectionSettingSelectedLocation: VPNSettings.SelectedLocation {
        get {
            Self.selectedLocationFromStorageValue(networkProtectionSettingSelectedLocationStorageValue)
        }

        set {
            switch newValue {
            case .nearest:
                networkProtectionSettingSelectedLocationStorageValue = nil
            case .location(let location):
                networkProtectionSettingSelectedLocationStorageValue = StorableLocation(country: location.country, city: location.city)
            }
        }
    }

    var networkProtectionSettingSelectedLocationPublisher: AnyPublisher<VPNSettings.SelectedLocation, Never> {
        return publisher(for: \.networkProtectionSettingSelectedLocationStorageValue)
            .map(Self.selectedLocationFromStorageValue(_:))
            .eraseToAnyPublisher()
    }

    func resetNetworkProtectionSettingSelectedLocation() {
        networkProtectionSettingSelectedLocationStorageValue = nil
    }
}

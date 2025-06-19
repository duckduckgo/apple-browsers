//
//  VPNServerSelectionResolver.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

enum VPNServerSelectionResolverError: Error {
    case countryNotFound
    case fetchingLocationsFailed(Error)
}

protocol VPNServerSelectionResolving {
    func resolvedServerSelectionMethod() async -> NetworkProtectionServerSelectionMethod
}

final class VPNServerSelectionResolver: VPNServerSelectionResolving {
    private let locationListRepository: NetworkProtectionLocationListRepository
    private let vpnSettings: VPNSettings

    init(locationListRepository: NetworkProtectionLocationListRepository, vpnSettings: VPNSettings) {
        self.locationListRepository = locationListRepository
        self.vpnSettings = vpnSettings
    }

    /// Address the case where the prefered location becomes unavailable
    /// We fall back to the country, if a city isn't available, 
    /// or nearest if the country isn't available
    public func resolvedServerSelectionMethod() async -> NetworkProtectionServerSelectionMethod {
        switch currentServerSelectionMethod {
        case .automatic, .preferredServer, .avoidServer, .failureRecovery:
            return currentServerSelectionMethod
        case .preferredLocation(let networkProtectionSelectedLocation):
            do {
                let location = try await resolveSelectionAgainstAvailableLocations(networkProtectionSelectedLocation)
                return .preferredLocation(location)
            } catch let error as VPNServerSelectionResolverError {
                switch error {
                case .countryNotFound:
                    return .automatic
                case .fetchingLocationsFailed:
                    return currentServerSelectionMethod
                }
            } catch {
                return currentServerSelectionMethod
            }
        }
    }

    private func resolveSelectionAgainstAvailableLocations(_ selection: NetworkProtectionSelectedLocation) async throws -> NetworkProtectionSelectedLocation {
        let availableLocations: [NetworkProtectionLocation]
        do {
            availableLocations = try await locationListRepository.fetchLocationList(cachePolicy: .ignoreCache)
        } catch {
            throw VPNServerSelectionResolverError.fetchingLocationsFailed(error)
        }

        let availableCitySelections = availableLocations.flatMap { location in
            location.cities.map { city in  NetworkProtectionSelectedLocation(country: location.country, city: city.name) }
        }

        if availableCitySelections.contains(selection) {
            return selection
        }

        let selectedCountry = NetworkProtectionSelectedLocation(country: selection.country)
        let availableCountrySelections = availableLocations.map { NetworkProtectionSelectedLocation(country: $0.country) }
        guard availableCountrySelections.contains(selectedCountry) else {
            throw VPNServerSelectionResolverError.countryNotFound
        }

        return selectedCountry
    }

    private var currentServerSelectionMethod: NetworkProtectionServerSelectionMethod {
        var serverSelectionMethod: NetworkProtectionServerSelectionMethod

        switch vpnSettings.selectedLocation {
        case .nearest:
            serverSelectionMethod = .automatic
        case .location(let networkProtectionSelectedLocation):
            serverSelectionMethod = .preferredLocation(networkProtectionSelectedLocation)
        }

        switch vpnSettings.selectedServer {
        case .automatic:
            break
        case .endpoint(let string):
            // Selecting a specific server will override locations setting
            // Only available in debug
            serverSelectionMethod = .preferredServer(serverName: string)
        }

        return serverSelectionMethod
    }
}

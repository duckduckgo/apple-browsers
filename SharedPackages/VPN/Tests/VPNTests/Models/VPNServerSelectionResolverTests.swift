//
//  VPNServerSelectionResolverTests.swift
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
import XCTest
@testable import VPN
@testable import VPNTestUtils

final class VPNServerSelectionResolverTests: XCTestCase {
    var resolver: VPNServerSelectionResolver!
    var vpnSettings: VPNSettings!
    var locationListRepository: MockNetworkProtectionLocationListRepository!

    override func setUp() {
        super.setUp()
        locationListRepository = MockNetworkProtectionLocationListRepository()
        vpnSettings = VPNSettings(defaults: UserDefaults(suiteName: self.className)!)
        resolver = VPNServerSelectionResolver(
            locationListRepository: locationListRepository,
            vpnSettings: vpnSettings
        )
    }

    override func tearDown() {
        vpnSettings.resetToDefaults()
        vpnSettings = nil
        resolver = nil
        locationListRepository = nil
        super.tearDown()
    }

    func testResolvedServerSelectionMethod_selectedServer_returnsPreferredServer() async {
        let serverName = "serverName"
        vpnSettings.selectedServer = .endpoint(serverName)
        let result = await resolver.resolvedServerSelectionMethod()
        guard case .preferredServer(let preferredServerName) = result else {
            XCTFail("Expected preferredServer method")
            return
        }
        XCTAssertEqual(preferredServerName, serverName)
    }

    func testResolvedServerSelectionMethod_selectedLocationIsNearest_returnsAutomatic() async {
        vpnSettings.selectedLocation = .nearest
        let result = await resolver.resolvedServerSelectionMethod()
        guard case .automatic = result else {
            XCTFail("Expected automatic method")
            return
        }
    }

    func testResolvedServerSelectionMethod_selectedLocationIsCity_fetchesListIgnoringCache() async {
        vpnSettings.selectedLocation = .location(.init(country: "nl", city: "Rotterdam"))
        _ = await resolver.resolvedServerSelectionMethod()
        XCTAssertTrue(locationListRepository.spyIgnoreCache)
    }

    func testResolvedServerSelectionMethod_selectedLocationIsCity_fetchedLocationsContainThatCity_returnsPreferredCity() async {
        let selectedLocation = NetworkProtectionSelectedLocation(country: "nl", city: "Rotterdam")
        vpnSettings.selectedLocation = .location(selectedLocation)
        locationListRepository.stubFetchLocationList = [
            .testData(country: "us"),
            .testData(
                country: "nl",
                cities: [.testData(name: "Rotterdam")]
            )
        ]
        let result = await resolver.resolvedServerSelectionMethod()
        guard case .preferredLocation(let location) = result else {
            XCTFail("Expected preferredLocation method")
            return
        }
        XCTAssertEqual(location, selectedLocation)
    }

    func testResolvedServerSelectionMethod_selectedLocationIsCity_fetchedLocationsContainThatCountry_butNotCity_returnsPreferredCountryWithNilCity() async {
        let selectedLocation = NetworkProtectionSelectedLocation(country: "nl", city: nil)
        vpnSettings.selectedLocation = .location(selectedLocation)
        locationListRepository.stubFetchLocationList = [
            .testData(country: "us"),
            .testData(
                country: "nl",
                cities: [.testData(name: "Amsterdam")]
            )
        ]
        let result = await resolver.resolvedServerSelectionMethod()
        guard case .preferredLocation(let location) = result else {
            XCTFail("Expected preferredLocation method")
            return
        }
        XCTAssertEqual(location, selectedLocation)
    }

    func testResolvedServerSelectionMethod_selectedLocationIsCity_fetchedLocationsDoesNotContainCountry_returnsAutomatic() async {
        let selectedLocation = NetworkProtectionSelectedLocation(country: "nl", city: nil)
        vpnSettings.selectedLocation = .location(selectedLocation)
        locationListRepository.stubFetchLocationList = [
            .testData(country: "us")
        ]
        let result = await resolver.resolvedServerSelectionMethod()
        guard case .automatic = result else {
            XCTFail("Expected automatic method")
            return
        }
    }

    func testResolvedServerSelectionMethod_overridesAllLocationSelectionMethods_returnsPreferredServer() async {
        let cases: [VPNSettings.SelectedLocation] = [
            .location(.init(country: "nl", city: "Rotterdam")),
            .location(.init(country: "us", city: nil)),
            .nearest
        ]

        for currentSelectedLocation in cases {
            vpnSettings.selectedLocation = currentSelectedLocation
            let selectedServerName = "selectedServer"
            vpnSettings.selectedServer = .endpoint(selectedServerName)
            locationListRepository.stubFetchLocationList = [
                .testData(country: "us"),
                .testData(
                    country: "nl",
                    cities: [.testData(name: "Rotterdam")]
                )
            ]
            let result = await resolver.resolvedServerSelectionMethod()
            guard case .preferredServer(let server) = result else {
                XCTFail("Expected preferredServer method")
                return
            }
            XCTAssertEqual(server, selectedServerName)
        }
    }
}

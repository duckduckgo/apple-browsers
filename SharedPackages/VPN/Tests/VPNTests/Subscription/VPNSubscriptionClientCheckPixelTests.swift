//
//  VPNSubscriptionClientCheckPixelTests.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

final class VPNSubscriptionClientCheckPixelTests: XCTestCase {

    // MARK: - Name Prefix Tests

    func testNamePrefix_appStartup() {
#if os(macOS)
        let pixel = VPNSubscriptionClientCheckPixel.vpnFeatureEnabled(
            isSubscriptionActive: true,
            trigger: .appStartup
        )
        XCTAssertEqual(pixel.namePrefix, "m_mac_vpn_subs_client_check_")
#elseif os(iOS)
        let pixel = VPNSubscriptionClientCheckPixel.vpnFeatureEnabled(
            isSubscriptionActive: true,
            trigger: .appStartup
        )
        XCTAssertEqual(pixel.namePrefix, "m_vpn_subs_client_check_")
#endif
    }

#if os(macOS)
    func testNamePrefix_deviceWake() {
        let pixel = VPNSubscriptionClientCheckPixel.vpnFeatureEnabled(
            isSubscriptionActive: true,
            trigger: .deviceWake
        )
        XCTAssertEqual(pixel.namePrefix, "m_mac_vpn_subs_client_check_on_wake_")
    }
#elseif os(iOS)
    func testNamePrefix_appForegrounded() {
        let pixel = VPNSubscriptionClientCheckPixel.vpnFeatureEnabled(
            isSubscriptionActive: true,
            trigger: .appForegrounded
        )
        XCTAssertEqual(pixel.namePrefix, "m_vpn_subs_client_check_on_foreground_")
    }
#endif

    // MARK: - Pixel Name Tests

    func testPixelName_vpnFeatureEnabled() {
        let pixel = VPNSubscriptionClientCheckPixel.vpnFeatureEnabled(
            isSubscriptionActive: true,
            trigger: .appStartup
        )
        XCTAssertEqual(pixel.name, "vpn_feature_enabled")
    }

    func testPixelName_vpnFeatureDisabled() {
        let pixel = VPNSubscriptionClientCheckPixel.vpnFeatureDisabled(
            isSubscriptionActive: false,
            trigger: .appStartup
        )
        XCTAssertEqual(pixel.name, "vpn_feature_disabled")
    }

    func testPixelName_failed() {
        let error = NSError(domain: "TestError", code: 1, userInfo: nil)
        let pixel = VPNSubscriptionClientCheckPixel.failed(
            isSubscriptionActive: true,
            trigger: .appStartup,
            error: error
        )
        XCTAssertEqual(pixel.name, "failed")
    }

    // MARK: - Parameters Tests

    func testParameters_activeSubscriptionAuthV2() {
        let pixel = VPNSubscriptionClientCheckPixel.vpnFeatureEnabled(
            isSubscriptionActive: true,
            trigger: .appStartup
        )

        let parameters = pixel.parameters
        XCTAssertNotNil(parameters)
        XCTAssertEqual(parameters?["vpnSubscriptionActive"], "true")
        XCTAssertEqual(parameters?["vpnAuthVersion"], "v2")
    }

    func testParameters_inactiveSubscription() {
        let pixel = VPNSubscriptionClientCheckPixel.vpnFeatureDisabled(
            isSubscriptionActive: false,
            trigger: .appStartup
        )

        let parameters = pixel.parameters
        XCTAssertNotNil(parameters)
        XCTAssertEqual(parameters?["vpnSubscriptionActive"], "false")
        XCTAssertEqual(parameters?["vpnAuthVersion"], "v2")
    }

    func testParameters_nilSubscription() {
        let pixel = VPNSubscriptionClientCheckPixel.vpnFeatureEnabled(
            isSubscriptionActive: nil,
            trigger: .appStartup
        )

        let parameters = pixel.parameters
        XCTAssertNotNil(parameters)
        XCTAssertEqual(parameters?["vpnSubscriptionActive"], "no_subscription")
        XCTAssertEqual(parameters?["vpnAuthVersion"], "v2")
    }

    func testParameters_failedPixel() {
        let error = NSError(domain: "TestError", code: 1, userInfo: nil)
        let pixel = VPNSubscriptionClientCheckPixel.failed(
            isSubscriptionActive: true,
            trigger: .appStartup,
            error: error
        )

        let parameters = pixel.parameters
        XCTAssertNotNil(parameters)

        XCTAssertEqual(parameters?["vpnSubscriptionActive"], "true")
        XCTAssertEqual(parameters?["vpnAuthVersion"], "v2")
    }

    // MARK: - Error Handling Tests

    func testError_successfulPixels() {
        let enabledPixel = VPNSubscriptionClientCheckPixel.vpnFeatureEnabled(
            isSubscriptionActive: true,
            trigger: .appStartup
        )
        XCTAssertNil(enabledPixel.error)

        let disabledPixel = VPNSubscriptionClientCheckPixel.vpnFeatureDisabled(
            isSubscriptionActive: false,
            trigger: .appStartup
        )
        XCTAssertNil(disabledPixel.error)
    }

    func testError_failedPixel() {
        let testError = NSError(domain: "TestDomain", code: 42, userInfo: [NSLocalizedDescriptionKey: "Test error"])
        let pixel = VPNSubscriptionClientCheckPixel.failed(
            isSubscriptionActive: nil,
            trigger: .appStartup,
            error: testError
        )

        XCTAssertNotNil(pixel.error)
        XCTAssertEqual((pixel.error as NSError?)?.domain, "TestDomain")
        XCTAssertEqual((pixel.error as NSError?)?.code, 42)
        XCTAssertEqual((pixel.error as NSError?)?.localizedDescription, "Test error")
    }

    // MARK: - Integration Tests

    func testFullPixelName_appStartupEnabled() {
#if os(macOS)
        let expectedPrefix = "m_mac_vpn_subs_client_check_"
#elseif os(iOS)
        let expectedPrefix = "m_vpn_subs_client_check_"
#endif

        let pixel = VPNSubscriptionClientCheckPixel.vpnFeatureEnabled(
            isSubscriptionActive: true,
            trigger: .appStartup
        )

        let fullName = pixel.namePrefix + pixel.name
        XCTAssertEqual(fullName, expectedPrefix + "vpn_feature_enabled")
    }

#if os(macOS)
    func testFullPixelName_deviceWakeFailed() {
        let error = NSError(domain: "NetworkError", code: 500, userInfo: nil)
        let pixel = VPNSubscriptionClientCheckPixel.failed(
            isSubscriptionActive: nil,
            trigger: .deviceWake,
            error: error
        )

        let fullName = pixel.namePrefix + pixel.name
        XCTAssertEqual(fullName, "m_mac_vpn_subs_client_check_on_wake_failed")
    }
#elseif os(iOS)
    func testFullPixelName_appForegroundedFailed() {
        let error = NSError(domain: "NetworkError", code: 500, userInfo: nil)
        let pixel = VPNSubscriptionClientCheckPixel.failed(
            isSubscriptionActive: nil,
            trigger: .appForegrounded,
            error: error
        )

        let fullName = pixel.namePrefix + pixel.name
        XCTAssertEqual(fullName, "m_vpn_subs_client_check_on_foreground_failed")
    }
#endif
}

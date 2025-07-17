//
//  VPNSubscriptionStatusPixelTests.swift
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

final class VPNSubscriptionStatusPixelTests: XCTestCase {

    // MARK: - Test Helpers

    private class TestSourceObject {
        let name = "TestSourceObject"
    }

    private class AnotherTestObject {
        let value = 42
    }

    // MARK: - Name Prefix Tests

    func testNamePrefix_platformSpecific() {
#if os(macOS)
        let pixel = VPNSubscriptionStatusPixel.signedIn(
            isSubscriptionActive: true,
            isAuthV2Enabled: true,
            sourceObject: nil
        )
        XCTAssertEqual(pixel.namePrefix, "m_mac_vpn_subs_notification_")
#elseif os(iOS)
        let pixel = VPNSubscriptionStatusPixel.signedIn(
            isSubscriptionActive: true,
            isAuthV2Enabled: true,
            sourceObject: nil
        )
        XCTAssertEqual(pixel.namePrefix, "m_vpn_subs_notification_")
#endif
    }

    // MARK: - Pixel Name Tests

    func testPixelName_signedIn() {
        let pixel = VPNSubscriptionStatusPixel.signedIn(
            isSubscriptionActive: true,
            isAuthV2Enabled: true,
            sourceObject: nil
        )
        XCTAssertEqual(pixel.name, "signed_in")
    }

    func testPixelName_signedOut() {
        let pixel = VPNSubscriptionStatusPixel.signedOut(
            isSubscriptionActive: false,
            isAuthV2Enabled: true,
            sourceObject: nil
        )
        XCTAssertEqual(pixel.name, "signed_out")
    }

    func testPixelName_vpnFeatureEnabled() {
        let pixel = VPNSubscriptionStatusPixel.vpnFeatureEnabled(
            isSubscriptionActive: true,
            isAuthV2Enabled: true,
            sourceObject: nil
        )
        XCTAssertEqual(pixel.name, "vpn_feature_enabled")
    }

    func testPixelName_vpnFeatureDisabled() {
        let pixel = VPNSubscriptionStatusPixel.vpnFeatureDisabled(
            isSubscriptionActive: false,
            isAuthV2Enabled: true,
            sourceObject: nil
        )
        XCTAssertEqual(pixel.name, "vpn_feature_disabled")
    }

    // MARK: - Parameters Tests

    func testParameters_activeSubscriptionAuthV2WithSourceObject() {
        let sourceObject = TestSourceObject()
        let pixel = VPNSubscriptionStatusPixel.vpnFeatureEnabled(
            isSubscriptionActive: true,
            isAuthV2Enabled: true,
            sourceObject: sourceObject
        )

        let parameters = pixel.parameters
        XCTAssertNotNil(parameters)
        XCTAssertEqual(parameters?["isSubscriptionActive"], "true")
        XCTAssertEqual(parameters?["authVersion"], "v2")
        XCTAssertEqual(parameters?["notificationObjectClass"], "TestSourceObject")
    }

    func testParameters_activeSubscriptionAuthV1() {
        let pixel = VPNSubscriptionStatusPixel.signedIn(
            isSubscriptionActive: true,
            isAuthV2Enabled: false,
            sourceObject: nil
        )

        let parameters = pixel.parameters
        XCTAssertNotNil(parameters)
        XCTAssertEqual(parameters?["isSubscriptionActive"], "true")
        XCTAssertEqual(parameters?["authVersion"], "v1")
        XCTAssertEqual(parameters?["notificationObjectClass"], "nil")
    }

    func testParameters_inactiveSubscription() {
        let sourceObject = AnotherTestObject()
        let pixel = VPNSubscriptionStatusPixel.vpnFeatureDisabled(
            isSubscriptionActive: false,
            isAuthV2Enabled: true,
            sourceObject: sourceObject
        )

        let parameters = pixel.parameters
        XCTAssertNotNil(parameters)
        XCTAssertEqual(parameters?["isSubscriptionActive"], "false")
        XCTAssertEqual(parameters?["authVersion"], "v2")
        XCTAssertEqual(parameters?["notificationObjectClass"], "AnotherTestObject")
    }

    func testParameters_nilSubscription() {
        let pixel = VPNSubscriptionStatusPixel.signedOut(
            isSubscriptionActive: nil,
            isAuthV2Enabled: true,
            sourceObject: NSString(string: "test")
        )

        let parameters = pixel.parameters
        XCTAssertNotNil(parameters)
        XCTAssertEqual(parameters?["isSubscriptionActive"], "no_subscription")
        XCTAssertEqual(parameters?["authVersion"], "v2")
        // NSString implementation can vary between OS versions (__NSCFConstantString vs NSTaggedPointerString)
        let objectClass = parameters?["notificationObjectClass"]
        XCTAssertTrue(objectClass?.contains("String") == true, "Expected string class name, got: \(objectClass ?? "nil")")
    }

    // MARK: - Source Class Tests

    func testSourceClass_nilObject() {
        let result = VPNSubscriptionStatusPixel.sourceClass(from: nil)
        XCTAssertEqual(result, "nil")
    }

    func testSourceClass_regularObject() {
        let testObject = TestSourceObject()
        let result = VPNSubscriptionStatusPixel.sourceClass(from: testObject)
        XCTAssertEqual(result, "TestSourceObject")
    }

    func testSourceClass_nsStringObject() {
        let nsString = NSString(string: "test")
        let result = VPNSubscriptionStatusPixel.sourceClass(from: nsString)
        // NSString implementation can vary between OS versions (__NSCFConstantString vs NSTaggedPointerString)
        XCTAssertTrue(result.contains("String"), "Expected string class name, got: \(result)")
    }

    func testSourceClass_arrayObject() {
        let array = [1, 2, 3]
        let result = VPNSubscriptionStatusPixel.sourceClass(from: array)
        XCTAssertEqual(result, "Array<Int>")
    }

    func testSourceClass_variousObjectTypes() {
        // Test the general type detection logic with various object types
        let nsString = NSString(string: "test")
        let array = [1, 2, 3]
        let testObj = TestSourceObject()
        let anotherTestObj = AnotherTestObject()

        // Test NSString (implementation can vary between OS versions)
        let stringResult = VPNSubscriptionStatusPixel.sourceClass(from: nsString)
        XCTAssertTrue(stringResult.contains("String"), "Expected string class name, got: \(stringResult)")

        // Test Array
        let arrayResult = VPNSubscriptionStatusPixel.sourceClass(from: array)
        XCTAssertEqual(arrayResult, "Array<Int>")

        // Test custom objects
        let testObjResult = VPNSubscriptionStatusPixel.sourceClass(from: testObj)
        XCTAssertEqual(testObjResult, "TestSourceObject")

        let anotherTestObjResult = VPNSubscriptionStatusPixel.sourceClass(from: anotherTestObj)
        XCTAssertEqual(anotherTestObjResult, "AnotherTestObject")
    }

    // MARK: - Error Tests

    func testError_alwaysNil() {
        let pixels = [
            VPNSubscriptionStatusPixel.signedIn(isSubscriptionActive: true, isAuthV2Enabled: true, sourceObject: nil),
            VPNSubscriptionStatusPixel.signedOut(isSubscriptionActive: false, isAuthV2Enabled: false, sourceObject: nil),
            VPNSubscriptionStatusPixel.vpnFeatureEnabled(isSubscriptionActive: true, isAuthV2Enabled: true, sourceObject: nil),
            VPNSubscriptionStatusPixel.vpnFeatureDisabled(isSubscriptionActive: false, isAuthV2Enabled: false, sourceObject: nil)
        ]

        for pixel in pixels {
            XCTAssertNil(pixel.error, "Notification pixels should never have errors")
        }
    }

    // MARK: - Integration Tests

    func testFullPixelName_signedIn() {
#if os(macOS)
        let expectedPrefix = "m_mac_vpn_subs_notification_"
#elseif os(iOS)
        let expectedPrefix = "m_vpn_subs_notification_"
#endif

        let pixel = VPNSubscriptionStatusPixel.signedIn(
            isSubscriptionActive: true,
            isAuthV2Enabled: true,
            sourceObject: nil
        )

        let fullName = pixel.namePrefix + pixel.name
        XCTAssertEqual(fullName, expectedPrefix + "signed_in")
    }

    func testFullPixelName_vpnFeatureDisabled() {
#if os(macOS)
        let expectedPrefix = "m_mac_vpn_subs_notification_"
#elseif os(iOS)
        let expectedPrefix = "m_vpn_subs_notification_"
#endif

        let pixel = VPNSubscriptionStatusPixel.vpnFeatureDisabled(
            isSubscriptionActive: false,
            isAuthV2Enabled: false,
            sourceObject: TestSourceObject()
        )

        let fullName = pixel.namePrefix + pixel.name
        XCTAssertEqual(fullName, expectedPrefix + "vpn_feature_disabled")
    }

    // MARK: - Edge Cases and Comprehensive Testing

    func testParameters_allPixelTypesWithAllCombinations() {
        let subscriptionStates: [Bool?] = [true, false, nil]
        let authVersions: [Bool] = [true, false]
        let sourceObjects: [Any?] = [nil, TestSourceObject(), NSString(string: "test")]

        let pixelFactories: [(Bool?, Bool, Any?) -> VPNSubscriptionStatusPixel] = [
            VPNSubscriptionStatusPixel.signedIn,
            VPNSubscriptionStatusPixel.signedOut,
            VPNSubscriptionStatusPixel.vpnFeatureEnabled,
            VPNSubscriptionStatusPixel.vpnFeatureDisabled
        ]

        for factory in pixelFactories {
            for subscriptionState in subscriptionStates {
                for authV2 in authVersions {
                    for sourceObject in sourceObjects {
                        let pixel = factory(subscriptionState, authV2, sourceObject)

                        // Verify parameters are always present
                        let parameters = pixel.parameters
                        XCTAssertNotNil(parameters, "Parameters should never be nil")
                        XCTAssertNotNil(parameters?["isSubscriptionActive"], "isSubscriptionActive should always be present")
                        XCTAssertNotNil(parameters?["authVersion"], "authVersion should always be present")
                        XCTAssertNotNil(parameters?["notificationObjectClass"], "notificationObjectClass should always be present")

                        // Verify specific values
                        let expectedSubscriptionValue = subscriptionState != nil ? String(subscriptionState!) : "no_subscription"
                        XCTAssertEqual(parameters?["isSubscriptionActive"], expectedSubscriptionValue)
                        XCTAssertEqual(parameters?["authVersion"], authV2 ? "v2" : "v1")

                        // Verify source object class
                        if sourceObject == nil {
                            XCTAssertEqual(parameters?["notificationObjectClass"], "nil")
                        } else {
                            XCTAssertNotEqual(parameters?["notificationObjectClass"], "nil")
                        }
                    }
                }
            }
        }
    }

    func testSourceClass_customObject() {
        // Test with a more complex custom object
        struct CustomStruct {
            let id: String = "test"
        }

        let customStruct = CustomStruct()
        let result = VPNSubscriptionStatusPixel.sourceClass(from: customStruct)
        XCTAssertTrue(result.contains("CustomStruct"), "Should contain struct name")
    }

    func testPixelConsistency_sameParametersAcrossPixelTypes() {
        let sourceObject = TestSourceObject()

        let pixels = [
            VPNSubscriptionStatusPixel.signedIn(isSubscriptionActive: true, isAuthV2Enabled: false, sourceObject: sourceObject),
            VPNSubscriptionStatusPixel.signedOut(isSubscriptionActive: true, isAuthV2Enabled: false, sourceObject: sourceObject),
            VPNSubscriptionStatusPixel.vpnFeatureEnabled(isSubscriptionActive: true, isAuthV2Enabled: false, sourceObject: sourceObject),
            VPNSubscriptionStatusPixel.vpnFeatureDisabled(isSubscriptionActive: true, isAuthV2Enabled: false, sourceObject: sourceObject)
        ]

        // All pixels should have the same parameter structure (keys and values) except for the pixel name
        let firstPixelParams = pixels[0].parameters!
        for pixel in pixels.dropFirst() {
            let params = pixel.parameters!
            XCTAssertEqual(params["isSubscriptionActive"], firstPixelParams["isSubscriptionActive"])
            XCTAssertEqual(params["authVersion"], firstPixelParams["authVersion"])
            XCTAssertEqual(params["notificationObjectClass"], firstPixelParams["notificationObjectClass"])
        }
    }
}

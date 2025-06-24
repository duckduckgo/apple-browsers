//
//  SubscriptionPixelHandlerTests.swift
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

import XCTest
@testable import DuckDuckGo_Privacy_Browser
import PixelKit
import PixelKitTestingUtilities
import Networking
import Subscription

final class SubscriptionPixelHandlerTests: XCTestCase {

    var pixelKit: PixelKitMock!

    override func setUpWithError() throws {
        pixelKit = PixelKitMock()
    }

    override func tearDownWithError() throws {
        pixelKit = nil
    }

    func test_entitlementAdded_firesAddedPixelOnly() {
        let new = [Entitlement(product: .networkProtection)]
        let old: [Entitlement] = []

        pixelKit.expectedFireCalls = [
            .init(pixel: PrivacyProPixel.privacyProEntitlementsAdded(.mainApp) , frequency: .dailyAndCount),
        ]

        AuthV2PixelHandler.sendPixelForEntitlementChange(
            newEntitlement: Set(new),
            previousEntitlements: Set(old),
            source: .mainApp,
            pixelKit: pixelKit
        )

        pixelKit.verifyExpectations()
    }

    func test_entitlementRemoved_firesRemovedPixelOnly() {
        let new: [Entitlement] = []
        let old = [Entitlement(product: .dataBrokerProtection)]

        pixelKit.expectedFireCalls = [
            .init(pixel: PrivacyProPixel.privacyProEntitlementsRemoved(.vpnApp) , frequency: .dailyAndCount),
        ]

        AuthV2PixelHandler.sendPixelForEntitlementChange(
            newEntitlement: Set(new),
            previousEntitlements: Set(old),
            source: .vpnApp,
            pixelKit: pixelKit
        )

        pixelKit.verifyExpectations()
    }

    func test_entitlementsAddedAndRemoved_firesBothPixels() {
        let new = [Entitlement(product: .identityTheftRestoration)]
        let old = [Entitlement(product: .paidAIChat)]

        pixelKit.expectedFireCalls = [
            .init(pixel: PrivacyProPixel.privacyProEntitlementsAdded(.dbp) , frequency: .dailyAndCount),
            .init(pixel: PrivacyProPixel.privacyProEntitlementsRemoved(.dbp) , frequency: .dailyAndCount),
        ]

        AuthV2PixelHandler.sendPixelForEntitlementChange(
            newEntitlement: Set(new),
            previousEntitlements: Set(old),
            source: .dbp,
            pixelKit: pixelKit
        )

        pixelKit.verifyExpectations()
    }

    func test_noEntitlementChange_firesNoPixel() {
        let entitlements = [Entitlement(product: .networkProtection)]

        AuthV2PixelHandler.sendPixelForEntitlementChange(
            newEntitlement: Set(entitlements),
            previousEntitlements: Set(entitlements),
            source: .systemExtension,
            pixelKit: pixelKit
        )

        pixelKit.verifyExpectations()
    }
}

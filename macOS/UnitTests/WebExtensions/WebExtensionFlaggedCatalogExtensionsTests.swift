//
//  WebExtensionFlaggedCatalogExtensionsTests.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

import FeatureFlags_macOS
import PrivacyConfig
import WebExtensions
import XCTest

@testable import DuckDuckGo_Privacy_Browser

@available(macOS 15.4, *)
final class WebExtensionFlaggedCatalogExtensionsTests: XCTestCase {

    private let iCloudPasswordsID = "pejdijmoenmkgeppbflobdenhhabjlaj"

    func testWhenICloudPasswordsFlagIsOff_ThenICloudPasswordsIsDisabled() {
        let featureFlagger = MockFeatureFlagger(featuresStub: [
            FeatureFlag.webExtensionBitwarden.rawValue: true,
            FeatureFlag.webExtensionOnePassword.rawValue: true,
            FeatureFlag.webExtensionICloudPasswords.rawValue: false
        ])

        let disabledIDs = WebExtensionManager.flagDisabledExtensionIDs(featureFlagger: featureFlagger)

        XCTAssertEqual(disabledIDs, [iCloudPasswordsID])
    }

    func testWhenICloudPasswordsFlagIsOn_ThenICloudPasswordsIsNotDisabled() {
        let featureFlagger = MockFeatureFlagger(featuresStub: [
            FeatureFlag.webExtensionBitwarden.rawValue: false,
            FeatureFlag.webExtensionOnePassword.rawValue: false,
            FeatureFlag.webExtensionICloudPasswords.rawValue: true
        ])

        let disabledIDs = WebExtensionManager.flagDisabledExtensionIDs(featureFlagger: featureFlagger)

        XCTAssertEqual(disabledIDs, [ChromeWebStoreID.bitwarden.rawValue, ChromeWebStoreID.onePassword.rawValue])
    }

    func testWhenAllFlagsAreOn_ThenNothingIsDisabled() {
        let featureFlagger = MockFeatureFlagger(featuresStub: [
            FeatureFlag.webExtensionBitwarden.rawValue: true,
            FeatureFlag.webExtensionOnePassword.rawValue: true,
            FeatureFlag.webExtensionICloudPasswords.rawValue: true
        ])

        XCTAssertTrue(WebExtensionManager.flagDisabledExtensionIDs(featureFlagger: featureFlagger).isEmpty)
    }
}

//
//  PermissionAuthorizationViewControllerTests.swift
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
import SwiftUI
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class PermissionAuthorizationViewControllerTests: XCTestCase {

    func testNewViewIsShownOnlyWhenFeatureFlagIsOn() {
        let featureFlagger = MockFeatureFlagger()
        let viewController = PermissionAuthorizationViewController(featureFlagger: featureFlagger)
        let query = PermissionAuthorizationQuery(domain: "example.com", url: URL(string: "https://example.com"), permissions: [.camera]) { _ in }

        featureFlagger.featuresStub[FeatureFlag.websitePermissionsPrompts.rawValue] = false
        viewController.query = query
        XCTAssertTrue(viewController.view.subviews.first is NSHostingView<PermissionAuthorizationSwiftUIView>)

        featureFlagger.featuresStub[FeatureFlag.websitePermissionsPrompts.rawValue] = true
        viewController.query = query
        XCTAssertTrue(viewController.view.subviews.first is NSHostingView<NewPermissionAuthorizationSwiftUIView>)
    }
}

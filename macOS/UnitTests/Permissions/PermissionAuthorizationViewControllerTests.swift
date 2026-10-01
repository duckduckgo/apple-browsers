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
        XCTAssertTrue(viewController.view.subviews.first is NSHostingView<LegacyPermissionAuthorizationSwiftUIView>)

        featureFlagger.featuresStub[FeatureFlag.websitePermissionsPrompts.rawValue] = true
        viewController.query = query
        XCTAssertTrue(viewController.view.subviews.first is NSHostingView<PermissionAuthorizationView>)
    }

    // MARK: - Authorization in progress

    @MainActor
    func testAuthorizationIsNotInProgressOnceQueryIsReleased() {
        let viewController = makeViewController()
        var query: PermissionAuthorizationQuery? = makeQuery()
        viewController.query = query
        XCTAssertTrue(viewController.isAuthorizationInProgress)

        query = nil

        XCTAssertNil(viewController.query)
        XCTAssertFalse(viewController.isAuthorizationInProgress)
    }

    @MainActor
    func testAuthorizationIsNotInProgressOnceQueryIsCompletedElsewhere() {
        let viewController = makeViewController()
        let query = makeQuery()
        viewController.query = query
        XCTAssertTrue(viewController.isAuthorizationInProgress)

        query.cancel()

        XCTAssertFalse(viewController.isAuthorizationInProgress)
    }

    @MainActor
    func testFinishingCurrentQueryEndsAuthorization() throws {
        let viewController = makeViewController()
        let query = makeQuery()
        viewController.query = query
        let viewModel = try XCTUnwrap(query.parameters.authorizationViewModel)

        viewModel.finish()

        XCTAssertFalse(query.isComplete)
        XCTAssertFalse(viewController.isAuthorizationInProgress)
    }

    @MainActor
    func testFinishingCachedViewModelOfPreviousQueryKeepsCurrentAuthorizationInProgress() throws {
        let viewController = makeViewController()
        let previousQuery = makeQuery()
        let currentQuery = makeQuery()
        viewController.query = previousQuery
        let previousViewModel = try XCTUnwrap(previousQuery.parameters.authorizationViewModel)
        viewController.query = currentQuery

        previousViewModel.finish()

        XCTAssertTrue(viewController.isAuthorizationInProgress)
    }

    // MARK: - Helpers

    private func makeViewController() -> PermissionAuthorizationViewController {
        let featureFlagger = MockFeatureFlagger()
        featureFlagger.featuresStub[FeatureFlag.websitePermissionsPrompts.rawValue] = true
        return PermissionAuthorizationViewController(featureFlagger: featureFlagger, systemPermissionManager: SystemPermissionManagerMock())
    }

    private func makeQuery() -> PermissionAuthorizationQuery {
        PermissionAuthorizationQuery(domain: "example.com", url: URL(string: "https://example.com"), permissions: [.camera]) { _ in }
    }
}

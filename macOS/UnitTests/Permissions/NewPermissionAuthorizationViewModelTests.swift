//
//  NewPermissionAuthorizationViewModelTests.swift
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

@_spi(Testing) import PixelKit
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class NewPermissionAuthorizationViewModelTests: XCTestCase {

    private var pixelFiring: PixelKitMock!
    private var result: PermissionAuthorizationQuery.CallbackResult?
    private var openedURLs: [URL] = []
    private var finishCount = 0

    override func setUp() {
        super.setUp()
        pixelFiring = PixelKitMock()
    }

    override func tearDown() {
        pixelFiring = nil
        result = nil
        openedURLs = []
        finishCount = 0
        super.tearDown()
    }

    // MARK: - View state

    func testInitialStateIsUsedUntilViewAppears() {
        let initialState = NewPermissionAuthorizationViewState(title: "Initial")

        let viewModel = makeViewModel(query: makeQuery(permissions: [.camera]), initialState: initialState)

        XCTAssertEqual(viewModel.viewState, initialState)
    }

    func testOnAppearBuildsTitleAndLearnMoreForLocation() {
        let viewModel = makeViewModel(query: makeQuery(permissions: [.geolocation], domain: "maps.example.com"))

        viewModel.send(action: .onAppear)

        XCTAssertEqual(viewModel.viewState.title, String(format: UserText.websitePermissionsPromptLocationFormat, "maps.example.com"))
        XCTAssertEqual(viewModel.viewState.learnMore, .init(title: UserText.permissionPopupLearnMoreLink, url: Self.locationHelpURL))
    }

    func testOnAppearHasNoLearnMoreForCamera() {
        let viewModel = makeViewModel(query: makeQuery(permissions: [.camera]))

        viewModel.send(action: .onAppear)

        XCTAssertNil(viewModel.viewState.learnMore)
    }

    // MARK: - Decisions

    func testAllowThisVisitGrantsWithoutRemembering() throws {
        try assertDecision(.allowThisVisit, granted: true, remember: false, pixel: .allow)
    }

    func testAlwaysAllowGrantsAndRemembers() throws {
        try assertDecision(.alwaysAllow, granted: true, remember: true, pixel: .allow)
    }

    func testNeverAllowDeniesAndRemembers() throws {
        try assertDecision(.neverAllow, granted: false, remember: true, pixel: .deny)
    }

    func testDismissCancelsQueryWithoutPixel() throws {
        let query = makeQuery(permissions: [.camera])
        let viewModel = makeViewModel(query: query)

        viewModel.send(action: .dismiss)

        XCTAssertThrowsError(try XCTUnwrap(result).get())
        XCTAssertTrue(pixelFiring.actualFireCalls.isEmpty)
        XCTAssertEqual(finishCount, 1)
        withExtendedLifetime(query) {}
    }

    func testWhenDismissedPermissionIsRequestedAgainThenPendingQueryIsReplacedWithoutSavingDecision() throws {
        let manager = PermissionManagerMock()
        let model = PermissionModel(permissionManager: manager,
                                    geolocationService: GeolocationServiceMock(),
                                    systemPermissionManager: SystemPermissionManagerMock())
        let permission = PermissionType.externalScheme(scheme: "mailto")
        var decisions: [Bool] = []
        model.permissions([permission], requestedForDomain: "example.com") { (granted: Bool) in
            decisions.append(granted)
        }
        let query = try XCTUnwrap(model.authorizationQuery)
        let viewModel = makeViewModel(query: query)

        viewModel.send(action: .dismiss)

        XCTAssertEqual(decisions, [false])
        XCTAssertNil(model.authorizationQuery)
        XCTAssertNil(manager.persistedDecision(forDomain: "example.com", permissionType: permission))

        model.permissions([permission], requestedForDomain: "example.com") { (granted: Bool) in
            decisions.append(granted)
        }
        let retryQuery = try XCTUnwrap(model.authorizationQuery)
        XCTAssertFalse(retryQuery === query)
        XCTAssertEqual(model.permissions[permission], .requested(retryQuery))
        XCTAssertEqual(decisions, [false])
        XCTAssertNil(manager.persistedDecision(forDomain: "example.com", permissionType: permission))
        retryQuery.cancel()
    }

    // MARK: - Learn more

    func testLearnMoreOpensHelpPageWithoutFinishing() {
        let viewModel = makeViewModel(query: makeQuery(permissions: [.geolocation]))
        viewModel.send(action: .onAppear)

        viewModel.send(action: .learnMore)

        XCTAssertEqual(openedURLs, [Self.locationHelpURL])
        XCTAssertEqual(finishCount, 0)
    }

    // MARK: - Query lifetime

    func testViewModelDoesNotRetainQuery() {
        var query: PermissionAuthorizationQuery? = makeQuery(permissions: [.camera])
        weak var weakQuery = query
        let viewModel = makeViewModel(query: query!)

        query = nil

        XCTAssertNil(weakQuery)
        withExtendedLifetime(viewModel) {}
    }

    // MARK: - Helpers

    private static let locationHelpURL = URL(string: "https://help.duckduckgo.com/privacy/device-location-services")!

    // Duck.ai camera and microphone, so the legacy Duck.ai "always remember" rule can't leak in.
    private func assertDecision(
        _ action: NewPermissionAuthorizationViewModel.Action,
        granted: Bool,
        remember: Bool,
        pixel: PermissionPixel.AuthorizationDecision
    ) throws {
        let query = makeQuery(permissions: [.camera, .microphone], domain: "duck.ai")
        let viewModel = makeViewModel(query: query)

        viewModel.send(action: action)

        let output = try XCTUnwrap(try result?.get())
        XCTAssertEqual(output.granted, granted)
        XCTAssertEqual(output.remember, remember)
        XCTAssertEqual(pixelFiring.actualFireCalls.map(\.pixel.name), [
            PermissionPixel.authorizationDecision(permissionType: .camera, decision: pixel).name,
            PermissionPixel.authorizationDecision(permissionType: .microphone, decision: pixel).name,
        ])
        XCTAssertEqual(finishCount, 1)
        withExtendedLifetime(query) {}
    }

    private func makeQuery(permissions: [PermissionType], domain: String = "example.com") -> PermissionAuthorizationQuery {
        PermissionAuthorizationQuery(domain: domain, url: URL(string: "https://\(domain)"), permissions: permissions) { [weak self] result in
            self?.result = result
        }
    }

    private func makeViewModel(
        query: PermissionAuthorizationQuery,
        initialState: NewPermissionAuthorizationViewState = .init()
    ) -> NewPermissionAuthorizationViewModel {
        NewPermissionAuthorizationViewModel(
            initialState: initialState,
            query: query,
            pixelFiring: pixelFiring,
            openURL: { [weak self] in self?.openedURLs.append($0) },
            finish: { [weak self] in self?.finishCount += 1 }
        )
    }
}

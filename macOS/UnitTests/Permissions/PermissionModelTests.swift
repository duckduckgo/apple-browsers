//
//  PermissionModelTests.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

import AVFoundation
import Combine
import CommonObjCExtensions

import Foundation
import OSLog
import PrivacyConfig
import SharedTestUtilities
import WebKit
import XCTest

@testable import DuckDuckGo_Privacy_Browser
@testable import PixelKit

final class PermissionModelTests: XCTestCase {

    var permissionManagerMock: PermissionManagerMock!
    var geolocationServiceMock: GeolocationServiceMock!
    var geolocationProviderMock: GeolocationProviderMock!
    var systemPermissionManagerMock: SystemPermissionManagerMock!
    static var processPool: WKProcessPool!
    var webView: WebViewMock!
    var model: PermissionModel!
    var pixelKit: PixelKit! = PixelKit(dryRun: true,
                                       appVersion: "1.0.0",
                                       defaultHeaders: [:],
                                       defaults: UserDefaults(),
                                       fireRequest: { _, _, _, _, _, _ in })

    var securityOrigin: WKSecurityOrigin {
        WKSecurityOriginMock.new(url: .duckDuckGo)
    }

    var frameInfo: WKFrameInfo {
        let request = URLRequest(url: .duckDuckGo)
        return .mock(for: webView, isMain: true, securityOrigin: securityOrigin, request: request)
    }

    override class func setUp() {
        Self.processPool = WKProcessPool()
    }

    override func setUp() {
        PixelKit.setSharedForTesting(pixelKit: pixelKit)

        permissionManagerMock = PermissionManagerMock()
        geolocationServiceMock = GeolocationServiceMock()
        systemPermissionManagerMock = SystemPermissionManagerMock()

        let configuration = WKWebViewConfiguration(processPool: Self.processPool)
        webView = WebViewMock(frame: NSRect(x: 0, y: 0, width: 50, height: 50), configuration: configuration)
        webView.uiDelegate = self

        geolocationProviderMock = GeolocationProviderMock(geolocationService: geolocationServiceMock)
        webView.configuration.processPool.geolocationProvider = geolocationProviderMock
        model = PermissionModel(webView: webView,
                                permissionManager: permissionManagerMock,
                                geolocationService: geolocationServiceMock,
                                systemPermissionManager: systemPermissionManagerMock)

        AVCaptureDeviceMock.authorizationStatuses = nil
    }

    override func tearDown() {
        AVCaptureDevice.restoreAuthorizationStatusForMediaType()
        webView = nil
        permissionManagerMock = nil
        geolocationServiceMock = nil
        systemPermissionManagerMock = nil
        pixelKit = nil
        geolocationProviderMock = nil
        model = nil
    }

    override class func tearDown() {
        Self.processPool = nil
    }

    func testWhenCameraIsActivatedThenCameraPermissionChangesToActive() {
        webView.cameraCaptureState = .active
        XCTAssertEqual(model.permissions, [.camera: .active])
    }

    func testWhenMicIsActivatedThenMicPermissionChangesToActive() {
        webView.microphoneCaptureState = .active
        XCTAssertEqual(model.permissions, [.microphone: .active])
    }

    func testWhenCameraAndMicIsActivatedThenCameraAndMicPermissionChangesToActive() {
        webView.cameraCaptureState = .active
        webView.microphoneCaptureState = .active
        XCTAssertEqual(model.permissions, [.microphone: .active,
                                           .camera: .active])
    }

    func testWhenLocationIsActivatedThenLocationPermissionChangesToActive() {
        geolocationServiceMock.authorizationStatus = .notDetermined
        geolocationProviderMock.isActive = true
        geolocationServiceMock.authorizationStatus = .authorized
        XCTAssertEqual(model.permissions, [.geolocation: .active])
    }

    func testWhenPermissionIsDeactivatedThenStateChangesToInactive() {
        webView.cameraCaptureState = .active
        webView.microphoneCaptureState = .active
        webView.cameraCaptureState = .none
        webView.microphoneCaptureState = .none

        XCTAssertEqual(model.permissions, [.microphone: .inactive,
                                           .camera: .inactive])
    }

    func testWhenLocationIsDeactivatedThenStateStaysActive() {
        geolocationServiceMock.authorizationStatus = .authorized
        geolocationProviderMock.isActive = true
        geolocationProviderMock.isActive = false

        // Geolocation stays .active once granted/used (for permission center visibility)
        XCTAssertEqual(model.permissions, [.geolocation: .active])
    }

    func testWhenPermissionIsQueriedThenQueryIsPublished() {
        let e = expectation(description: "Query received")
        let c = model.$authorizationQuery.sink { query in
            guard let query = query else { return }

            XCTAssertEqual(query.domain, URL.duckDuckGo.host)
            XCTAssertEqual(query.permissions, [.camera, .microphone])
            e.fulfill()
        }

        self.webView(webView, requestUserMediaAuthorizationFor: [.microphone, .camera],
                     url: .duckDuckGo,
                     mainFrameURL: .duckDuckGo) { _ in }

        withExtendedLifetime(c) {
            waitForExpectations(timeout: 1)
            XCTAssertEqual(model.permissions, [.camera: .requested(model.authorizationQuery!),
                                               .microphone: .requested(model.authorizationQuery!)])
        }
    }

    func testWhenMicPermissionIsQueriedThenQueryIsPublished() {
        let e = expectation(description: "Query received")
        let c = model.$authorizationQuery.sink { query in
            guard let query = query else { return }

            XCTAssertEqual(query.domain, URL.duckDuckGo.host)
            XCTAssertEqual(query.permissions, [.microphone])
            e.fulfill()
        }

        self.webView(webView,
                     requestMediaCapturePermissionFor: securityOrigin,
                     initiatedByFrame: frameInfo,
                     type: .microphone) { _ in }

        withExtendedLifetime(c) {
            waitForExpectations(timeout: 1)
            XCTAssertEqual(model.permissions, [.microphone: .requested(model.authorizationQuery!)])
        }
    }

    func testWhenCameraAndMicPermissionIsGrantedThenItIsProvidedToDecisionHandler() {
        // Wait for authorizationQuery to be set by async Task
        let queryExpectation = expectation(description: "query set")
        let c = model.$authorizationQuery.dropFirst().sink { query in
            guard query != nil else { return }
            queryExpectation.fulfill()
        }

        let e = expectation(description: "Permission granted")
        self.webView(webView, requestUserMediaAuthorizationFor: [.microphone, .camera],
                     url: .duckDuckGo,
                     mainFrameURL: .duckDuckGo) { granted in
            XCTAssertTrue(granted)
            e.fulfill()
            self.webView.cameraCaptureState = .active
            self.webView.microphoneCaptureState = .active
        }

        // Wait for query to be ready, then allow it
        wait(for: [queryExpectation], timeout: 1)
        model.allow(model.authorizationQuery!)

        withExtendedLifetime(c) {
            waitForExpectations(timeout: 1)
        }
        XCTAssertEqual(model.permissions, [.camera: .active,
                                           .microphone: .active])
        XCTAssertEqual(permissionManagerMock.permission(forDomain: URL.duckDuckGo.host!, permissionType: .camera), .ask)
        XCTAssertEqual(permissionManagerMock.permission(forDomain: URL.duckDuckGo.host!, permissionType: .microphone), .ask)
    }

    func testWhenPermissionIsGrantedAndStoredThenItIsStored() {
        let c = model.$authorizationQuery.sink {
            guard let query = $0 else { return }
            query.shouldShowAlwaysAllowCheckbox = true
            query.handleDecision(grant: true, remember: true)
        }

        let e = expectation(description: "Permission granted")
        self.webView(webView, requestUserMediaAuthorizationFor: [.microphone, .camera],
                     url: .duckDuckGo,
                     mainFrameURL: .duckDuckGo) { granted in
            XCTAssertTrue(granted)
            e.fulfill()
            self.webView.cameraCaptureState = .active
            self.webView.microphoneCaptureState = .active
        }

        withExtendedLifetime(c) {
            waitForExpectations(timeout: 1)
        }
        XCTAssertEqual(model.permissions, [.camera: .active,
                                           .microphone: .active])
        XCTAssertEqual(permissionManagerMock.permission(forDomain: URL.duckDuckGo.host!, permissionType: .camera), .allow)
        XCTAssertEqual(permissionManagerMock.permission(forDomain: URL.duckDuckGo.host!, permissionType: .microphone), .allow)
    }

    func testWhenPermissionIsDeniedAndStoredThenItIsStored() {
        let c = model.$authorizationQuery.sink {
            guard let query = $0 else { return }
            query.shouldShowAlwaysAllowCheckbox = true
            query.handleDecision(grant: false, remember: true)
        }

        let e = expectation(description: "Permission granted")
        self.webView(webView, requestUserMediaAuthorizationFor: [.microphone, .camera],
                     url: .duckDuckGo,
                     mainFrameURL: .duckDuckGo) { granted in
            XCTAssertFalse(granted)
            e.fulfill()
        }

        withExtendedLifetime(c) {
            waitForExpectations(timeout: 1)
        }
        XCTAssertEqual(permissionManagerMock.permission(forDomain: URL.duckDuckGo.host!, permissionType: .camera), .deny)
        XCTAssertEqual(permissionManagerMock.permission(forDomain: URL.duckDuckGo.host!, permissionType: .microphone), .deny)
    }

    func testWhenLocationPermissionIsGrantedThenItIsProvidedToDecisionHandler() {
        self.geolocationServiceMock.authorizationStatus = .authorized
        let c = model.$authorizationQuery.sink {
            $0?.handleDecision(grant: true)
        }

        let e = expectation(description: "Permission granted")
        self.webView(webView, requestGeolocationPermissionFor: frameInfo) { granted in
            XCTAssertTrue(granted)
            e.fulfill()
            self.geolocationProviderMock.isActive = true
        }

        withExtendedLifetime(c) {
            waitForExpectations(timeout: 1)
        }
        XCTAssertEqual(model.permissions, [.geolocation: .active])
    }

    func testWhenCameraAndMicPermissionQueryIsResetThenItIsDenied() {
        let c = model.$authorizationQuery.sink {
            if $0 != nil {
                self.model!.tabDidStartNavigation()
            }
        }

        let e = expectation(description: "Permission granted")
        self.webView(webView, requestUserMediaAuthorizationFor: [.microphone, .camera],
                     url: .duckDuckGo,
                     mainFrameURL: .duckDuckGo) { granted in
            XCTAssertFalse(granted)
            e.fulfill()
        }

        withExtendedLifetime(c) {
            waitForExpectations(timeout: 1)
        }
        XCTAssertEqual(model.permissions, [:])
    }

    func testWhenLocationPermissionQueryIsResetThenItIsDenied() {
        let c = model.$authorizationQuery.sink {
            if $0 != nil {
                self.model!.tabDidStartNavigation()
            }
        }

        let e = expectation(description: "Permission granted")
        self.webView(webView, requestGeolocationPermissionFor: frameInfo) { granted in
            XCTAssertFalse(granted)
            e.fulfill()
        }

        withExtendedLifetime(c) {
            waitForExpectations(timeout: 1)
        }
        // After navigation reset, geolocation transitions to .reloading (awaiting deactivation)
        XCTAssertEqual(model.permissions, [.geolocation: .reloading])
    }

    func testWhenExternalSchemePermissionQueryIsResetThenItTriggersDecisionHandler() {
        let c = model.$authorizationQuery.sink {
            if $0 != nil {
                self.model!.tabDidStartNavigation()
            }
        }

        let e = expectation(description: "Permission granted")
        model.permissions([.externalScheme(scheme: "mailto")], requestedForDomain: "test@example.com") { (_: Bool) in
            e.fulfill()
        }

        withExtendedLifetime(c) {
            waitForExpectations(timeout: 0.1)
        }
        XCTAssertEqual(model.permissions, [:])
    }

    func testWhenAllowPermissionIsPersistedThenPermissionQueryIsGranted() {
        let e = expectation(description: "Permission granted")
        self.webView.urlValue = URL.duckDuckGo

        // Wait for authorizationQuery to be set by async Task
        let queryExpectation = expectation(description: "query set")
        let c = model.$authorizationQuery.dropFirst().sink { query in
            guard query != nil else { return }
            queryExpectation.fulfill()
        }

        self.webView(webView, requestGeolocationPermissionFor: frameInfo) { granted in
            XCTAssertTrue(granted)
            e.fulfill()
        }

        // Wait for query to be ready before publishing permission change
        wait(for: [queryExpectation], timeout: 1)

        self.permissionManagerMock.setPermission(.allow, forDomain: URL.duckDuckGo.host!, permissionType: .geolocation)
        permissionManagerMock.permissionSubject.send((URL.duckDuckGo.host!, .geolocation, .allow))

        withExtendedLifetime(c) {
            waitForExpectations(timeout: 1)
        }
    }

    func testWhenDenyPermissionIsPersistedThenPermissionQueryIsDenied() {
        let e = expectation(description: "Permission denied")
        self.webView.urlValue = URL.duckDuckGo

        // Wait for authorizationQuery to be set by async Task
        let queryExpectation = expectation(description: "query set")
        let c = model.$authorizationQuery.dropFirst().sink { query in
            guard query != nil else { return }
            queryExpectation.fulfill()
        }

        self.webView(webView, requestGeolocationPermissionFor: frameInfo) { granted in
            XCTAssertFalse(granted)
            e.fulfill()
        }

        // Wait for query to be ready before publishing permission change
        wait(for: [queryExpectation], timeout: 1)

        self.permissionManagerMock.setPermission(.deny, forDomain: URL.duckDuckGo.host!, permissionType: .geolocation)
        permissionManagerMock.permissionSubject.send((URL.duckDuckGo.host!, .geolocation, .deny))

        withExtendedLifetime(c) {
            waitForExpectations(timeout: 1)
        }
    }

    func testWhenSystemMediaPermissionIsDeniedThenStateIsDisabled() {
        let e = expectation(description: "decisionHandler called")
        AVCaptureDeviceMock.authorizationStatuses = [.audio: .denied]
        self.webView(webView, checkUserMediaPermissionFor: .duckDuckGo, mainFrameURL: .duckDuckGo, frameIdentifier: 0) { _, flag in
            XCTAssertFalse(flag)
            e.fulfill()

            _=AVCaptureDeviceMock.authorizationStatus(for: .audio)
        }

        waitForExpectations(timeout: 0)
        XCTAssertEqual(model.permissions, [.microphone: .disabled(systemWide: false)])
    }

    func testWhenSystemMediaPermissionIsRestrictedThenStateIsDisabled() {
        let e = expectation(description: "decisionHandler called")
        AVCaptureDeviceMock.authorizationStatuses = [.video: .restricted]
        self.webView(webView, checkUserMediaPermissionFor: .duckDuckGo, mainFrameURL: .duckDuckGo, frameIdentifier: 0) { _, flag in
            XCTAssertFalse(flag)
            e.fulfill()

            _=AVCaptureDeviceMock.authorizationStatus(for: .video)
        }

        waitForExpectations(timeout: 0)
        XCTAssertEqual(model.permissions, [.camera: .disabled(systemWide: false)])
    }

    func testWhenSystemMediaPermissionIsNotDeterminedThenStateIsNotUpdated() {
        let e = expectation(description: "decisionHandler called")
        AVCaptureDeviceMock.authorizationStatuses = [.audio: .notDetermined]
        self.webView(webView, checkUserMediaPermissionFor: .duckDuckGo, mainFrameURL: .duckDuckGo, frameIdentifier: 0) { _, flag in
            XCTAssertFalse(flag)
            e.fulfill()

            _=AVCaptureDeviceMock.authorizationStatus(for: .audio)
        }

        waitForExpectations(timeout: 0)
        XCTAssertEqual(model.permissions, [:])
    }

    func testWhenSystemMediaPermissionIsAuthorizedThenStateIsNotUpdated() {
        let e = expectation(description: "decisionHandler called")
        AVCaptureDeviceMock.authorizationStatuses = [.audio: .authorized]
        self.webView(webView, checkUserMediaPermissionFor: .duckDuckGo, mainFrameURL: .duckDuckGo, frameIdentifier: 0) { _, flag in
            XCTAssertFalse(flag)
            e.fulfill()

            _=AVCaptureDeviceMock.authorizationStatus(for: .video)
        }

        waitForExpectations(timeout: 0)
        XCTAssertEqual(model.permissions, [:])
    }

    func testWhenSystemLocationIsDisabledAndLocationQueriedThenQueryIsShownForTwoStepFlow() {
        geolocationServiceMock.authorizationStatus = .denied

        // Wait for authorizationQuery to be set by async Task
        let queryExpectation = expectation(description: "query set")
        let c = model.$authorizationQuery.dropFirst().sink { query in
            guard query != nil else { return }
            queryExpectation.fulfill()
        }

        var e: XCTestExpectation!
        self.webView(webView, requestGeolocationPermissionFor: securityOrigin, initiatedBy: frameInfo) { decision in
            XCTAssertEqual(decision, .grant)
            e.fulfill()
        }

        wait(for: [queryExpectation], timeout: 1)
        // The two-step authorization dialog handles system permission state,
        // so geolocation stays in .requested state (not immediately .disabled)
        XCTAssertEqual(model.permissions, [.geolocation: .requested(model.authorizationQuery!)])

        e = expectation(description: "permission granted")
        geolocationServiceMock.authorizationStatus = .authorizedAlways
        // System authorization granted triggers updatePermissions() which transitions from .requested to .inactive
        XCTAssertEqual(model.permissions, [.geolocation: .inactive])
        model.authorizationQuery!.handleDecision(grant: true)
        withExtendedLifetime(c) {
            waitForExpectations(timeout: 1)
        }

        geolocationProviderMock.isActive = true
        XCTAssertEqual(model.permissions, [.geolocation: .active])
    }

    func testWhenSystemLocationIsNotDeterminedAndLocationQueriedThenQueryIsMade() {
        geolocationServiceMock.authorizationStatus = .notDetermined

        // Wait for authorizationQuery to be set by async Task
        let queryExpectation = expectation(description: "query set")
        let c = model.$authorizationQuery.dropFirst().sink { query in
            guard query != nil else { return }
            queryExpectation.fulfill()
        }

        var e: XCTestExpectation!
        self.webView(webView, requestGeolocationPermissionFor: securityOrigin, initiatedBy: frameInfo) { decision in
            XCTAssertEqual(decision, .grant)
            e.fulfill()
        }

        wait(for: [queryExpectation], timeout: 1)
        XCTAssertEqual(model.permissions, [.geolocation: .requested(model.authorizationQuery!)])
        e = expectation(description: "permission granted")
        model.authorizationQuery!.handleDecision(grant: true)
        withExtendedLifetime(c) {
            waitForExpectations(timeout: 1)
        }

        geolocationProviderMock.isActive = true
        geolocationServiceMock.authorizationStatus = .authorized
        XCTAssertEqual(model.permissions, [.geolocation: .active])
    }

    func testWhenSystemLocationIsNotDeterminedAndDisabledByUserThenStateIsDisabled() {
        geolocationServiceMock.authorizationStatus = .notDetermined

        // Wait for authorizationQuery to be set by async Task
        let queryExpectation = expectation(description: "query set")
        let c = model.$authorizationQuery.dropFirst().sink { query in
            guard query != nil else { return }
            queryExpectation.fulfill()
        }

        var e: XCTestExpectation!
        self.webView(webView, requestGeolocationPermissionFor: securityOrigin, initiatedBy: frameInfo) { decision in
            XCTAssertEqual(decision, .grant)
            e.fulfill()
        }

        wait(for: [queryExpectation], timeout: 1)
        XCTAssertEqual(model.permissions, [.geolocation: .requested(model.authorizationQuery!)])
        e = expectation(description: "permission granted")
        model.authorizationQuery!.handleDecision(grant: true)
        withExtendedLifetime(c) {
            waitForExpectations(timeout: 1)
        }

        geolocationProviderMock.isActive = true
        geolocationServiceMock.authorizationStatus = .restricted
        XCTAssertEqual(model.permissions, [.geolocation: .disabled(systemWide: false)])
    }

    func testWhenSystemLocationIsDisabledThenStateIsDisabled() {
        geolocationServiceMock.authorizationStatus = .authorized
        geolocationProviderMock.isActive = true
        geolocationServiceMock.authorizationStatus = .denied
        XCTAssertEqual(model.permissions, [.geolocation: .disabled(systemWide: false)])
    }

    func testWhenSystemLocationIsDisabledSystemWideThenStateIsDisabled() {
        geolocationServiceMock.authorizationStatus = .authorized
        geolocationProviderMock.isActive = true
        geolocationServiceMock.locationServicesEnabledValue = false
        XCTAssertEqual(model.permissions, [.geolocation: .disabled(systemWide: true)])
    }

    func testWhenSystemLocationIsDisabledSystemWideButLocationIsNotActiveThenStateIsNotUpdated() {
        geolocationServiceMock.authorizationStatus = .notDetermined
        geolocationServiceMock.locationServicesEnabledValue = false
        XCTAssertEqual(model.permissions, [:])
    }

    func testWhenSystemLocationServicesDisabledButLocationIsNotActiveThenStateIsNotUpdated() {
        geolocationServiceMock.authorizationStatus = .notDetermined
        geolocationServiceMock.locationServicesEnabledValue = false
        XCTAssertEqual(model.permissions, [:])
    }

    func testWhenSystemLocationIsActivatedThenStateIsActive() {
        geolocationServiceMock.authorizationStatus = .denied
        geolocationServiceMock.locationServicesEnabledValue = false
        geolocationProviderMock.isActive = true
        geolocationServiceMock.authorizationStatus = .authorized
        geolocationServiceMock.locationServicesEnabledValue = true
        XCTAssertEqual(model.permissions, [.geolocation: .active])
    }

    func testWhenLocationRequeriedAfterSystemLocationIsDisabledThenStateIsDisabled() {
        geolocationServiceMock.authorizationStatus = .denied
        geolocationServiceMock.locationServicesEnabledValue = true
        geolocationServiceMock.authorizationStatus = .denied
        geolocationProviderMock.isActive = true

        // Wait for authorizationQuery to be set by async Task
        let queryExpectation = expectation(description: "query set")
        let c = model.$authorizationQuery.dropFirst().sink { query in
            guard query != nil else { return }
            queryExpectation.fulfill()
        }

        var e: XCTestExpectation!
        self.webView(webView, requestGeolocationPermissionFor: securityOrigin, initiatedBy: frameInfo) { decision in
            XCTAssertEqual(decision, .grant)
            e.fulfill()
        }

        wait(for: [queryExpectation], timeout: 1)
        e = expectation(description: "permission granted")
        model.authorizationQuery!.handleDecision(grant: true)
        withExtendedLifetime(c) {
            waitForExpectations(timeout: 1)
        }
        geolocationProviderMock.isActive = true

        XCTAssertEqual(model.permissions, [.geolocation: .disabled(systemWide: false)])
    }

    func testWhenLocationRequeriedAfterSystemLocationIsDisabledSystemWideThenStateIsDisabledSystemWide() {
        geolocationServiceMock.authorizationStatus = .denied
        geolocationServiceMock.locationServicesEnabledValue = false
        geolocationServiceMock.authorizationStatus = .denied
        geolocationProviderMock.isActive = true

        // Wait for authorizationQuery to be set by async Task
        let queryExpectation = expectation(description: "query set")
        let c = model.$authorizationQuery.dropFirst().sink { query in
            guard query != nil else { return }
            queryExpectation.fulfill()
        }

        var e: XCTestExpectation!
        self.webView(webView, requestGeolocationPermissionFor: securityOrigin, initiatedBy: frameInfo) { decision in
            XCTAssertEqual(decision, .grant)
            e.fulfill()
        }

        wait(for: [queryExpectation], timeout: 1)
        e = expectation(description: "permission granted")
        model.authorizationQuery!.handleDecision(grant: true)
        withExtendedLifetime(c) {
            waitForExpectations(timeout: 1)
        }
        geolocationProviderMock.isActive = true

        XCTAssertEqual(model.permissions, [.geolocation: .disabled(systemWide: true)])
    }

    func testWhenPageIsReloadedThenInactivePermissionStateIsReset() {
        webView.cameraCaptureState = .active
        webView.microphoneCaptureState = .active
        webView.cameraCaptureState = .none
        webView.microphoneCaptureState = .none

        model.tabDidStartNavigation()
        XCTAssertEqual(model.permissions, [:])
    }

    func testWhenPageIsReloadedThenActivePermissionStateIsReset() {
        webView.cameraCaptureState = .active
        webView.microphoneCaptureState = .active

        model.tabDidStartNavigation()
        webView.cameraCaptureState = .none
        webView.microphoneCaptureState = .none

        XCTAssertEqual(model.permissions, [:])
    }

    func testWhenPageIsReloadedThenPausedPermissionStateIsReset() {
        webView.cameraCaptureState = .active
        webView.microphoneCaptureState = .active
        webView.cameraCaptureState = .muted
        webView.microphoneCaptureState = .muted

        model.tabDidStartNavigation()
        webView.cameraCaptureState = .none
        webView.microphoneCaptureState = .none

        XCTAssertEqual(model.permissions, [:])
    }

    func testWhenPermissionIsGrantedThenItsRepeatedQueryIsQueried() {
        let e = expectation(description: "Permission queried")
        var c = model.$authorizationQuery.sink { query in
            guard let query = query else { return }
            query.handleDecision(grant: true)
            e.fulfill()
        }

        let e2 = expectation(description: "Permission granted")
        self.webView(webView, requestUserMediaAuthorizationFor: [.microphone, .camera],
                     url: .duckDuckGo,
                     mainFrameURL: .duckDuckGo) { granted in
            XCTAssertTrue(granted)
            e2.fulfill()

            self.webView.cameraCaptureState = .active
            self.webView.microphoneCaptureState = .active
            self.webView.cameraCaptureState = .none
            self.webView.microphoneCaptureState = .none
        }

        waitForExpectations(timeout: 1)

        let e3 = expectation(description: "Permission queried again")
        c = model.$authorizationQuery.sink { query in
            guard let query = query else { return }
            query.handleDecision(grant: false)
            e3.fulfill()
        }
        let e4 = expectation(description: "Permission granted again")
        self.webView(webView, requestUserMediaAuthorizationFor: [.microphone, .camera],
                     url: .duckDuckGo,
                     mainFrameURL: .duckDuckGo) { granted in
            XCTAssertFalse(granted)
            e4.fulfill()
        }

        withExtendedLifetime(c) { waitForExpectations(timeout: 1) }
    }

    func testWhenPermissionIsDeniedThenItsRepeatedQueryIsDenied() {
        let e = expectation(description: "Permission queried")
        let c = model.$authorizationQuery.sink { query in
            guard let query = query else { return }
            query.handleDecision(grant: false)
            e.fulfill()
        }

        let e2 = expectation(description: "Permission granted")
        self.webView(webView, requestUserMediaAuthorizationFor: .camera,
                     url: .duckDuckGo,
                     mainFrameURL: .duckDuckGo) { granted in
            XCTAssertFalse(granted)
            e2.fulfill()
        }

        waitForExpectations(timeout: 1)

        let e3 = expectation(description: "Permission granted again")
        self.webView(webView, requestUserMediaAuthorizationFor: [.microphone, .camera],
                     url: .duckDuckGo,
                     mainFrameURL: .duckDuckGo) { granted in
            XCTAssertFalse(granted)
            e3.fulfill()
        }

        withExtendedLifetime(c) { waitForExpectations(timeout: 1) }
    }

    func testWhenDeniedPermissionIsStoredThenQueryIsDenied() {
        permissionManagerMock.setPermission(.allow, forDomain: URL.duckDuckGo.host!, permissionType: .camera)
        permissionManagerMock.setPermission(.deny, forDomain: URL.duckDuckGo.host!, permissionType: .microphone)

        let c = model.$authorizationQuery.sink { query in
            guard query != nil else { return }
            XCTFail("Unexpected query")
        }
        let e = expectation(description: "Permission denied")
        self.webView(webView, requestUserMediaAuthorizationFor: [.microphone, .camera],
                     url: .duckDuckGo,
                     mainFrameURL: .duckDuckGo) { granted in
            XCTAssertFalse(granted)
            e.fulfill()
        }
        withExtendedLifetime(c) {
            waitForExpectations(timeout: 1)
        }
    }

    func testWhenGrantedPermissionIsStoredThenQueryIsGranted() {
        permissionManagerMock.setPermission(.allow, forDomain: URL.duckDuckGo.host!, permissionType: .camera)
        permissionManagerMock.setPermission(.allow, forDomain: URL.duckDuckGo.host!, permissionType: .microphone)

        let c = model.$authorizationQuery.sink { query in
            guard query != nil else { return }
            XCTFail("Unexpected query")
        }
        let e = expectation(description: "Permission granted")
        self.webView(webView, requestUserMediaAuthorizationFor: [.microphone, .camera],
                     url: .duckDuckGo,
                     mainFrameURL: .duckDuckGo) { granted in
            XCTAssertTrue(granted)
            e.fulfill()
        }
        withExtendedLifetime(c) {
            waitForExpectations(timeout: 1)
        }
    }

    func testWhenPartialGrantedPermissionIsStoredThenQueryIsQueried() {
        permissionManagerMock.setPermission(.allow, forDomain: URL.duckDuckGo.host!, permissionType: .camera)

        let e = expectation(description: "Permission asked")
        let c = model.$authorizationQuery.sink { query in
            guard query != nil else { return }
            e.fulfill()
        }

        self.webView(webView, requestUserMediaAuthorizationFor: [.microphone, .camera],
                     url: .duckDuckGo,
                     mainFrameURL: .duckDuckGo) { _ in
        }
        withExtendedLifetime(c) {
            waitForExpectations(timeout: 1)
        }
    }

    func testWhenDeniedPermissionIsStoredThenActivePermissionIsRevoked() {
        webView.urlValue = URL(string: "http://www.duckduckgo.com")!
        webView.cameraCaptureState = .active
        webView.microphoneCaptureState = .active

        permissionManagerMock.setPermission(.allow, forDomain: URL.duckDuckGo.host!, permissionType: .camera)

        let e = expectation(description: "camera stopped")
        webView.setMicCaptureStateHandler = { _ in
            XCTFail("unexpected call")
        }
        webView.setCameraCaptureStateHandler = {
            XCTAssertEqual($0, .none)
            e.fulfill()
        }

        permissionManagerMock.setPermission(.deny, forDomain: URL.duckDuckGo.host!, permissionType: .camera)
        permissionManagerMock.permissionSubject.send( (URL.duckDuckGo.host!, .camera, .deny) )

        waitForExpectations(timeout: 1)
    }

    func testWhenPopupsGrantedPermissionIsStoredAndRevokedThenStoredPermissionIsRemoved() {
        permissionManagerMock.setPermission(.allow, forDomain: URL.duckDuckGo.host!, permissionType: .popups)
        permissionManagerMock.setPermission(.allow, forDomain: URL.duckDuckGo.host!, permissionType: .externalScheme(scheme: "asdf"))

        webView.urlValue = URL.duckDuckGo
        model.revoke(.popups)

        XCTAssertEqual(permissionManagerMock.permission(forDomain: URL.duckDuckGo.host!, permissionType: .popups),
                       .ask)
        XCTAssertEqual(permissionManagerMock.permission(forDomain: URL.duckDuckGo.host!, permissionType: .externalScheme(scheme: "asdf")),
                       .allow)
        XCTAssertEqual(model.permissions.popups, .denied)
    }

    func testWhenExternalAppGrantedPermissionIsStoredAndRevokedThenStoredPermissionIsRemoved() {
        permissionManagerMock.setPermission(.allow, forDomain: URL.duckDuckGo.host!, permissionType: .popups)
        permissionManagerMock.setPermission(.allow, forDomain: URL.duckDuckGo.host!, permissionType: .externalScheme(scheme: "asdf"))
        permissionManagerMock.setPermission(.allow, forDomain: URL.duckDuckGo.host!, permissionType: .externalScheme(scheme: "sdfg"))

        webView.urlValue = URL.duckDuckGo

        model.revoke(.externalScheme(scheme: "asdf"))

        XCTAssertEqual(permissionManagerMock.permission(forDomain: URL.duckDuckGo.host!, permissionType: .popups),
                       .allow)
        XCTAssertEqual(permissionManagerMock.permission(forDomain: URL.duckDuckGo.host!, permissionType: .externalScheme(scheme: "asdf")),
                       .ask)
        XCTAssertEqual(permissionManagerMock.permission(forDomain: URL.duckDuckGo.host!, permissionType: .externalScheme(scheme: "sdfg")),
                       .allow)
    }

    func testWhenGrantedPermissionIsRemovedThenActivePermissionStaysActive() {
        webView.urlValue = URL(string: "http://www.duckduckgo.com")!
        self.webView.cameraCaptureState = .active
        self.webView.microphoneCaptureState = .active
        permissionManagerMock.setPermission(.allow, forDomain: URL.duckDuckGo.host!, permissionType: .camera)

        webView.setMicCaptureStateHandler = { _ in
            XCTFail("unexpected call")
        }
        webView.setCameraCaptureStateHandler = { _ in
            XCTFail("unexpected call")
        }

        permissionManagerMock.removePermission(forDomain: URL.duckDuckGo.host!, permissionType: .camera)
        permissionManagerMock.permissionSubject.send( (URL.duckDuckGo.host!, .camera, .ask) )
    }

    func testWhenMicrophoneIsMutedThenSetMediaCaptureMutedIsCalled() {
        self.webView.cameraCaptureState = .active
        self.webView.microphoneCaptureState = .active

        let e = expectation(description: "mic muted")
        webView.setMicCaptureStateHandler = {
            e.fulfill()
            XCTAssertEqual($0, false)
        }
        webView.setCameraCaptureStateHandler = { _ in
            XCTFail("Unexpected call")
        }

        model.set(.microphone, muted: true)
        waitForExpectations(timeout: 0)
        self.webView.cameraCaptureState = .muted
        self.webView.microphoneCaptureState = .muted

        XCTAssertEqual(model.permissions, [.camera: .paused, .microphone: .paused])
    }

    func testWhenCameraIsMutedThenSetMediaCaptureMutedIsCalled() {
        self.webView.cameraCaptureState = .active
        self.webView.microphoneCaptureState = .active

        let e = expectation(description: "camera muted")
        webView.setMicCaptureStateHandler = { _ in
            XCTFail("Unexpected call")
        }
        webView.setCameraCaptureStateHandler = {
            e.fulfill()
            XCTAssertEqual($0, false)
        }

        model.set(.camera, muted: true)
        waitForExpectations(timeout: 0)
    }

    func testWhenLocationIsMutedThenPauseIsCalled() {
        geolocationServiceMock.authorizationStatus = .authorized
        geolocationProviderMock.isActive = true

        model.set(.geolocation, muted: true)
        XCTAssertTrue(geolocationProviderMock.isPaused)
        XCTAssertEqual(model.permissions, [.geolocation: .paused])
    }

    func testWhenCameraIsUnmutedThenSetMediaCaptureMutedIsCalled() {
        let e = expectation(description: "camera resumed")
        webView.cameraCaptureState = .muted
        webView.microphoneCaptureState = .muted
        webView.setMicCaptureStateHandler = { _ in
            XCTFail("Unexpected call")
        }
        webView.setCameraCaptureStateHandler = {
            e.fulfill()
            XCTAssertEqual($0, true)
        }

        model.set(.camera, muted: false)
        waitForExpectations(timeout: 0)
    }

    func testWhenLocationIsUnmutedThenResumeIsCalled() {
        geolocationServiceMock.authorizationStatus = .authorized
        geolocationProviderMock.isActive = true
        geolocationProviderMock.isPaused = true

        model.set(.geolocation, muted: false)
        XCTAssertFalse(geolocationProviderMock.isPaused)
        XCTAssertEqual(model.permissions, [.geolocation: .active])
    }

    func testWhenCameraAndMicAreMutedThenSetMediaCaptureMutedIsCalled() {
        webView.cameraCaptureState = .active
        webView.microphoneCaptureState = .active

        let e1 = expectation(description: "mic muted")
        let e2 = expectation(description: "camera muted")
        webView.setMicCaptureStateHandler = {
            e1.fulfill()
            XCTAssertEqual($0, false)
        }
        webView.setCameraCaptureStateHandler = {
            e2.fulfill()
            XCTAssertEqual($0, false)
        }

        model.set([.camera, .microphone], muted: true)
        waitForExpectations(timeout: 0)

        XCTAssertEqual(model.permissions, [.camera: .paused, .microphone: .paused])
    }

    func testWhenCameraAndMicAreUnmutedThenSetMediaCaptureMutedIsCalled() {
        let e1 = expectation(description: "mic resumed")
        let e2 = expectation(description: "camera resumed")
        webView.cameraCaptureState = .muted
        webView.microphoneCaptureState = .muted
        webView.setMicCaptureStateHandler = {
            e1.fulfill()
            XCTAssertEqual($0, true)
        }
        webView.setCameraCaptureStateHandler = {
            e2.fulfill()
            XCTAssertEqual($0, true)
        }

        model.set([.camera, .microphone], muted: false)
        waitForExpectations(timeout: 0)

        XCTAssertEqual(model.permissions, [.camera: .active, .microphone: .active])
    }

    func testWhenMicrophoneIsRevokedThenStopMediaCaptureIsCalled() {
        self.webView.cameraCaptureState = .active
        self.webView.microphoneCaptureState = .active

        let e = expectation(description: "mic stopped")
        webView.setMicCaptureStateHandler = {
            XCTAssertEqual($0, .none)
            e.fulfill()
        }
        webView.setCameraCaptureStateHandler = { _ in
            XCTFail("unexpected call")
        }

        model.revoke(.microphone)
        waitForExpectations(timeout: 0)
        XCTAssertEqual(model.permissions, [.camera: .active, .microphone: .denied])
    }

    func testWhenCameraIsRevokedThenStopMediaCaptureIsCalled() {
        self.webView.cameraCaptureState = .active
        self.webView.microphoneCaptureState = .active

        let e = expectation(description: "camera stopped")
        webView.setMicCaptureStateHandler = { _ in
            XCTFail("unexpected call")
        }
        webView.setCameraCaptureStateHandler = {
            XCTAssertEqual($0, .none)
            e.fulfill()
        }

        model.revoke(.camera)
        waitForExpectations(timeout: 0)

        XCTAssertEqual(model.permissions, [.camera: .denied, .microphone: .active])
    }

    func testWhenCameraAndMicAreRevokedThenStopMediaCaptureIsCalled() {
        self.webView.cameraCaptureState = .active
        self.webView.microphoneCaptureState = .active

        let e1 = expectation(description: "camera stopped")
        let e2 = expectation(description: "mic stopped")
        webView.setCameraCaptureStateHandler = {
            XCTAssertEqual($0, .none)
            e1.fulfill()
        }
        webView.setMicCaptureStateHandler = {
            XCTAssertEqual($0, .none)
            e2.fulfill()
        }

        model.revoke(.camera)
        model.revoke(.microphone)
        waitForExpectations(timeout: 0)

        XCTAssertEqual(model.permissions, [.camera: .denied, .microphone: .denied])
    }

    func testWhenGeolocationIsRevokedThenRevokeGeolocationIsCalled() {
        geolocationServiceMock.authorizationStatus = .authorized
        geolocationProviderMock.isActive = true

        model.revoke(.geolocation)
        XCTAssertEqual(model.permissions, [.geolocation: .denied])
    }

    // MARK: - isPermissionGranted() Tests

    /// Returns true when persisted decision is .allow, regardless of session state.
    func testWhenPersistedDecisionIsAllowThenIsPermissionGrantedReturnsTrue() {
        let domain = "example.com"
        permissionManagerMock.setPermission(.allow, forDomain: domain, permissionType: .notification)

        XCTAssertTrue(model.isPermissionGranted(.notification, forDomain: domain))
    }

    /// Returns true when session state is .active (permission granted and in use).
    func testWhenSessionStateIsActiveThenIsPermissionGrantedReturnsTrue() {
        let domain = URL.duckDuckGo.host!
        webView.urlValue = URL.duckDuckGo

        // Simulate active camera permission
        webView.cameraCaptureState = .active

        XCTAssertTrue(model.isPermissionGranted(.camera, forDomain: domain))
    }

    /// Returns true when session state is .inactive (permission granted but not currently active).
    func testWhenSessionStateIsInactiveThenIsPermissionGrantedReturnsTrue() {
        let domain = URL.duckDuckGo.host!
        webView.urlValue = URL.duckDuckGo

        // Simulate inactive camera permission (was active, now inactive)
        webView.cameraCaptureState = .active
        webView.cameraCaptureState = .none

        XCTAssertTrue(model.isPermissionGranted(.camera, forDomain: domain))
    }

    /// Returns true when session state is .paused (permission granted but muted).
    func testWhenSessionStateIsPausedThenIsPermissionGrantedReturnsTrue() {
        let domain = URL.duckDuckGo.host!
        webView.urlValue = URL.duckDuckGo

        // Simulate paused camera permission
        webView.cameraCaptureState = .active
        webView.cameraCaptureState = .muted

        XCTAssertTrue(model.isPermissionGranted(.camera, forDomain: domain))
    }

    /// Returns false when permission is denied (user explicitly denied in this session).
    func testWhenSessionStateIsDeniedThenIsPermissionGrantedReturnsFalse() {
        let domain = "example.com"
        webView.urlValue = URL(string: "https://\(domain)")!

        // Set up permission as denied via model.permissions dictionary
        // Simulate a denied permission by requesting and denying
        let c = model.$authorizationQuery.sink {
            $0?.handleDecision(grant: false)
        }

        let e = expectation(description: "Permission denied")
        model.permissions([.notification], requestedForDomain: domain) { granted in
            XCTAssertFalse(granted)
            e.fulfill()
        }

        withExtendedLifetime(c) {
            waitForExpectations(timeout: 1)
        }

        XCTAssertFalse(model.isPermissionGranted(.notification, forDomain: domain))
    }

    /// Returns false when no permission exists (nil state).
    func testWhenNoPermissionExistsThenIsPermissionGrantedReturnsFalse() {
        let domain = "example.com"

        XCTAssertFalse(model.isPermissionGranted(.notification, forDomain: domain))
    }

    /// Returns false when persisted decision is .deny.
    func testWhenPersistedDecisionIsDenyThenIsPermissionGrantedReturnsFalse() {
        let domain = "example.com"
        permissionManagerMock.setPermission(.deny, forDomain: domain, permissionType: .notification)

        XCTAssertFalse(model.isPermissionGranted(.notification, forDomain: domain))
    }

    /// Returns false when persisted decision is .ask (not yet decided).
    func testWhenPersistedDecisionIsAskThenIsPermissionGrantedReturnsFalse() {
        let domain = "example.com"
        permissionManagerMock.setPermission(.ask, forDomain: domain, permissionType: .notification)

        XCTAssertFalse(model.isPermissionGranted(.notification, forDomain: domain))
    }

    // MARK: - System Permission Disabled Tests

    func testWhenSystemPermissionDeniedThenQueryIsShown() {
        // Set system permission as denied
        systemPermissionManagerMock.authorizationStates[.geolocation] = .denied

        let e = expectation(description: "Query received")
        let c = model.$authorizationQuery.sink { query in
            guard query != nil else { return }
            e.fulfill()
        }

        // Request geolocation permission
        self.webView(webView, requestGeolocationPermissionFor: securityOrigin, initiatedBy: frameInfo) { _ in }

        withExtendedLifetime(c) {
            waitForExpectations(timeout: 1)
        }

        // Verify query was shown (state should be .requested)
        XCTAssertNotNil(model.authorizationQuery)
        XCTAssertEqual(model.permissions.geolocation, .requested(model.authorizationQuery!))
    }

    func testWhenSystemPermissionRestrictedThenQueryIsShown() {
        // Set system permission as restricted
        systemPermissionManagerMock.authorizationStates[.geolocation] = .restricted

        let e = expectation(description: "Query received")
        let c = model.$authorizationQuery.sink { query in
            guard query != nil else { return }
            e.fulfill()
        }

        // Request geolocation permission
        self.webView(webView, requestGeolocationPermissionFor: securityOrigin, initiatedBy: frameInfo) { _ in }

        withExtendedLifetime(c) {
            waitForExpectations(timeout: 1)
        }

        XCTAssertNotNil(model.authorizationQuery)
    }

    func testWhenSystemPermissionDisabledSystemWideThenQueryIsShown() {
        // Set system permission as system disabled (Location Services off)
        systemPermissionManagerMock.authorizationStates[.geolocation] = .systemDisabled

        let e = expectation(description: "Query received")
        let c = model.$authorizationQuery.sink { query in
            guard query != nil else { return }
            e.fulfill()
        }

        // Request geolocation permission
        self.webView(webView, requestGeolocationPermissionFor: securityOrigin, initiatedBy: frameInfo) { _ in }

        withExtendedLifetime(c) {
            waitForExpectations(timeout: 1)
        }

        XCTAssertNotNil(model.authorizationQuery)
    }

    func testWhenSystemPermissionAuthorizedThenStoredPermissionIsUsed() {
        // Set system permission as authorized
        systemPermissionManagerMock.authorizationStates[.geolocation] = .authorized

        // Store an "allow" permission
        permissionManagerMock.setPermission(.allow, forDomain: URL.duckDuckGo.host!, permissionType: .geolocation)

        let e = expectation(description: "Permission granted from stored")
        var queryShown = false
        let c = model.$authorizationQuery.sink { query in
            if query != nil {
                queryShown = true
            }
        }

        // Request geolocation permission
        self.webView(webView, requestGeolocationPermissionFor: securityOrigin, initiatedBy: frameInfo) { decision in
            XCTAssertEqual(decision, .grant)
            e.fulfill()
        }

        withExtendedLifetime(c) {
            waitForExpectations(timeout: 1)
        }

        // When system permission is authorized, stored permission should be used
        XCTAssertFalse(queryShown)
    }

    func testWhenSystemPermissionDeniedThenStoredAllowDeniesAndShowsInfoPopover() {
        // Set system permission as denied
        systemPermissionManagerMock.authorizationStates[.geolocation] = .denied

        // Store an "allow" permission - should be ignored when system permission is denied
        permissionManagerMock.setPermission(.allow, forDomain: URL.duckDuckGo.host!, permissionType: .geolocation)

        let e = expectation(description: "Permission blocked by system")
        var receivedDomain: String?
        var receivedPermissionType: PermissionType?
        let c = model.permissionBlockedBySystem.sink { (domain, permissionType) in
            receivedDomain = domain
            receivedPermissionType = permissionType
            e.fulfill()
        }

        var permissionResult: Bool?
        // Request geolocation permission
        self.webView(webView, requestGeolocationPermissionFor: securityOrigin, initiatedBy: frameInfo) { decision in
            permissionResult = (decision == .grant)
        }

        withExtendedLifetime(c) {
            waitForExpectations(timeout: 1)
        }

        // No query shown - permission denied immediately, info popover triggered instead
        XCTAssertNil(model.authorizationQuery)
        XCTAssertEqual(permissionResult, false)
        XCTAssertEqual(receivedDomain, URL.duckDuckGo.host)
        XCTAssertEqual(receivedPermissionType, .geolocation)
    }

    func testWhenSystemPermissionDeniedButUserSetNeverAllowThenDenyDirectly() {
        // Set system permission as denied
        systemPermissionManagerMock.authorizationStates[.geolocation] = .denied

        // Store a "deny" permission - should be respected regardless of system permission state
        permissionManagerMock.setPermission(.deny, forDomain: URL.duckDuckGo.host!, permissionType: .geolocation)

        let e = expectation(description: "Permission denied directly")
        var queryShown = false
        let c = model.$authorizationQuery.sink { query in
            if query != nil {
                queryShown = true
            }
        }

        // Request geolocation permission
        self.webView(webView, requestGeolocationPermissionFor: securityOrigin, initiatedBy: frameInfo) { decision in
            XCTAssertEqual(decision, .deny)
            e.fulfill()
        }

        withExtendedLifetime(c) {
            waitForExpectations(timeout: 1)
        }

        // Query should NOT be shown - user's "Never Allow" decision should be respected
        // even when system permission is disabled
        XCTAssertFalse(queryShown)
    }

}

extension PermissionModelTests: WebViewPermissionsDelegate {

    @objc(_webView:checkUserMediaPermissionForURL:mainFrameURL:frameIdentifier:decisionHandler:)
    func webView(_ webView: WKWebView,
                 checkUserMediaPermissionFor url: URL,
                 mainFrameURL: URL,
                 frameIdentifier frame: UInt,
                 decisionHandler: @escaping (String, Bool) -> Void) {
        self.model.checkUserMediaPermission(for: url, mainFrameURL: mainFrameURL, decisionHandler: decisionHandler)
    }

    @objc(webView:requestMediaCapturePermissionForOrigin:initiatedByFrame:type:decisionHandler:)
    func webView(_ webView: WKWebView,
                 requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo,
                 type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        guard let permissions = [PermissionType](devices: type) else {
            fatalError()
        }

        self.model.permissions(permissions, requestedForDomain: origin.host) { granted in
            decisionHandler(granted ? .grant : .deny)
        }
    }

    @objc(_webView:requestUserMediaAuthorizationForDevices:url:mainFrameURL:decisionHandler:)
    func webView(_ webView: WKWebView,
                 requestUserMediaAuthorizationFor devices: UInt /*_WKCaptureDevices*/,
                 url: URL,
                 mainFrameURL: URL,
                 decisionHandler: @escaping (Bool) -> Void) {
        let devices = _WKCaptureDevices(rawValue: devices)
        guard let permissions = [PermissionType](devices: devices) else {
            fatalError()
        }

        self.model.permissions(permissions, requestedForDomain: url.host ?? "", decisionHandler: decisionHandler)
    }

    func webView(_ webView: WKWebView,
                 requestUserMediaAuthorizationFor devices: _WKCaptureDevices,
                 url: URL,
                 mainFrameURL: URL,
                 decisionHandler: @escaping (Bool) -> Void) {
        self.webView(webView,
                     requestUserMediaAuthorizationFor: devices.rawValue,
                     url: url,
                     mainFrameURL: mainFrameURL,
                     decisionHandler: decisionHandler)
    }

    @objc(_webView:mediaCaptureStateDidChange:)
    func webView(_ webView: WKWebView, mediaCaptureStateDidChange state: UInt /*_WKMediaCaptureStateDeprecated*/) {
        self.model.mediaCaptureStateDidChange()
    }

    @objc(_webView:requestGeolocationPermissionForFrame:decisionHandler:)
    func webView(_ webView: WKWebView, requestGeolocationPermissionFor frame: WKFrameInfo, decisionHandler: @escaping (Bool) -> Void) {
        self.model.permissions(.geolocation, requestedForDomain: frame.safeRequest?.url?.host ?? "", decisionHandler: decisionHandler)
    }

    @objc(_webView:requestGeolocationPermissionForOrigin:initiatedByFrame:decisionHandler:)
    func webView(_ webView: WKWebView,
                 requestGeolocationPermissionFor origin: WKSecurityOrigin,
                 initiatedBy frame: WKFrameInfo,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        self.model.permissions(.geolocation, requestedForDomain: frame.safeRequest?.url?.host ?? "") { granted in
            decisionHandler(granted ? .grant : .deny)
        }
    }

}

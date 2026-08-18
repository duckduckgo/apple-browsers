//
//  NetworkProtectionStatusViewModelTests.swift
//  DuckDuckGo
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import Combine
import Core
import VPN
import NetworkExtension
import VPNTestUtils
import SubscriptionTestingUtilities
import Subscription
@testable import DuckDuckGo

 final class NetworkProtectionStatusViewModelTests: XCTestCase {
    private var tunnelController: MockTunnelController!
    private var statusObserver: MockConnectionStatusObserver!
    private var serverInfoObserver: MockConnectionServerInfoObserver!
    private var viewModel: NetworkProtectionStatusViewModel!

    private var testError: Error {
        let nsError = NSError(domain: "", code: 0)
        return NEVPNError(_nsError: nsError)
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        tunnelController = MockTunnelController()
        statusObserver = MockConnectionStatusObserver()
        serverInfoObserver = MockConnectionServerInfoObserver()
        viewModel = NetworkProtectionStatusViewModel(tunnelController: tunnelController,
                                                     entryContextProvider: { .init(source: .toolbar, tokenState: .present) },
                                                     settings: VPNSettings(defaults: .networkProtectionGroupDefaults),
                                                     statusObserver: statusObserver,
                                                     serverInfoObserver: serverInfoObserver,
                                                     locationListRepository: MockNetworkProtectionLocationListRepository(),
                                                     enablesUnifiedFeedbackForm: false)
    }

    override func tearDown() {
        serverInfoObserver = nil
        statusObserver = nil
        tunnelController = nil
        viewModel = nil
        super.tearDown()
    }

    func testStatusUpdate_connected_setsIsNetPEnabledToTrue() async throws {
        await whenStatusUpdate_connected()
    }

    func testStatusUpdate_notConnected_setsIsNetPEnabledToFalse() async throws {
        await whenStatusUpdate_notConnected()
    }

    func testDidToggleNetPToTrue_setsTunnelControllerStateToTrue() async {
        await viewModel.didToggleNetP(to: true)
        XCTAssertEqual(self.tunnelController.didCallStart, true)
    }

    func testWhenNetPIsEnabledThenPassesEntryContextToTunnelController() async {
        let entryContext = VPNConnectionWideEventData.EntryContext(
            source: .toolbar,
            tokenState: .missing
        )
        let viewModel = makeViewModel(entryContextProvider: { entryContext })

        await viewModel.didToggleNetP(to: true)

        XCTAssertEqual(tunnelController.startEntryContexts, [entryContext])
    }

    func testWhenNetPIsEnabledThenEntryContextIsResolvedAtConnectTimeNotAtConstruction() async {
        // The token state can change between opening the VPN screen and tapping connect. The wide event
        // should record the state at connect time, so the provider must be evaluated lazily.
        var tokenState: VPNConnectionWideEventData.TokenState = .missing
        let viewModel = makeViewModel(entryContextProvider: {
            VPNConnectionWideEventData.EntryContext(source: .toolbar, tokenState: tokenState)
        })

        // A token appears after construction but before the user connects.
        tokenState = .present

        await viewModel.didToggleNetP(to: true)

        XCTAssertEqual(tunnelController.startEntryContexts,
                       [VPNConnectionWideEventData.EntryContext(source: .toolbar, tokenState: .present)])
    }

    func testDidToggleNetPToFalse_setsTunnelControllerStateToFalse() async {
        await viewModel.didToggleNetP(to: false)
        XCTAssertEqual(self.tunnelController.didCallStart, false)
    }

    func testStatusUpdate_connected_setsHeaderTitleToOn() async {
        viewModel.headerTitle = ""
        await whenStatusUpdate_connected()
        XCTAssertEqual(self.viewModel.headerTitle, UserText.netPStatusHeaderTitleOn)
    }

    func testStatusUpdate_notconnected_setsHeaderTitleToOff() async {
        let offTitleStates: [ConnectionStatus] = [.disconnected, .disconnecting, .notConfigured, .connecting, .reasserting]
        for status in offTitleStates {
            viewModel.headerTitle = ""
            statusObserver.subject.send(status)
            await waitFor(condition: self.viewModel.headerTitle == UserText.netPStatusHeaderTitleOff)
        }
    }

    func testStatusUpdate_connected_setsStatusImageIDToVPN() async {
        viewModel.statusImageID = ""
        await whenStatusUpdate_connected()
        XCTAssertEqual(self.viewModel.statusImageID, "VPN")
    }

    func testStatusUpdate_disconnected_setsStatusImageIDToVPNDisabled() async {
        viewModel.statusImageID = ""
        await whenStatusUpdate_notConnected()
        XCTAssertEqual(self.viewModel.statusImageID, "VPNDisabled")
    }

    func testStatusUpdate_connected_updatesStatusMessageEverySecond_withTimeLapsed() throws {
        statusObserver.subject.send(.connected(connectedDate: Date()))

        // This test looks at whether the publisher emits an updated "Connected" message over time.
        // In rare cases, CI can start emitting them at the 1s mark, which broke the previous test that was expecting
        // the first instance to read "0s". To make the test more resilient, it now gets the first two "Connected"
        // messages that are emitted and confirms that they're different.
        let messages = try waitForPublisher(
            viewModel.$statusMessage
                .removeDuplicates()
                .filter { $0.hasPrefix("Connected") }
                .prefix(2)
                .collect()
        )

        XCTAssertEqual(messages.count, 2)
        XCTAssertNotEqual(messages[0], messages[1], "Status message should update over time")
    }

    func testStatusUpdate_disconnecting_updateStatusToDisconnecting() throws {
        viewModel.isNetPEnabled = true
        statusObserver.subject.send(.disconnecting)
        try waitForPublisher(viewModel.$statusMessage, toEmit: UserText.netPStatusDisconnecting)
    }

    func testStatusUpdate_connectingOrReasserting_updateStatusToConnecting() throws {
        let connectingStates: [ConnectionStatus] = [.connecting, .reasserting]
        for current in connectingStates {
            statusObserver.subject.send(current)
            try waitForPublisher(viewModel.$statusMessage, toEmit: UserText.netPStatusConnecting)
        }
    }

    func testStatusUpdate_disconnectedOrNotConfigured_updateStatusToDisconnected() throws {
        let disconnectedStates: [ConnectionStatus] = [.disconnected, .notConfigured]
        // Wait for the initial value first
        try waitForPublisher(viewModel.$statusMessage, toEmit: UserText.netPStatusDisconnected)
        for current in disconnectedStates {
            viewModel.statusMessage = ""
            statusObserver.subject.send(current)
            try waitForPublisher(viewModel.$statusMessage, toEmit: UserText.netPStatusDisconnected)
        }
    }

    func testStatusUpdate_notLoadingStates_enablesToggle() throws {
        let notLoadingStates: [ConnectionStatus] = [.connected(connectedDate: Date()), .disconnected, .notConfigured]
        for current in notLoadingStates {
            viewModel.shouldDisableToggle = true
            statusObserver.subject.send(current)
            try waitForPublisher(viewModel.$shouldDisableToggle, toEmit: false)
        }
    }

    func testStatusUpdate_loadingStates_disablesToggle() throws {
        let toggleEnabledStates: [ConnectionStatus] = [.disconnecting, .connecting, .reasserting]
        for current in toggleEnabledStates {
            viewModel.shouldDisableToggle = false
            statusObserver.subject.send(current)
            try waitForPublisher(viewModel.$shouldDisableToggle, toEmit: true)
        }
    }

    func testStatusUpdate_publishesLocation() throws {
        let attributes = serverAttributes()
        let serverInfo = NetworkProtectionStatusServerInfo(serverLocation: attributes, serverAddress: nil)
        serverInfoObserver.subject.send(serverInfo)
        try waitForPublisher(viewModel.$location, toEmit: "🇺🇸 El Segundo, United States")
    }

    func testStatusUpdate_publishesIPAddress() throws {
        let ipAddress = "123.456.789.147"
        let serverInfo = NetworkProtectionStatusServerInfo(serverLocation: nil, serverAddress: ipAddress)
        serverInfoObserver.subject.send(serverInfo)
        try waitForPublisher(viewModel.$ipAddress, toEmit: ipAddress)
    }

    func testStatusUpdate_nilServerLocationAndServerAddress_hidesConnectionDetails() throws {
        let serverInfo = NetworkProtectionStatusServerInfo(serverLocation: nil, serverAddress: nil)
        // Wait for initial value first
        try waitForPublisher(viewModel.$hasServerInfo, toEmit: false)
        serverInfoObserver.subject.send(serverInfo)
        try waitForPublisher(viewModel.$hasServerInfo, toEmit: false)
    }

    func testStatusUpdate_anyServerInfoPropertiesNonNil_showsConnectionDetails() throws {
        for serverInfo in [
            NetworkProtectionStatusServerInfo(serverLocation: nil, serverAddress: "123.123.123.123"),
            NetworkProtectionStatusServerInfo(serverLocation: serverAttributes(), serverAddress: nil),
            NetworkProtectionStatusServerInfo(serverLocation: serverAttributes(), serverAddress: "111.222.333.444")
        ] {
            serverInfoObserver.subject.send(serverInfo)
            try waitForPublisher(viewModel.$hasServerInfo, toEmit: true)
        }
    }

    // MARK: - Controller (pre-session) errors

    func testControllerError_message_setsErrorBannerWithExistingCopy() async {
        let subject = CurrentValueSubject<String?, Never>(nil)
        let viewModel = makeViewModel(controllerErrorPublisher: subject.eraseToAnyPublisher())

        subject.send(UserText.vpnErrorAuthenticationFailed)

        await waitFor(condition: viewModel.error != nil)
        XCTAssertEqual(viewModel.error?.title, UserText.netPStatusViewErrorConnectionFailedTitle)
        XCTAssertEqual(viewModel.error?.message, UserText.vpnErrorAuthenticationFailed)
    }

    func testControllerError_nil_clearsErrorBanner() async {
        let subject = CurrentValueSubject<String?, Never>(nil)
        let viewModel = makeViewModel(controllerErrorPublisher: subject.eraseToAnyPublisher())

        subject.send(UserText.vpnErrorAuthenticationFailed)
        await waitFor(condition: viewModel.error != nil)

        subject.send(nil)
        await waitFor(condition: viewModel.error == nil)
        XCTAssertNil(viewModel.error)
    }

    func testControllerError_isNotClearedBySessionErrorObserverEmittingNil() async {
        let controllerErrorSubject = CurrentValueSubject<String?, Never>(nil)
        let errorObserver = MockConnectionErrorObserver()
        let viewModel = makeViewModel(controllerErrorPublisher: controllerErrorSubject.eraseToAnyPublisher(),
                                      errorObserver: errorObserver)

        controllerErrorSubject.send(UserText.vpnErrorAuthenticationFailed)
        await waitFor(condition: viewModel.error != nil)

        // A session status change that resolves to no error must not clear a live controller start failure.
        errorObserver.subject.send(nil)

        // Give the sink a chance to run, then confirm the controller error is still showing.
        await waitFor(condition: viewModel.error?.message == UserText.vpnErrorAuthenticationFailed)
        XCTAssertEqual(viewModel.error?.title, UserText.netPStatusViewErrorConnectionFailedTitle)
        XCTAssertEqual(viewModel.error?.message, UserText.vpnErrorAuthenticationFailed)
    }

    func testControllerError_takesPrecedenceOverLiveSessionError() async {
        let controllerErrorSubject = CurrentValueSubject<String?, Never>(nil)
        let errorObserver = MockConnectionErrorObserver()
        let viewModel = makeViewModel(controllerErrorPublisher: controllerErrorSubject.eraseToAnyPublisher(),
                                      errorObserver: errorObserver)

        // A real (non-nil) session error is showing in the banner first.
        errorObserver.subject.send("VPN disconnected due to expired subscription")
        await waitFor(condition: viewModel.error?.message == UserText.vpnErrorSubscriptionExpired)

        // With a controller (pre-session) start failure also present, the controller message wins.
        controllerErrorSubject.send(UserText.vpnErrorAuthenticationFailed)
        await waitFor(condition: viewModel.error?.message == UserText.vpnErrorAuthenticationFailed)
        XCTAssertEqual(viewModel.error?.title, UserText.netPStatusViewErrorConnectionFailedTitle)
        XCTAssertEqual(viewModel.error?.message, UserText.vpnErrorAuthenticationFailed)
    }

    func testWhenCreatingVPNEntryPointsThenScreenAndSubscriptionSourcesArePaired() {
        let expectations: [(VPNEntryPoint, SubscriptionFunnelOrigin, VPNConnectionWideEventData.ScreenSource)] = [
            (.toolbar, .toolbarVPN, .toolbar),
            (.addressBar, .addressBarVPN, .addressBar),
            (.widget, .widgetVPN, .widget),
            (.shortcut, .shortcutVPN, .shortcut),
            (.notification, .notificationVPN, .notification),
        ]

        for (entryPoint, expectedSubscriptionOrigin, expectedScreenSource) in expectations {
            XCTAssertEqual(entryPoint.subscriptionFunnelOrigin, expectedSubscriptionOrigin)
            XCTAssertEqual(entryPoint.screenSource, expectedScreenSource)
        }
    }

    // MARK: - Helpers

    private func makeViewModel(controllerErrorPublisher: AnyPublisher<String?, Never> = Empty(completeImmediately: false).eraseToAnyPublisher(),
                               entryContextProvider: @escaping () -> VPNConnectionWideEventData.EntryContext = { .init(source: .toolbar, tokenState: .present) },
                               errorObserver: ConnectionErrorObserver = MockConnectionErrorObserver()) -> NetworkProtectionStatusViewModel {
        NetworkProtectionStatusViewModel(tunnelController: tunnelController,
                                         entryContextProvider: entryContextProvider,
                                         settings: VPNSettings(defaults: .networkProtectionGroupDefaults),
                                         statusObserver: statusObserver,
                                         serverInfoObserver: serverInfoObserver,
                                         errorObserver: errorObserver,
                                         controllerErrorPublisher: controllerErrorPublisher,
                                         locationListRepository: MockNetworkProtectionLocationListRepository(),
                                         enablesUnifiedFeedbackForm: false)
    }

    private func whenStatusUpdate_connected() async {
        statusObserver.subject.send(.connected(connectedDate: Date()))
        await waitFor(condition: self.viewModel.isNetPEnabled)
    }

    private func whenStatusUpdate_notConnected() async {
        let nonConnectedCases: [ConnectionStatus] = [.disconnected, .disconnecting, .notConfigured, .reasserting]
        for current in nonConnectedCases {
            statusObserver.subject.send(current)
            await waitFor(condition: !self.viewModel.isNetPEnabled)
        }
    }

    private func waitFor(condition: @escaping @autoclosure () -> Bool) async {
        let predicate = NSPredicate { _, _ in
            condition()
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        await fulfillment(of: [expectation], timeout: 20)
    }

    // MARK: - Strict routing pill

    func testShowsStrictRoutingPillWhenEnabledAndAvailable() {
        let model = makeStrictRoutingViewModel(isStrictRoutingAvailable: true)
        model.isNetPEnabled = true
        XCTAssertTrue(model.showStrictRoutingPill)
    }

    func testHidesStrictRoutingPillWhenUnavailable() {
        let model = makeStrictRoutingViewModel(isStrictRoutingAvailable: false)
        model.isNetPEnabled = true
        XCTAssertFalse(model.showStrictRoutingPill)
    }

    func testHidesStrictRoutingPillWhenVPNOff() {
        let model = makeStrictRoutingViewModel(isStrictRoutingAvailable: true)
        model.isNetPEnabled = false
        XCTAssertFalse(model.showStrictRoutingPill)
    }

    func testHidesStrictRoutingPillWhileReasserting() async {
        let statusObserver = MockConnectionStatusObserver()
        let model = makeStrictRoutingViewModel(isStrictRoutingAvailable: true, statusObserver: statusObserver)

        statusObserver.subject.send(.connected(connectedDate: Date()))
        await waitFor(condition: model.isNetPEnabled)
        XCTAssertTrue(model.showStrictRoutingPill)

        // Reasserting is presented as an off/connecting state, matching the rest of the status UI,
        // so the pill and its on-state message are hidden while the tunnel reasserts.
        statusObserver.subject.send(.reasserting)
        await waitFor(condition: !model.isNetPEnabled)
        XCTAssertFalse(model.showStrictRoutingPill)
        XCTAssertEqual(model.headerMessage, UserText.netPStatusHeaderMessageOff)
    }

    func testHeaderMessageWarnsWhenStrictRoutingOff() {
        let model = makeStrictRoutingViewModel(isStrictRoutingAvailable: true)
        model.isNetPEnabled = true
        model.enforceRoutes = false
        XCTAssertEqual(model.headerMessage, UserText.netPStatusHeaderMessageStrictRoutingOff)
    }

    func testHeaderMessageReflectsOnStateWhenStrictRoutingOn() {
        let model = makeStrictRoutingViewModel(isStrictRoutingAvailable: true)
        model.isNetPEnabled = true
        model.enforceRoutes = true
        XCTAssertEqual(model.headerMessage, UserText.netPStatusHeaderMessageOn)
    }

    func testHeaderMessageReflectsOffStateWhenVPNOff() {
        let model = makeStrictRoutingViewModel(isStrictRoutingAvailable: true)
        model.isNetPEnabled = false
        model.enforceRoutes = true
        XCTAssertEqual(model.headerMessage, UserText.netPStatusHeaderMessageOff)
    }

    func testHeaderMessageReflectsOnStateWhenStrictRoutingUnavailable() {
        let model = makeStrictRoutingViewModel(isStrictRoutingAvailable: false)
        model.isNetPEnabled = true
        model.enforceRoutes = false
        XCTAssertEqual(model.headerMessage, UserText.netPStatusHeaderMessageOn)
    }

    func testStrictRoutingAvailabilityRefreshesWhenFeatureFlagChanges() throws {
        let featureFlagger = MockFeatureFlagger()
        let model = makeStrictRoutingViewModel(featureFlagger: featureFlagger)
        XCTAssertFalse(model.isStrictRoutingAvailable)

        featureFlagger.enabledFeatureFlags = [.vpnStrictRoutingToggle]
        featureFlagger.triggerUpdate()

        try waitForPublisher(model.$isStrictRoutingAvailable, toEmit: true)
    }

    private func makeStrictRoutingViewModel(isStrictRoutingAvailable: Bool,
                                            statusObserver: ConnectionStatusObserver = MockConnectionStatusObserver()) -> NetworkProtectionStatusViewModel {
        makeStrictRoutingViewModel(
            featureFlagger: MockFeatureFlagger(enabledFeatureFlags: isStrictRoutingAvailable ? [.vpnStrictRoutingToggle] : []),
            statusObserver: statusObserver
        )
    }

    private func makeStrictRoutingViewModel(featureFlagger: MockFeatureFlagger,
                                            statusObserver: ConnectionStatusObserver = MockConnectionStatusObserver()) -> NetworkProtectionStatusViewModel {
        // Use an isolated defaults suite so setting `enforceRoutes` doesn't leak into the shared
        // app-group defaults and pollute other tests.
        let suiteName = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }

        return NetworkProtectionStatusViewModel(tunnelController: MockTunnelController(),
                                                entryContextProvider: { .init(source: .toolbar, tokenState: .present) },
                                                settings: VPNSettings(defaults: defaults),
                                                statusObserver: statusObserver,
                                                serverInfoObserver: MockConnectionServerInfoObserver(),
                                                locationListRepository: MockNetworkProtectionLocationListRepository(),
                                                enablesUnifiedFeedbackForm: false,
                                                featureFlagger: featureFlagger)
    }

    private func serverAttributes() -> NetworkProtectionServerInfo.ServerAttributes {
        let json = """
        {
            "city": "El Segundo",
            "country": "us",
            "latitude": 33.9192,
            "longitude": -118.4165,
            "region": "North America",
            "state": "ca",
            "tzOffset": -28800
        }
        """

        // swiftlint:disable:next force_try
        return try! JSONDecoder().decode(NetworkProtectionServerInfo.ServerAttributes.self, from: json.data(using: .utf8)!)
    }

 }

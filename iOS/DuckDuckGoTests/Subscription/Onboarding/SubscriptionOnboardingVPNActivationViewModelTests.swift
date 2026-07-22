//
//  SubscriptionOnboardingVPNActivationViewModelTests.swift
//  DuckDuckGo
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

import Combine
import XCTest
import VPN
import VPNTestUtils
@testable import DuckDuckGo

@MainActor
final class SubscriptionOnboardingVPNActivationViewModelTests: XCTestCase {

    private let enUS = Locale(identifier: "en_US")
    private let madrid = SubscriptionOnboardingConnectionInfo(ip: "31.120.130.50", city: "Madrid", country: "ES")
    private let valencia = SubscriptionOnboardingConnectionInfo(ip: "45.132.71.9", city: "Valencia", country: "ES")

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Connection info model

    func testConnectionInfoDecodesFromConnectionJSONShape() throws {
        let json = Data(#"{"ip":"31.120.130.50","city":"Madrid","country":"ES"}"#.utf8)
        let info = try JSONDecoder().decode(SubscriptionOnboardingConnectionInfo.self, from: json)
        XCTAssertEqual(info, madrid)
    }

    func testDisplayLocationFormatsFlagCityAndLocalizedCountry() {
        XCTAssertEqual(madrid.displayLocation(locale: enUS), "🇪🇸 Madrid, Spain")
    }

    // MARK: - Placeholders

    func testWhenConnectionInfoIsUnresolvedThenTextsArePlaceholders() {
        let viewModel = makeViewModel()
        XCTAssertEqual(viewModel.originalIPText, "-.-.-")
        XCTAssertEqual(viewModel.originalLocationText, "-,-")
        XCTAssertEqual(viewModel.vpnIPText, "-.-.-")
        XCTAssertEqual(viewModel.vpnLocationText, "-,-")
    }

    // MARK: - Original IP fetch

    func testWhenOnAppearThenOriginalConnectionInfoIsFetchedAndFormatted() async {
        let service = MockConnectionInfoService(results: [madrid])
        let viewModel = makeViewModel(service: service)

        await waitFor(viewModel.$originalConnectionInfo, toEqual: .loaded(madrid)) {
            viewModel.onAppear()
        }

        XCTAssertEqual(viewModel.originalIPText, "31.120.130.50")
        XCTAssertEqual(viewModel.originalLocationText, "🇪🇸 Madrid, Spain")
    }

    func testWhenOnAppearCalledTwiceThenConnectionInfoIsFetchedOnce() async {
        let service = MockConnectionInfoService(results: [madrid, valencia])
        let viewModel = makeViewModel(service: service)

        await waitFor(viewModel.$originalConnectionInfo, toEqual: .loaded(madrid)) {
            viewModel.onAppear()
            viewModel.onAppear()
        }

        XCTAssertEqual(service.fetchCallCount, 1)
    }

    func testWhenFetchFailsThenStateIsFailedAndPlaceholdersRemain() async {
        let service = MockConnectionInfoService(results: [])
        let viewModel = makeViewModel(service: service)

        await waitFor(viewModel.$originalConnectionInfo, toEqual: .failed) {
            viewModel.onAppear()
        }

        XCTAssertEqual(viewModel.originalIPText, "-.-.-")
        XCTAssertEqual(viewModel.originalLocationText, "-,-")
    }

    // MARK: - Off / on state

    func testWhenControllerIsDisconnectedThenInitialStateIsOff() {
        let viewModel = makeViewModel(controller: MockVPNController(isConnected: false))
        XCTAssertEqual(viewModel.connectionState, .off)
    }

    func testWhenControllerIsConnectedThenInitialStateIsOn() {
        let viewModel = makeViewModel(controller: MockVPNController(isConnected: true))
        XCTAssertEqual(viewModel.connectionState, .on)
    }

    func testTurnOnVPNStartsTheController() async {
        let controller = MockVPNController(isConnected: false)
        let viewModel = makeViewModel(controller: controller)

        await viewModel.turnOnVPN()

        XCTAssertEqual(controller.startCallCount, 1)
    }

    func testWhenTunnelConnectsThenStateBecomesOnAndSectionCompletes() async {
        let controller = MockVPNController(isConnected: false)
        let delegate = SpySectionDelegate()
        let viewModel = makeViewModel(controller: controller, delegate: delegate)

        XCTAssertEqual(viewModel.connectionState, .off)

        await waitFor(viewModel.$connectionState, toEqual: .on) {
            controller.simulateConnected()
        }

        XCTAssertEqual(viewModel.connectionState, .on)
        XCTAssertEqual(delegate.completedSections, [.vpn])
    }

    func testWhenAlreadyOnThenVPNConnectionInfoComesFromServerInfoObserverAndOriginalIsNotFetched() async {
        let service = MockConnectionInfoService(results: [])
        let observer = MockConnectionServerInfoObserver()
        let viewModel = makeViewModel(service: service,
                                      controller: MockVPNController(isConnected: true),
                                      serverInfoObserver: observer)

        await waitFor(viewModel.$vpnServerInfo, toEqual: serverInfo(for: valencia)) {
            observer.subject.send(serverInfo(for: valencia))
            viewModel.onAppear()
        }

        XCTAssertEqual(service.fetchCallCount, 0)
        XCTAssertEqual(viewModel.vpnIPText, "45.132.71.9")
        XCTAssertEqual(viewModel.vpnLocationText, "🇪🇸 Valencia, Spain")
        XCTAssertEqual(viewModel.originalIPText, "-.-.-")
    }

    func testWhenAlreadyOnAndOnAppearCalledTwiceThenSectionCompletesOnce() {
        let delegate = SpySectionDelegate()
        let viewModel = makeViewModel(controller: MockVPNController(isConnected: true), delegate: delegate)

        viewModel.onAppear()
        viewModel.onAppear()

        XCTAssertEqual(delegate.completedSections, [.vpn])
    }

    func testWhenAlreadyOnThenOnAppearReportsSectionComplete() {
        let delegate = SpySectionDelegate()
        let viewModel = makeViewModel(controller: MockVPNController(isConnected: true), delegate: delegate)

        viewModel.onAppear()

        XCTAssertEqual(delegate.completedSections, [.vpn])
    }

    func testWhenTunnelConnectsThenVPNConnectionInfoComesFromServerInfoObserver() async {
        let controller = MockVPNController(isConnected: false)
        let observer = MockConnectionServerInfoObserver()
        let viewModel = makeViewModel(controller: controller, serverInfoObserver: observer)

        await waitFor(viewModel.$vpnServerInfo, toEqual: serverInfo(for: valencia)) {
            controller.simulateConnected()
            observer.subject.send(serverInfo(for: valencia))
        }

        XCTAssertEqual(viewModel.vpnIPText, "45.132.71.9")
    }

    func testWhenServerInfoHasAddressButNoLocationThenIPShowsAndLocationIsPlaceholder() async {
        let observer = MockConnectionServerInfoObserver()
        let viewModel = makeViewModel(controller: MockVPNController(isConnected: true), serverInfoObserver: observer)
        let addressOnly = NetworkProtectionStatusServerInfo(serverLocation: nil, serverAddress: "45.132.71.9")

        await waitFor(viewModel.$vpnServerInfo, toEqual: addressOnly) {
            observer.subject.send(addressOnly)
        }

        XCTAssertEqual(viewModel.vpnIPText, "45.132.71.9")
        XCTAssertEqual(viewModel.vpnLocationText, "-,-")
    }

    func testWhenTurnedOnThenPreVPNIPIsRetainedInOriginalIPRow() async {
        let service = MockConnectionInfoService(results: [madrid])
        let controller = MockVPNController(isConnected: false)
        let observer = MockConnectionServerInfoObserver()
        let viewModel = makeViewModel(service: service, controller: controller, serverInfoObserver: observer)

        await waitFor(viewModel.$originalConnectionInfo, toEqual: .loaded(madrid)) {
            viewModel.onAppear()
        }
        XCTAssertEqual(viewModel.originalIPText, "31.120.130.50")

        await waitFor(viewModel.$vpnServerInfo, toEqual: serverInfo(for: valencia)) {
            controller.simulateConnected()
            observer.subject.send(serverInfo(for: valencia))
        }

        XCTAssertEqual(viewModel.originalIPText, "31.120.130.50")
        XCTAssertEqual(viewModel.vpnIPText, "45.132.71.9")
    }

    // MARK: - Nearest location

    func testWhenNearestLocationIsSelectedThenNearestIndicatorIsShownAndLocationHasNoSuffix() async {
        let observer = MockConnectionServerInfoObserver()
        let viewModel = makeViewModel(controller: MockVPNController(isConnected: true),
                                      locationProvider: MockVPNLocationProvider(isNearestSelected: true),
                                      serverInfoObserver: observer)

        await waitFor(viewModel.$vpnServerInfo, toEqual: serverInfo(for: valencia)) {
            observer.subject.send(serverInfo(for: valencia))
            viewModel.onAppear()
        }

        XCTAssertEqual(viewModel.vpnLocationText, "🇪🇸 Valencia, Spain")
        XCTAssertEqual(viewModel.vpnLocationNearestIndicator, UserText.netPVPNLocationNearest)
    }

    func testWhenSpecificLocationIsSelectedThenNearestIndicatorIsNil() async {
        let observer = MockConnectionServerInfoObserver()
        let viewModel = makeViewModel(controller: MockVPNController(isConnected: true),
                                      locationProvider: MockVPNLocationProvider(isNearestSelected: false),
                                      serverInfoObserver: observer)

        await waitFor(viewModel.$vpnServerInfo, toEqual: serverInfo(for: valencia)) {
            observer.subject.send(serverInfo(for: valencia))
            viewModel.onAppear()
        }

        XCTAssertEqual(viewModel.vpnLocationText, "🇪🇸 Valencia, Spain")
        XCTAssertNil(viewModel.vpnLocationNearestIndicator)
    }

    // MARK: - Permission denial (observed)

    func testWhenConfigurationIsDeniedThenDidDenyVPNPermissionBecomesTrue() async {
        let controller = MockVPNController(isConnected: false)
        let viewModel = makeViewModel(controller: controller)

        await waitFor(viewModel.$didDenyVPNPermission, toEqual: true) {
            controller.simulateConfigurationDenied()
        }

        XCTAssertTrue(viewModel.didDenyVPNPermission)
    }

    func testWhenRetryingAfterDenialThenDenialStatePersists() async {
        let controller = MockVPNController(isConnected: false)
        let viewModel = makeViewModel(controller: controller)

        await waitFor(viewModel.$didDenyVPNPermission, toEqual: true) {
            controller.simulateConfigurationDenied()
        }

        await viewModel.turnOnVPN()

        XCTAssertTrue(viewModel.didDenyVPNPermission)
    }

    func testWhenTunnelConnectsAfterDenialThenDidDenyVPNPermissionIsCleared() async {
        let controller = MockVPNController(isConnected: false)
        let viewModel = makeViewModel(controller: controller)

        await waitFor(viewModel.$didDenyVPNPermission, toEqual: true) {
            controller.simulateConfigurationDenied()
        }

        await waitFor(viewModel.$connectionState, toEqual: .on) {
            controller.simulateConnected()
        }

        XCTAssertFalse(viewModel.didDenyVPNPermission)
    }

    // MARK: - Helpers

    private func makeViewModel(service: SubscriptionOnboardingConnectionInfoService = MockConnectionInfoService(results: []),
                               controller: SubscriptionOnboardingVPNControlling = MockVPNController(isConnected: false),
                               locationProvider: SubscriptionOnboardingVPNLocationProviding = MockVPNLocationProvider(),
                               serverInfoObserver: ConnectionServerInfoObserver = MockConnectionServerInfoObserver(),
                               delegate: SubscriptionOnboardingSectionDelegate? = nil) -> SubscriptionOnboardingVPNActivationViewModel {
        SubscriptionOnboardingVPNActivationViewModel(prefetcher: SubscriptionOnboardingPrefetcher(connectionInfoService: service),
                                                     vpnController: controller,
                                                     vpnLocationProvider: locationProvider,
                                                     serverInfoObserver: serverInfoObserver,
                                                     delegate: delegate,
                                                     locale: enUS)
    }

    /// Builds a server-info value (as the shared observer would publish) that maps to `info` on the egress card.
    private func serverInfo(for info: SubscriptionOnboardingConnectionInfo) -> NetworkProtectionStatusServerInfo {
        let json = "{\"city\": \"\(info.city)\", \"country\": \"\(info.country)\", \"state\": \"\"}"
        // swiftlint:disable:next force_try
        let attributes = try! JSONDecoder().decode(NetworkProtectionServerInfo.ServerAttributes.self, from: Data(json.utf8))
        return NetworkProtectionStatusServerInfo(serverLocation: attributes, serverAddress: info.ip)
    }

    /// Runs `trigger`, then waits until `publisher` emits `value`.
    private func waitFor<T: Equatable>(_ publisher: Published<T>.Publisher,
                                       toEqual value: T,
                                       trigger: () -> Void) async {
        let expectation = expectation(description: "publisher emits \(value)")
        var fulfilled = false
        publisher
            .sink { emitted in
                if emitted == value, !fulfilled {
                    fulfilled = true
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        trigger()
        await fulfillment(of: [expectation], timeout: 1)
    }
}

// MARK: - Test doubles

private final class MockConnectionInfoService: SubscriptionOnboardingConnectionInfoService {
    private var results: [SubscriptionOnboardingConnectionInfo]
    private(set) var fetchCallCount = 0

    init(results: [SubscriptionOnboardingConnectionInfo]) {
        self.results = results
    }

    func fetchConnectionInfo() async throws -> SubscriptionOnboardingConnectionInfo {
        fetchCallCount += 1
        guard !results.isEmpty else { throw CancellationError() }
        return results.removeFirst()
    }
}

private final class MockVPNController: SubscriptionOnboardingVPNControlling {
    private let subject: CurrentValueSubject<Bool, Never>
    private let configurationDeniedSubject = PassthroughSubject<Void, Never>()
    private(set) var startCallCount = 0

    init(isConnected: Bool) {
        subject = CurrentValueSubject(isConnected)
    }

    var isConnected: Bool { subject.value }

    var isConnectedPublisher: AnyPublisher<Bool, Never> { subject.eraseToAnyPublisher() }

    var configurationDeniedPublisher: AnyPublisher<Void, Never> { configurationDeniedSubject.eraseToAnyPublisher() }

    func start() async {
        startCallCount += 1
    }

    func isVPNConfigured() async -> Bool { false }

    func simulateConnected() {
        subject.send(true)
    }

    func simulateConfigurationDenied() {
        configurationDeniedSubject.send()
    }
}

private final class MockVPNLocationProvider: SubscriptionOnboardingVPNLocationProviding {
    let isNearestSelected: Bool

    init(isNearestSelected: Bool = false) {
        self.isNearestSelected = isNearestSelected
    }
}

private final class SpySectionDelegate: SubscriptionOnboardingSectionDelegate {
    private(set) var completedSections: [SubscriptionOnboardingSection] = []

    func sectionDidComplete(_ section: SubscriptionOnboardingSection) {
        completedSections.append(section)
    }

    func sectionDidRequestDuckAIChat(modelID: String?) {}
    func sectionDidRequestAdvance() {}
    func sectionDidRequestGoBack() {}
}

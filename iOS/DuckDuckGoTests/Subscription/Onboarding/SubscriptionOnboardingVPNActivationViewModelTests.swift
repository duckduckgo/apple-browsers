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

    func testWhenConnectionInfoIsUnresolvedThenTextsAreDashPlaceholders() {
        let viewModel = makeViewModel()
        XCTAssertEqual(viewModel.realIPText, "-")
        XCTAssertEqual(viewModel.realLocationText, "-")
        XCTAssertEqual(viewModel.vpnIPText, "-")
        XCTAssertEqual(viewModel.vpnLocationText, "-")
    }

    // MARK: - Real IP fetch

    func testWhenOnAppearThenRealConnectionInfoIsFetchedAndFormatted() async {
        let service = MockConnectionInfoService(results: [madrid])
        let viewModel = makeViewModel(service: service)

        await viewModel.onAppear()

        XCTAssertEqual(viewModel.realIPText, "31.120.130.50")
        XCTAssertEqual(viewModel.realLocationText, "🇪🇸 Madrid, Spain")
    }

    func testWhenOnAppearCalledTwiceThenConnectionInfoIsFetchedOnce() async {
        let service = MockConnectionInfoService(results: [madrid, valencia])
        let viewModel = makeViewModel(service: service)

        await viewModel.onAppear()
        await viewModel.onAppear()

        XCTAssertEqual(service.fetchCallCount, 1)
    }

    func testWhenFetchFailsThenPlaceholdersRemain() async {
        let service = MockConnectionInfoService(results: [])
        let viewModel = makeViewModel(service: service)

        await viewModel.onAppear()

        XCTAssertEqual(viewModel.realIPText, "-")
        XCTAssertEqual(viewModel.realLocationText, "-")
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
        let service = MockConnectionInfoService(results: [madrid, valencia])
        let controller = MockVPNController(isConnected: false)
        let delegate = SpySectionDelegate()
        let viewModel = makeViewModel(service: service, controller: controller, delegate: delegate)

        XCTAssertEqual(viewModel.connectionState, .off)

        await waitFor(viewModel.$connectionState, toEqual: .on) {
            controller.simulateConnected()
        }

        XCTAssertEqual(viewModel.connectionState, .on)
        XCTAssertEqual(delegate.completedSections, [.vpn])
    }

    func testRefreshVPNConnectionInfoFetchesAndFormatsNewConnection() async {
        let service = MockConnectionInfoService(results: [valencia])
        let viewModel = makeViewModel(service: service)

        await viewModel.refreshVPNConnectionInfo()

        XCTAssertEqual(viewModel.vpnIPText, "45.132.71.9")
        XCTAssertEqual(viewModel.vpnLocationText, "🇪🇸 Valencia, Spain")
    }

    func testRefreshVPNConnectionInfoFetchesOnlyOnce() async {
        let service = MockConnectionInfoService(results: [valencia, madrid])
        let viewModel = makeViewModel(service: service)

        await viewModel.refreshVPNConnectionInfo()
        await viewModel.refreshVPNConnectionInfo()

        XCTAssertEqual(service.fetchCallCount, 1)
    }

    // MARK: - Helpers

    private func makeViewModel(service: SubscriptionOnboardingConnectionInfoService = MockConnectionInfoService(results: []),
                               controller: SubscriptionOnboardingVPNControlling = MockVPNController(isConnected: false),
                               delegate: SubscriptionOnboardingSectionDelegate? = nil) -> SubscriptionOnboardingVPNActivationViewModel {
        SubscriptionOnboardingVPNActivationViewModel(connectionInfoService: service,
                                                     vpnController: controller,
                                                     delegate: delegate,
                                                     locale: enUS)
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
    private(set) var startCallCount = 0

    init(isConnected: Bool) {
        subject = CurrentValueSubject(isConnected)
    }

    var isConnected: Bool { subject.value }

    var isConnectedPublisher: AnyPublisher<Bool, Never> { subject.eraseToAnyPublisher() }

    func start() async {
        startCallCount += 1
    }

    func simulateConnected() {
        subject.send(true)
    }
}

private final class SpySectionDelegate: SubscriptionOnboardingSectionDelegate {
    private(set) var completedSections: [SubscriptionOnboardingSection] = []

    func sectionDidComplete(_ section: SubscriptionOnboardingSection) {
        completedSections.append(section)
    }
}

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
import AIChat
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

    func testWhenConnectionInfoIsDecodedFromConnectionJSONShapeThenFieldsArePopulated() throws {
        let json = Data(#"{"ip":"31.120.130.50","city":"Madrid","country":"ES"}"#.utf8)
        let info = try JSONDecoder().decode(SubscriptionOnboardingConnectionInfo.self, from: json)
        XCTAssertEqual(info, madrid)
    }

    func testWhenDisplayLocationThenFormatsFlagCityAndLocalizedCountry() {
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

    func testWhenTurnOnVPNThenControllerStarts() async {
        let controller = MockVPNController(isConnected: false)
        let viewModel = makeViewModel(controller: controller)

        await viewModel.turnOnVPN()

        XCTAssertEqual(controller.startCallCount, 1)
    }

    func testWhenTunnelConnectsThenStateBecomesOnAndSectionCompletes() async {
        let controller = MockVPNController(isConnected: false)
        let delegate = SpySectionDelegate()
        let viewModel = makeViewModel(controller: controller, delegate: delegate)
        viewModel.onAppear()

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
        viewModel.onAppear()

        await waitFor(viewModel.$vpnServerInfo, toEqual: serverInfo(for: valencia)) {
            observer.subject.send(serverInfo(for: valencia))
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
        viewModel.onAppear()

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
        viewModel.onAppear()

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
        viewModel.onAppear()

        await waitFor(viewModel.$vpnServerInfo, toEqual: serverInfo(for: valencia)) {
            observer.subject.send(serverInfo(for: valencia))
        }

        XCTAssertEqual(viewModel.vpnLocationText, "🇪🇸 Valencia, Spain")
        XCTAssertEqual(viewModel.vpnLocationNearestIndicator, UserText.netPVPNLocationNearest)
    }

    func testWhenSpecificLocationIsSelectedThenNearestIndicatorIsNil() async {
        let observer = MockConnectionServerInfoObserver()
        let viewModel = makeViewModel(controller: MockVPNController(isConnected: true),
                                      locationProvider: MockVPNLocationProvider(isNearestSelected: false),
                                      serverInfoObserver: observer)
        viewModel.onAppear()

        await waitFor(viewModel.$vpnServerInfo, toEqual: serverInfo(for: valencia)) {
            observer.subject.send(serverInfo(for: valencia))
        }

        XCTAssertEqual(viewModel.vpnLocationText, "🇪🇸 Valencia, Spain")
        XCTAssertNil(viewModel.vpnLocationNearestIndicator)
    }

    // MARK: - Permission denial (observed)

    func testWhenConfigurationIsDeniedThenDidDenyVPNPermissionBecomesTrue() async {
        let controller = MockVPNController(isConnected: false)
        let viewModel = makeViewModel(controller: controller)
        viewModel.onAppear()

        await waitFor(viewModel.$didDenyVPNPermission, toEqual: true) {
            controller.simulateConfigurationDenied()
        }

        XCTAssertTrue(viewModel.didDenyVPNPermission)
    }

    func testWhenRetryingAfterDenialThenDenialStatePersists() async {
        let controller = MockVPNController(isConnected: false)
        let viewModel = makeViewModel(controller: controller)
        viewModel.onAppear()

        await waitFor(viewModel.$didDenyVPNPermission, toEqual: true) {
            controller.simulateConfigurationDenied()
        }

        await viewModel.turnOnVPN()

        XCTAssertTrue(viewModel.didDenyVPNPermission)
    }

    func testWhenTunnelConnectsAfterDenialThenDidDenyVPNPermissionIsCleared() async {
        let controller = MockVPNController(isConnected: false)
        let viewModel = makeViewModel(controller: controller)
        viewModel.onAppear()

        await waitFor(viewModel.$didDenyVPNPermission, toEqual: true) {
            controller.simulateConfigurationDenied()
        }

        await waitFor(viewModel.$connectionState, toEqual: .on) {
            controller.simulateConnected()
        }

        XCTAssertFalse(viewModel.didDenyVPNPermission)
    }

    // MARK: - Start failure (observed)

    func testWhenStartingTheVPNFailsThenActivationIsMarkedAsFailed() async {
        let controller = MockVPNController(isConnected: false)
        let viewModel = makeViewModel(controller: controller)
        viewModel.onAppear()
        await viewModel.turnOnVPN()

        await waitFor(viewModel.$didFailToStartVPN, toEqual: true) {
            controller.simulateStartFailure()
        }

        XCTAssertTrue(viewModel.didFailActivation)
        XCTAssertFalse(viewModel.didDenyVPNPermission)
    }

    func testWhenTheTunnelErrorsBeforeAnyActivationAttemptThenActivationIsNotMarkedAsFailed() async {
        let errorObserver = MockConnectionErrorObserver()
        let viewModel = makeViewModel(errorObserver: errorObserver)
        let markedAsFailed = expectation(description: "an unprompted tunnel error must not mark the activation as failed")
        markedAsFailed.isInverted = true
        viewModel.$didFailToStartVPN.filter { $0 }.sink { _ in markedAsFailed.fulfill() }.store(in: &cancellables)
        viewModel.onAppear()

        errorObserver.subject.send("Failed to generate a tunnel configuration")

        await fulfillment(of: [markedAsFailed], timeout: 0.2)
        XCTAssertFalse(viewModel.didFailActivation)
    }

    func testWhenTheConfigurationIsDeniedThenActivationIsMarkedAsFailed() async {
        let controller = MockVPNController(isConnected: false)
        let viewModel = makeViewModel(controller: controller)
        viewModel.onAppear()

        await waitFor(viewModel.$didDenyVPNPermission, toEqual: true) {
            controller.simulateConfigurationDenied()
        }

        XCTAssertTrue(viewModel.didFailActivation)
        XCTAssertFalse(viewModel.didFailToStartVPN)
    }

    func testWhenStartingFailedBeforeTheScreenAppearedThenActivationIsNotMarkedAsFailed() async {
        let controller = MockVPNController(isConnected: false, controllerError: "failure from an earlier attempt")
        let viewModel = makeViewModel(controller: controller)
        let markedAsFailed = expectation(description: "the replayed error must not mark the activation as failed")
        markedAsFailed.isInverted = true
        viewModel.$didFailToStartVPN.filter { $0 }.sink { _ in markedAsFailed.fulfill() }.store(in: &cancellables)

        viewModel.onAppear()
        await viewModel.turnOnVPN()

        await fulfillment(of: [markedAsFailed], timeout: 0.2)
        XCTAssertFalse(viewModel.didFailActivation)
    }

    func testWhenARetryStartsAfterAFailureThenTheFailureStatePersists() async {
        let controller = MockVPNController(isConnected: false)
        let viewModel = makeViewModel(controller: controller)
        viewModel.onAppear()
        await viewModel.turnOnVPN()

        await waitFor(viewModel.$didFailToStartVPN, toEqual: true) {
            controller.simulateStartFailure()
        }

        let cleared = expectation(description: "a fresh start attempt must not clear the failure")
        cleared.isInverted = true
        viewModel.$didFailToStartVPN.filter { !$0 }.sink { _ in cleared.fulfill() }.store(in: &cancellables)

        controller.simulateStartAttempt()

        await fulfillment(of: [cleared], timeout: 0.2)
        XCTAssertTrue(viewModel.didFailToStartVPN)
    }

    func testWhenTheTunnelReportsAnErrorThenActivationIsMarkedAsFailed() async {
        let errorObserver = MockConnectionErrorObserver()
        let viewModel = makeViewModel(errorObserver: errorObserver)
        viewModel.onAppear()
        await viewModel.turnOnVPN()

        await waitFor(viewModel.$didFailToStartVPN, toEqual: true) {
            errorObserver.subject.send("Failed to generate a tunnel configuration")
        }

        XCTAssertTrue(viewModel.didFailActivation)
    }

    func testWhenTheTunnelErrorPredatesTheScreenThenActivationIsNotMarkedAsFailed() async {
        let errorObserver = MockConnectionErrorObserver()
        errorObserver.subject.send("Missing auth token")
        let viewModel = makeViewModel(errorObserver: errorObserver)
        let markedAsFailed = expectation(description: "the replayed error must not mark the activation as failed")
        markedAsFailed.isInverted = true
        viewModel.$didFailToStartVPN.filter { $0 }.sink { _ in markedAsFailed.fulfill() }.store(in: &cancellables)

        viewModel.onAppear()
        await viewModel.turnOnVPN()

        await fulfillment(of: [markedAsFailed], timeout: 0.2)
        XCTAssertFalse(viewModel.didFailActivation)
    }

    func testWhenStartingFailsAfterADenialThenOnlyTheStartFailureIsMarked() async {
        let controller = MockVPNController(isConnected: false)
        let viewModel = makeViewModel(controller: controller)
        viewModel.onAppear()
        await viewModel.turnOnVPN()

        await waitFor(viewModel.$didDenyVPNPermission, toEqual: true) {
            controller.simulateConfigurationDenied()
        }

        await waitFor(viewModel.$didFailToStartVPN, toEqual: true) {
            controller.simulateStartFailure()
        }

        XCTAssertFalse(viewModel.didDenyVPNPermission)
    }

    func testWhenTheConfigurationIsDeniedAfterAStartFailureThenOnlyTheDenialIsMarked() async {
        let controller = MockVPNController(isConnected: false)
        let viewModel = makeViewModel(controller: controller)
        viewModel.onAppear()
        await viewModel.turnOnVPN()

        await waitFor(viewModel.$didFailToStartVPN, toEqual: true) {
            controller.simulateStartFailure()
        }

        await waitFor(viewModel.$didDenyVPNPermission, toEqual: true) {
            controller.simulateConfigurationDenied()
        }

        XCTAssertFalse(viewModel.didFailToStartVPN)
    }

    func testWhenTunnelConnectsAfterAFailureThenTheFailureStateIsCleared() async {
        let controller = MockVPNController(isConnected: false)
        let viewModel = makeViewModel(controller: controller)
        viewModel.onAppear()
        await viewModel.turnOnVPN()

        await waitFor(viewModel.$didFailToStartVPN, toEqual: true) {
            controller.simulateStartFailure()
        }

        await waitFor(viewModel.$connectionState, toEqual: .on) {
            controller.simulateConnected()
        }

        XCTAssertFalse(viewModel.didFailToStartVPN)
        XCTAssertFalse(viewModel.didFailActivation)
    }

    // MARK: - Leaving and returning

    func testWhenTheScreenReappearsThenItStillObservesTheConnection() async {
        let controller = MockVPNController(isConnected: false)
        let viewModel = makeViewModel(controller: controller)
        viewModel.onAppear()
        viewModel.onDisappear()

        viewModel.onAppear()

        await waitFor(viewModel.$connectionState, toEqual: .on) {
            controller.simulateConnected()
        }

        XCTAssertEqual(viewModel.connectionState, .on)
    }

    func testWhenTheScreenReappearsWhileConnectedThenTheOriginalConnectionIsNotRefetched() async {
        let service = MockConnectionInfoService(results: [])
        let controller = MockVPNController(isConnected: false)
        let viewModel = makeViewModel(service: service, controller: controller)

        await waitFor(viewModel.$originalConnectionInfo, toEqual: .failed) {
            viewModel.onAppear()
        }
        await waitFor(viewModel.$connectionState, toEqual: .on) {
            controller.simulateConnected()
        }

        viewModel.onDisappear()
        viewModel.onAppear()

        // A refetch would leave through the tunnel and describe the VPN's egress, not the original connection.
        XCTAssertEqual(service.fetchCallCount, 1)
    }

    // MARK: - Tap allow hint

    func testWhenTurnOnIsTappedAgainThenAVisibleHintIsHidden() async {
        let coordinator = TapAllowHintCoordinator()
        coordinator.startTapped()
        coordinator.appWillResignActive(isVPNConfigured: { false })
        await waitForHint(coordinator)

        coordinator.startTapped()

        XCTAssertFalse(coordinator.shouldShowHint)
    }

    func testWhenThePermissionDialogAppearsAfterTappingTurnOnThenTheHintIsShown() async {
        let coordinator = TapAllowHintCoordinator()
        coordinator.startTapped()

        coordinator.appWillResignActive(isVPNConfigured: { false })

        await waitForHint(coordinator)
    }

    func testWhenTheAppResignsActiveWithoutTappingTurnOnThenTheHintIsNotShown() async {
        let coordinator = TapAllowHintCoordinator()

        coordinator.appWillResignActive(isVPNConfigured: { false })

        await assertHintDoesNotShow(coordinator)
    }

    func testWhenThePermissionIsGrantedThenTheHintIsHidden() async {
        let coordinator = TapAllowHintCoordinator()
        coordinator.startTapped()
        coordinator.appWillResignActive(isVPNConfigured: { false })
        await waitForHint(coordinator)

        coordinator.appDidBecomeActive(isVPNConfigured: { true })

        await assertHintDoesNotShow(coordinator)
    }

    func testWhenThePermissionIsDeniedThenTheHintIsHiddenAndDoesNotReturn() async {
        let coordinator = TapAllowHintCoordinator()
        coordinator.startTapped()
        coordinator.appWillResignActive(isVPNConfigured: { false })
        await waitForHint(coordinator)

        coordinator.permissionDenied()

        XCTAssertFalse(coordinator.shouldShowHint)
        coordinator.appDidBecomeActive(isVPNConfigured: { false })
        await assertHintDoesNotShow(coordinator)
    }

    func testWhenTheAppEntersBackgroundThenTheHintIsHidden() async {
        let coordinator = TapAllowHintCoordinator()
        coordinator.startTapped()
        coordinator.appWillResignActive(isVPNConfigured: { false })
        await waitForHint(coordinator)

        coordinator.appDidEnterBackground()

        XCTAssertFalse(coordinator.shouldShowHint)
    }

    func testWhenTheScreenDisappearsThenTheHintIsHiddenAndDoesNotReturn() async {
        let coordinator = TapAllowHintCoordinator()
        coordinator.startTapped()
        coordinator.appWillResignActive(isVPNConfigured: { false })
        await waitForHint(coordinator)

        coordinator.disappeared()

        XCTAssertFalse(coordinator.shouldShowHint)
        coordinator.appWillResignActive(isVPNConfigured: { false })
        await assertHintDoesNotShow(coordinator)
    }

    func testWhenTurningOnFinishesWhileTheHintIsVisibleThenTheHintIsHidden() async {
        let coordinator = TapAllowHintCoordinator()
        coordinator.startTapped()
        coordinator.appWillResignActive(isVPNConfigured: { false })
        await waitForHint(coordinator)

        coordinator.turnOnFinished()

        XCTAssertFalse(coordinator.shouldShowHint)
    }

    func testWhenASupersededConfigurationCheckReportsLastThenTheHintStaysHidden() async {
        let coordinator = TapAllowHintCoordinator()
        let gate = ConfigurationCheckGate()
        coordinator.startTapped()

        coordinator.appWillResignActive(isVPNConfigured: {
            await gate.wait()
            return false
        })

        coordinator.appDidBecomeActive(isVPNConfigured: { true })
        await gate.open()

        await assertHintDoesNotShow(coordinator)
    }

    func testWhenTurningOnFinishesWithoutConnectingOrDenialThenTheHintDoesNotReturn() async {
        let coordinator = TapAllowHintCoordinator()
        coordinator.startTapped()

        coordinator.turnOnFinished()

        coordinator.appWillResignActive(isVPNConfigured: { false })
        await assertHintDoesNotShow(coordinator)
    }

    // MARK: - Helpers

    private func waitForHint(_ coordinator: TapAllowHintCoordinator) async {
        await fulfillment(of: [hintShownExpectation(coordinator, inverted: false)], timeout: 5)
    }

    private func assertHintDoesNotShow(_ coordinator: TapAllowHintCoordinator) async {
        await fulfillment(of: [hintShownExpectation(coordinator, inverted: true)], timeout: 0.3)
    }

    private func hintShownExpectation(_ coordinator: TapAllowHintCoordinator, inverted: Bool) -> XCTestExpectation {
        let expectation = expectation(description: inverted ? "the hint must not show" : "the hint shows")
        expectation.isInverted = inverted
        var fulfilled = false
        coordinator.$shouldShowHint
            .filter { $0 }
            .sink { _ in
                if !fulfilled {
                    fulfilled = true
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        return expectation
    }

    private func makeViewModel(service: SubscriptionOnboardingConnectionInfoService = MockConnectionInfoService(results: []),
                               controller: SubscriptionOnboardingVPNControlling = MockVPNController(isConnected: false),
                               locationProvider: SubscriptionOnboardingVPNLocationProviding = MockVPNLocationProvider(),
                               serverInfoObserver: ConnectionServerInfoObserver = MockConnectionServerInfoObserver(),
                               errorObserver: ConnectionErrorObserver = MockConnectionErrorObserver(),
                               delegate: SubscriptionOnboardingSectionDelegate? = nil) -> SubscriptionOnboardingVPNActivationViewModel {
        SubscriptionOnboardingVPNActivationViewModel(prefetcher: SubscriptionOnboardingPrefetcher(connectionInfoService: service,
                                                                                                  modelProvider: StubAIModelProvider()),
                                                     vpnController: controller,
                                                     vpnLocationProvider: locationProvider,
                                                     serverInfoObserver: serverInfoObserver,
                                                     errorObserver: errorObserver,
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
        await fulfillment(of: [expectation], timeout: 5)
    }
}

// MARK: - Test doubles

@MainActor
private final class StubAIModelProvider: SubscriptionOnboardingAIModelProviding {
    nonisolated init() {}

    func fetchModels() async -> [AIChatModel] { [] }

    func updateSelectedModel(_ modelID: String) {}
}

/// `@MainActor` so its state isn't touched from two threads; `init` is `nonisolated` for the default argument.
@MainActor
private final class MockConnectionInfoService: SubscriptionOnboardingConnectionInfoService {
    private var results: [SubscriptionOnboardingConnectionInfo]
    private(set) var fetchCallCount = 0

    nonisolated init(results: [SubscriptionOnboardingConnectionInfo]) {
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
    /// Replays its current value on subscription, as the live controller's does.
    private let controllerErrorSubject: CurrentValueSubject<String?, Never>
    private(set) var startCallCount = 0

    init(isConnected: Bool, controllerError: String? = nil) {
        subject = CurrentValueSubject(isConnected)
        controllerErrorSubject = CurrentValueSubject(controllerError)
    }

    var isConnected: Bool { subject.value }

    var isConnectedPublisher: AnyPublisher<Bool, Never> { subject.eraseToAnyPublisher() }

    var configurationDeniedPublisher: AnyPublisher<Void, Never> { configurationDeniedSubject.eraseToAnyPublisher() }

    var controllerErrorPublisher: AnyPublisher<String?, Never> { controllerErrorSubject.eraseToAnyPublisher() }

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

    func simulateStartFailure(_ message: String = "Unable to connect to a VPN server.") {
        controllerErrorSubject.send(message)
    }

    /// Clears the carried error, as the live controller does when a start attempt begins.
    func simulateStartAttempt() {
        controllerErrorSubject.send(nil)
    }
}

private actor ConfigurationCheckGate {
    private var isOpen = false
    private var waiter: CheckedContinuation<Void, Never>?

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiter = $0 }
    }

    func open() {
        isOpen = true
        waiter?.resume()
        waiter = nil
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

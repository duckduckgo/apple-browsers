//
//  PermissionAuthorizationViewModelTests.swift
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
import Combine
import FeatureFlags_macOS
import PrivacyConfig
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class PermissionAuthorizationViewModelTests: XCTestCase {

    private var pixelFiring: PixelKitMock!
    private var systemPermissionManager: SystemPermissionManagerMock!
    private var appDidBecomeActive: PassthroughSubject<Void, Never>!
    private var scheduledWork: [(delay: TimeInterval, work: @MainActor () -> Void)] = []
    private var result: PermissionAuthorizationQuery.CallbackResult?
    private var openedURLs: [URL] = []
    private var openedSystemSettingsURLs: [URL] = []
    private var finishCount = 0
    /// A prompt shown through a real permission model; kept alive for the test.
    private var sitePrompt: SitePrompt?
    /// What the page was told for the request behind `sitePrompt`.
    private var pageDecisions: [Bool] = []

    override func setUp() {
        super.setUp()
        pixelFiring = PixelKitMock()
        systemPermissionManager = SystemPermissionManagerMock()
        appDidBecomeActive = PassthroughSubject()
    }

    override func tearDown() {
        pixelFiring = nil
        systemPermissionManager = nil
        appDidBecomeActive = nil
        scheduledWork = []
        result = nil
        openedURLs = []
        openedSystemSettingsURLs = []
        finishCount = 0
        sitePrompt = nil
        pageDecisions = []
        super.tearDown()
    }

    // MARK: - View state

    func testInitialStateIsUsedUntilViewAppears() {
        let initialState = PermissionAuthorizationViewState(title: "Initial")

        let viewModel = makeViewModel(query: makeQuery(permissions: [.camera]), initialState: initialState)

        XCTAssertEqual(viewModel.viewState, initialState)
    }

    func testOnAppearBuildsTitleAndLearnMoreForLocation() {
        let viewModel = makeViewModel(query: makeQuery(permissions: [.geolocation], domain: "maps.example.com"))

        viewModel.send(action: .onAppear)

        XCTAssertEqual(viewModel.viewState.title, String(format: UserText.websitePermissionsPromptLocationFormat, "maps.example.com"))
        XCTAssertEqual(viewModel.viewState.decision?.learnMore, .init(title: UserText.permissionPopupLearnMoreLink, url: Self.locationHelpURL))
    }

    func testWhenExternalAppIsOpenedFromALocalFileOrATypedLinkThenOnlyTheLocalFileCanSaveTheChoice() {
        let permission = PermissionType.externalScheme(scheme: "mailto")
        let localFileViewModel = makeViewModel(query: makeQuery(permissions: [permission], domain: .localFilePermissionDomain))
        let typedLinkViewModel = makeViewModel(query: makeQuery(permissions: [permission], domain: ""))

        localFileViewModel.send(action: .onAppear)
        typedLinkViewModel.send(action: .onAppear)

        XCTAssertEqual(localFileViewModel.viewState.title,
                       String(format: UserText.externalSchemePermissionAuthorizationFormat, UserText.websitePermissionsLocalFile, permission.localizedDescription))
        XCTAssertEqual(localFileViewModel.viewState.decision?.buttons.map(\.action), [.allowThisVisit, .alwaysAllow, .neverAllow])
        XCTAssertEqual(typedLinkViewModel.viewState.title,
                       String(format: UserText.externalSchemePermissionAuthorizationNoDomainFormat, permission.localizedDescription))
        XCTAssertEqual(typedLinkViewModel.viewState.decision?.buttons.map(\.action), [.allowThisVisit])
    }

    func testOnAppearHasNoLearnMoreForCamera() {
        let viewModel = makeViewModel(query: makeQuery(permissions: [.camera]))

        viewModel.send(action: .onAppear)

        XCTAssertNil(viewModel.viewState.decision?.learnMore)
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
        let featureFlagger = MockFeatureFlagger()
        featureFlagger.featuresStub[FeatureFlag.websitePermissionsPrompts.rawValue] = true
        let model = PermissionModel(permissionManager: manager,
                                    geolocationService: GeolocationServiceMock(),
                                    systemPermissionManager: SystemPermissionManagerMock(),
                                    featureFlagger: featureFlagger)
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
        XCTAssertNil(model.permissions[permission])
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

    // MARK: - System permission step

    func testWhenNotificationPermissionIsResetThenWebsiteChoicesPrecedeSystemRequest() async throws {
        for action in [PermissionAuthorizationViewModel.Action.allowThisVisit, .alwaysAllow] {
            pixelFiring = PixelKitMock()
            systemPermissionManager = SystemPermissionManagerMock()
            systemPermissionManager.notificationAuthorizationStateSubject.send(.notDetermined)
            systemPermissionManager.defersAuthorizationResponse = true
            let manager = PermissionManagerMock()
            let featureFlagger = MockFeatureFlagger()
            featureFlagger.featuresStub[FeatureFlag.websitePermissionsPrompts.rawValue] = true
            let model = PermissionModel(permissionManager: manager,
                                        geolocationService: GeolocationServiceMock(),
                                        systemPermissionManager: systemPermissionManager,
                                        featureFlagger: featureFlagger)
            var decisions: [Bool] = []
            model.permissions([.notification], requestedForDomain: "example.com") { (granted: Bool) in
                decisions.append(granted)
            }
            let query = try XCTUnwrap(model.authorizationQuery)
            let viewModel = makeViewModel(query: query)

            viewModel.send(action: .onAppear)

            XCTAssertFalse(query.opensOnSystemPermissionStep)
            XCTAssertNil(viewModel.viewState.systemPermissionStep)
            XCTAssertEqual(viewModel.viewState.decision?.buttons.map(\.action), [.allowThisVisit, .alwaysAllow, .neverAllow])
            XCTAssertTrue(decisions.isEmpty)
            XCTAssertTrue(systemPermissionManager.authorizationRequestedFor.isEmpty)

            viewModel.send(action: action)

            XCTAssertEqual(viewModel.viewState.systemPermissionStep?.phase, .request)
            XCTAssertTrue(decisions.isEmpty)
            XCTAssertTrue(systemPermissionManager.authorizationRequestedFor.isEmpty)

            viewModel.send(action: .requestSystemPermission)

            XCTAssertEqual(viewModel.viewState.systemPermissionStep?.phase, .waiting)
            XCTAssertNil(viewModel.viewState.systemPermissionStep?.buttonAction)
            XCTAssertEqual(systemPermissionManager.authorizationRequestedFor, [.notification])
            XCTAssertTrue(decisions.isEmpty)

            respondToSystemPermissionRequest(with: .authorized)
            await waitUntil { !decisions.isEmpty }

            XCTAssertEqual(decisions, [true])
            XCTAssertEqual(pixelFiring.actualFireCalls.map(\.pixel.name), [
                PermissionPixel.authorizationDecision(permissionType: .notification, decision: .allow).name,
            ])
            XCTAssertNil(model.authorizationQuery)
            XCTAssertEqual(manager.persistedDecision(forDomain: "example.com", permissionType: .notification),
                           action == .alwaysAllow ? .allow : nil)
            withExtendedLifetime(viewModel) {}
        }
    }

    func testWhenMediaAccessIsBlockedThenEachDeviceMustBeAuthorizedBeforeGrantingTheSite() async throws {
        for permissions: [PermissionType] in [[.camera], [.microphone], [.camera, .microphone], [.microphone, .camera]] {
            result = nil
            finishCount = 0
            openedSystemSettingsURLs = []
            systemPermissionManager = SystemPermissionManagerMock()
            systemPermissionManager.defersAuthorizationResponse = true
            for permission in permissions {
                systemPermissionManager.authorizationStates[permission] = .notDetermined
            }
            let blockedPermission = try XCTUnwrap(permissions.first)
            systemPermissionManager.authorizationStates[blockedPermission] = .denied
            let query = makeQuery(permissions: permissions)
            let viewModel = makeViewModel(query: query)

            viewModel.send(action: .onAppear)
            XCTAssertNil(viewModel.viewState.systemPermissionStep)
            viewModel.send(action: .alwaysAllow)
            XCTAssertEqual(viewModel.viewState.systemPermissionStep?.phase, .openSettings)
            viewModel.send(action: .openSystemSettings)
            XCTAssertEqual(openedSystemSettingsURLs.last, PermissionAuthorizationType(from: [blockedPermission]).systemSettingsURL)
            XCTAssertNil(result)

            // Reset the blocked device in Settings; the request must still wait for every device.
            systemPermissionManager.authorizationStates[blockedPermission] = .notDetermined
            appDidBecomeActive.send()
            await waitUntil { viewModel.viewState.systemPermissionStep?.phase == .request }

            for permission in permissions {
                viewModel.send(action: .requestSystemPermission)
                XCTAssertEqual(viewModel.viewState.systemPermissionStep?.phase, .waiting)
                XCTAssertEqual(systemPermissionManager.authorizationRequestedFor.last, permission)
                XCTAssertNil(result)

                systemPermissionManager.authorizationStates[permission] = .authorized
                respondToSystemPermissionRequest(with: .authorized)
                await waitUntil { self.result != nil || viewModel.viewState.systemPermissionStep?.phase != .waiting }
                if permission != permissions.last {
                    XCTAssertNil(result)
                    XCTAssertEqual(viewModel.viewState.systemPermissionStep?.phase, .request)
                }
            }

            let output = try XCTUnwrap(try result?.get())
            XCTAssertTrue(output.granted)
            XCTAssertEqual(output.remember, true)
            XCTAssertEqual(finishCount, 1)
            withExtendedLifetime((query, viewModel)) {}
        }
    }

    func testWhenDecisionNeedsNoSystemRequestThenItSubmitsImmediately() throws {
        let scenarios: [(permissions: [PermissionType], state: SystemPermissionAuthorizationState,
                         action: PermissionAuthorizationViewModel.Action, granted: Bool, remember: Bool)] = [
            ([.notification], .authorized, .alwaysAllow, true, true),
            ([.notification], .denied, .neverAllow, false, true),
            ([.camera, .microphone], .authorized, .allowThisVisit, true, false),
        ]
        for scenario in scenarios {
            result = nil
            finishCount = 0
            systemPermissionManager.defaultAuthorizationState = scenario.state
            systemPermissionManager.notificationAuthorizationStateSubject.send(scenario.state)
            let query = makeQuery(permissions: scenario.permissions)
            let viewModel = makeViewModel(query: query)

            viewModel.send(action: scenario.action)

            let output = try XCTUnwrap(try result?.get())
            XCTAssertEqual(output.granted, scenario.granted)
            XCTAssertEqual(output.remember, scenario.remember)
            XCTAssertNil(viewModel.viewState.systemPermissionStep)
            XCTAssertTrue(systemPermissionManager.authorizationRequestedFor.isEmpty)
            XCTAssertEqual(finishCount, 1)
            withExtendedLifetime((viewModel, query)) {}
        }
    }

    func testWhenMediaRefreshRacesCameraCompletionThenItDoesNotReturnToTheCameraStep() async {
        systemPermissionManager.authorizationStates = [.camera: .notDetermined, .microphone: .notDetermined]
        systemPermissionManager.defersAuthorizationResponse = true
        systemPermissionManager.defersAuthorizationStateResponse = true
        let query = makeQuery(permissions: [.camera, .microphone])
        let viewModel = makeViewModel(query: query)
        viewModel.send(action: .allowThisVisit)
        viewModel.send(action: .requestSystemPermission)

        appDidBecomeActive.send()
        await waitUntil { self.systemPermissionManager.pendingAuthorizationStateCompletions.count == 1 }
        systemPermissionManager.pendingAuthorizationStateCompletions[0](.notDetermined)
        await waitUntil { self.systemPermissionManager.pendingAuthorizationStateCompletions.count == 2 }

        // The refresh has already read the old camera state and is waiting for microphone status.
        systemPermissionManager.authorizationStates[.camera] = .authorized
        respondToSystemPermissionRequest(with: .authorized)
        await waitUntil { viewModel.viewState.systemPermissionStep?.phase == .request }
        systemPermissionManager.pendingAuthorizationStateCompletions[1](.notDetermined)
        await waitUntil { self.systemPermissionManager.authorizationStateResponseCount == 2 }
        await settle()

        viewModel.send(action: .requestSystemPermission)

        XCTAssertEqual(systemPermissionManager.authorizationRequestedFor, [.camera, .microphone])
        XCTAssertEqual(viewModel.viewState.systemPermissionStep?.phase, .waiting)
        XCTAssertNil(result)

        systemPermissionManager.authorizationStates[.microphone] = .authorized
        respondToSystemPermissionRequest(with: .authorized)
        await waitUntil { self.result != nil }
        XCTAssertEqual(finishCount, 1)
        withExtendedLifetime((query, viewModel)) {}
    }

    func testWhenLocationServicesAreRestoredThenSettingsStepReturnsToRequestStep() async throws {
        systemPermissionManager.authorizationStates[.geolocation] = .systemDisabled
        let query = makeQuery(permissions: [.geolocation])
        let viewModel = makeViewModel(query: query)
        viewModel.send(action: .allowThisVisit)

        XCTAssertEqual(viewModel.viewState.systemPermissionStep?.phase, .openSettings)
        XCTAssertEqual(viewModel.viewState.systemPermissionStep?.message, UserText.websitePermissionsPromptSystemLocationOff)
        viewModel.send(action: .openSystemSettings)

        XCTAssertEqual(openedSystemSettingsURLs, [try XCTUnwrap(PermissionAuthorizationType.geolocation.systemSettingsURL)])
        XCTAssertEqual(pixelFiring.actualFireCalls.map(\.pixel.name), [
            PermissionPixel.systemPreferencesOpened(permissionType: .geolocation).name,
        ])
        XCTAssertNil(result)
        XCTAssertEqual(finishCount, 0)

        systemPermissionManager.authorizationStates[.geolocation] = .notDetermined
        appDidBecomeActive.send()
        await waitUntil { viewModel.viewState.systemPermissionStep?.phase == .request }

        XCTAssertEqual(viewModel.viewState.systemPermissionStep?.message, UserText.websitePermissionsPromptSystemLocationRequired)
        XCTAssertTrue(systemPermissionManager.authorizationRequestedFor.isEmpty)
        XCTAssertNil(result)
        withExtendedLifetime((viewModel, query)) {}
    }

    func testWhenLocationAccessIsRestoredThenPendingDecisionIsSubmitted() async throws {
        systemPermissionManager.authorizationStates[.geolocation] = .systemDisabled
        let query = makeQuery(permissions: [.geolocation])
        let viewModel = makeViewModel(query: query)
        viewModel.send(action: .allowThisVisit)
        XCTAssertEqual(viewModel.viewState.systemPermissionStep?.phase, .openSettings)
        XCTAssertNil(result)

        systemPermissionManager.authorizationStates[.geolocation] = .authorized
        appDidBecomeActive.send()
        await waitUntil { self.result != nil }

        let output = try XCTUnwrap(try result?.get())
        XCTAssertTrue(output.granted)
        XCTAssertEqual(output.remember, false)
        XCTAssertTrue(query.isComplete)
        XCTAssertEqual(finishCount, 1)
        XCTAssertTrue(systemPermissionManager.authorizationRequestedFor.isEmpty)
        withExtendedLifetime((viewModel, query)) {}
    }

    func testWhenSystemPermissionIsDeniedElsewhereThenReturningShowsSettingsAndPreservesPendingDecision() async throws {
        systemPermissionManager.notificationAuthorizationStateSubject.send(.notDetermined)
        let query = makeQuery(permissions: [.notification])
        let viewModel = makeViewModel(query: query)
        viewModel.send(action: .allowThisVisit)
        XCTAssertEqual(viewModel.viewState.systemPermissionStep?.phase, .request)

        systemPermissionManager.notificationAuthorizationStateSubject.send(.denied)
        appDidBecomeActive.send()
        await waitUntil { viewModel.viewState.systemPermissionStep?.phase == .openSettings }

        XCTAssertEqual(viewModel.viewState.systemPermissionStep, .init(
            phase: .openSettings,
            message: UserText.websitePermissionsPromptSystemNotificationsOff,
            buttonTitle: UserText.websitePermissionsPromptOpenSystemSettings
        ))
        XCTAssertNil(result)
        XCTAssertEqual(finishCount, 0)
        XCTAssertTrue(systemPermissionManager.authorizationRequestedFor.isEmpty)

        systemPermissionManager.notificationAuthorizationStateSubject.send(.authorized)
        appDidBecomeActive.send()
        await waitUntil { self.result != nil }

        let output = try XCTUnwrap(try result?.get())
        XCTAssertTrue(output.granted)
        XCTAssertEqual(output.remember, false)
        XCTAssertEqual(finishCount, 1)
        withExtendedLifetime((viewModel, query)) {}
    }

    func testWhenSystemPermissionIsDeniedThenSettingsCanResumePendingDecision() async throws {
        let (viewModel, query) = makeViewModelWaitingForSystemPermission(decision: .alwaysAllow)

        systemPermissionManager.notificationAuthorizationStateSubject.send(.denied)
        respondToSystemPermissionRequest(with: .denied)
        await waitUntil { viewModel.viewState.systemPermissionStep?.phase == .openSettings }

        XCTAssertEqual(viewModel.viewState.systemPermissionStep, .init(
            phase: .openSettings,
            message: UserText.websitePermissionsPromptSystemNotificationsOff,
            buttonTitle: UserText.websitePermissionsPromptOpenSystemSettings
        ))
        XCTAssertNil(result)
        XCTAssertEqual(finishCount, 0)

        appDidBecomeActive.send()
        await settle()
        XCTAssertEqual(viewModel.viewState.systemPermissionStep?.phase, .openSettings)
        XCTAssertNil(result)

        systemPermissionManager.notificationAuthorizationStateSubject.send(.authorized)
        appDidBecomeActive.send()
        await waitUntil { self.result != nil }

        let output = try XCTUnwrap(try result?.get())
        XCTAssertTrue(output.granted)
        XCTAssertEqual(output.remember, true)
        XCTAssertEqual(finishCount, 1)
        withExtendedLifetime((viewModel, query)) {}
    }

    func testWhenSystemPermissionIsGrantedAfterTimeoutThenPendingDecisionIsSubmitted() async throws {
        let (viewModel, query) = makeViewModelWaitingForSystemPermission(decision: .alwaysAllow)
        XCTAssertEqual(scheduledWork.map(\.delay), [PermissionAuthorizationViewModel.Constants.systemPermissionRequestTimeout])
        runScheduledWork()

        XCTAssertEqual(viewModel.viewState.systemPermissionStep?.phase, .openSettings)
        XCTAssertNil(result)

        respondToSystemPermissionRequest(with: .authorized)
        await waitUntil { self.result != nil }

        let output = try XCTUnwrap(try result?.get())
        XCTAssertTrue(output.granted)
        XCTAssertEqual(output.remember, true)
        XCTAssertEqual(finishCount, 1)
        withExtendedLifetime((viewModel, query)) {}
    }

    func testTimeoutOfEarlierRequestDoesNotEndLaterRequest() async {
        let (viewModel, query) = makeViewModelWaitingForSystemPermission(decision: .alwaysAllow)
        respondToSystemPermissionRequest(with: .notDetermined)
        await waitUntil { viewModel.viewState.systemPermissionStep?.phase == .request }
        viewModel.send(action: .requestSystemPermission)

        scheduledWork.removeFirst().work()

        XCTAssertEqual(viewModel.viewState.systemPermissionStep?.phase, .waiting)
        withExtendedLifetime(query) {}
    }

    func testDismissDuringSystemPermissionStepCancelsWithoutSavingAndIgnoresLaterGrant() async throws {
        let (viewModel, query) = makeViewModelWaitingForSystemPermission(decision: .alwaysAllow)

        viewModel.send(action: .dismiss)
        respondToSystemPermissionRequest(with: .authorized)
        appDidBecomeActive.send()
        await settle()

        XCTAssertThrowsError(try XCTUnwrap(result).get())
        XCTAssertTrue(query.wasDismissed)
        XCTAssertTrue(pixelFiring.actualFireCalls.isEmpty)
        XCTAssertEqual(finishCount, 1)
        withExtendedLifetime((viewModel, query)) {}
    }

    func testWhenMacOSBlocksAccessThenAlwaysAllowIsSavedWithoutGrantingTheRequest() throws {
        for permissions in Self.permissionsBlockableByMacOS {
            pixelFiring = PixelKitMock()
            let prompt = try showPrompt(for: permissions, systemPermissionState: .denied)

            prompt.viewModel.send(action: .alwaysAllow)

            XCTAssertEqual(prompt.phase, .openSettings)
            XCTAssertEqual(prompt.savedDecisions, permissions.map { _ in .allow })
            XCTAssertTrue(pageDecisions.isEmpty)
            XCTAssertEqual(firedPixelNames, allowDecisionPixelNames(for: permissions))
        }
    }

    func testWhenPromptIsClosedAfterMacOSDeniedItsPromptThenAlwaysAllowStaysSavedAndRequestIsDenied() async throws {
        let prompt = try showPrompt(for: [.notification], systemPermissionState: .notDetermined)
        systemPermissionManager.defersAuthorizationResponse = true
        prompt.viewModel.send(action: .alwaysAllow)
        prompt.viewModel.send(action: .requestSystemPermission)
        await denySystemPermissionRequest()

        prompt.viewModel.send(action: .dismiss)

        XCTAssertEqual(pageDecisions, [false])
        XCTAssertEqual(prompt.savedDecisions, [.allow])
    }

    func testWhenSiteIsAlreadyAlwaysAllowedThenPromptOpensOnSystemPermissionStepWithoutSavingAgain() throws {
        let expectedPhases: [(SystemPermissionAuthorizationState, PermissionAuthorizationViewState.SystemPermissionStep.Phase)] = [
            (.denied, .openSettings),
            (.notDetermined, .request),
        ]
        for (systemPermissionState, expectedPhase) in expectedPhases {
            let prompt = try showPrompt(for: [.notification], systemPermissionState: systemPermissionState, savedDecision: .allow)

            XCTAssertEqual(prompt.phase, expectedPhase)
            XCTAssertNil(prompt.viewModel.viewState.decision)
            XCTAssertEqual(prompt.manager.setPermissionCalls.count, 1, "Saving again would move the site in Settings' Recent list")
            XCTAssertTrue(firedPixelNames.isEmpty)
        }
    }

    func testWhenSiteIsAlwaysAllowedAndSystemPermissionIsGrantedOnReturnThenRequestIsGrantedWithoutDecisionPixel() async throws {
        systemPermissionManager.notificationAuthorizationStateSubject.send(.denied)
        let query = makeQuery(permissions: [.notification])
        query.opensOnSystemPermissionStep = true
        let viewModel = makeViewModel(query: query)
        viewModel.send(action: .onAppear)

        XCTAssertEqual(viewModel.viewState.systemPermissionStep?.phase, .openSettings)
        XCTAssertNil(result)
        XCTAssertTrue(systemPermissionManager.authorizationRequestedFor.isEmpty)

        systemPermissionManager.notificationAuthorizationStateSubject.send(.authorized)
        appDidBecomeActive.send()
        await waitUntil { self.result != nil }

        let output = try XCTUnwrap(try result?.get())
        XCTAssertTrue(output.granted)
        XCTAssertEqual(output.remember, true)
        XCTAssertTrue(pixelFiring.actualFireCalls.isEmpty)
        XCTAssertEqual(finishCount, 1)
        withExtendedLifetime((viewModel, query)) {}
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
        _ action: PermissionAuthorizationViewModel.Action,
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
        initialState: PermissionAuthorizationViewState = .init()
    ) -> PermissionAuthorizationViewModel {
        PermissionAuthorizationViewModel(
            initialState: initialState,
            query: query,
            systemPermissionManager: systemPermissionManager,
            appDidBecomeActivePublisher: appDidBecomeActive.eraseToAnyPublisher(),
            scheduleAfter: { [weak self] delay, work in self?.scheduledWork.append((delay, work)) },
            pixelFiring: pixelFiring,
            openURL: { [weak self] in self?.openedURLs.append($0) },
            openSystemSettingsURL: { [weak self] in self?.openedSystemSettingsURLs.append($0) },
            finish: { [weak self] in self?.finishCount += 1 }
        )
    }

    // MARK: - Prompt shown through a permission model

    private static let permissionsBlockableByMacOS: [[PermissionType]] = [[.notification], [.geolocation], [.camera, .microphone]]

    @MainActor
    private struct SitePrompt {
        let model: PermissionModel
        let manager: PermissionManagerMock
        let query: PermissionAuthorizationQuery
        let viewModel: PermissionAuthorizationViewModel

        var phase: PermissionAuthorizationViewState.SystemPermissionStep.Phase? {
            viewModel.viewState.systemPermissionStep?.phase
        }

        var savedDecisions: [PersistedPermissionDecision?] {
            query.permissions.map { manager.persistedDecision(forDomain: query.domain, permissionType: $0) }
        }
    }

    /// example.com asks for `permissions` with the new prompt on, every macOS permission in `systemPermissionState`,
    /// and the site's `savedDecision`. The prompt is shown; the page's answers are recorded in `pageDecisions`.
    private func showPrompt(
        for permissions: [PermissionType],
        systemPermissionState: SystemPermissionAuthorizationState,
        savedDecision: PersistedPermissionDecision? = nil
    ) throws -> SitePrompt {
        systemPermissionManager = SystemPermissionManagerMock()
        systemPermissionManager.defaultAuthorizationState = systemPermissionState
        systemPermissionManager.notificationAuthorizationStateSubject.send(systemPermissionState)
        let manager = PermissionManagerMock()
        if let savedDecision {
            permissions.forEach { manager.setPermission(savedDecision, forDomain: "example.com", permissionType: $0) }
        }
        let featureFlagger = MockFeatureFlagger()
        featureFlagger.featuresStub[FeatureFlag.websitePermissionsPrompts.rawValue] = true
        let model = PermissionModel(permissionManager: manager,
                                    geolocationService: GeolocationServiceMock(),
                                    systemPermissionManager: systemPermissionManager,
                                    featureFlagger: featureFlagger)

        pageDecisions = []
        model.permissions(permissions, requestedForDomain: "example.com") { [weak self] (granted: Bool) in
            self?.pageDecisions.append(granted)
        }
        let query = try XCTUnwrap(model.authorizationQuery)
        let viewModel = makeViewModel(query: query)
        viewModel.send(action: .onAppear)

        let prompt = SitePrompt(model: model, manager: manager, query: query, viewModel: viewModel)
        sitePrompt = prompt
        return prompt
    }

    private func denySystemPermissionRequest() async {
        systemPermissionManager.notificationAuthorizationStateSubject.send(.denied)
        respondToSystemPermissionRequest(with: .denied)
        await waitUntil { self.sitePrompt?.phase == .openSettings }
    }

    private var firedPixelNames: [String] {
        pixelFiring.actualFireCalls.map(\.pixel.name)
    }

    private func allowDecisionPixelNames(for permissions: [PermissionType]) -> [String] {
        permissions.map { PermissionPixel.authorizationDecision(permissionType: $0, decision: .allow).name }
    }

    /// Notifications not asked by macOS yet, the allow `decision` picked, and Request Permission pressed.
    private func makeViewModelWaitingForSystemPermission(
        decision: PermissionAuthorizationViewModel.Action
    ) -> (PermissionAuthorizationViewModel, PermissionAuthorizationQuery) {
        systemPermissionManager.notificationAuthorizationStateSubject.send(.notDetermined)
        systemPermissionManager.defersAuthorizationResponse = true
        let query = makeQuery(permissions: [.notification])
        let viewModel = makeViewModel(query: query)
        viewModel.send(action: decision)
        viewModel.send(action: .requestSystemPermission)
        return (viewModel, query)
    }

    private func respondToSystemPermissionRequest(with state: SystemPermissionAuthorizationState) {
        systemPermissionManager.pendingAuthorizationCompletions.last?(state)
    }

    private func runScheduledWork() {
        let work = scheduledWork
        scheduledWork = []
        work.forEach { $0.work() }
    }

    /// Lets the main-actor tasks the view model starts from callbacks run.
    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<100 where !condition() {
            await Task.yield()
        }
        XCTAssertTrue(condition(), file: file, line: line)
    }

    private func settle() async {
        for _ in 0..<20 {
            await Task.yield()
        }
    }
}

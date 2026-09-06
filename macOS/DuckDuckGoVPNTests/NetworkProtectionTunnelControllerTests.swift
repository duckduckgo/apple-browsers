//
//  NetworkProtectionTunnelControllerTests.swift
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

import Foundation
import NetworkExtension
import Networking
import NetworkingTestingUtils
import NetworkProtectionUI
import PixelKit
import PixelKitTestingUtilities
import PrivacyConfig
import Subscription
import SubscriptionTestingUtilities
import SystemExtensionManager
import VPN
import VPNAppState
import XCTest
@testable import DuckDuckGoVPN

/// Characterises what the VPN enable flow reports for each scenario a real user can hit.
///
/// These tests describe today's behaviour, including the places where it is wrong. Where an outcome
/// misrepresents what the user experienced, the test says so in its name and in a comment, so the
/// misclassification is visible rather than implied. Do not "fix" a test here without also changing the
/// controller, and vice versa.
///
@MainActor
final class NetworkProtectionTunnelControllerTests: XCTestCase {

    private enum PixelName {
        static let attempt = "netp_controller_start_attempt"
        static let success = "netp_controller_start_success"
        static let failure = "netp_controller_start_failure"
        static let cancelled = "netp_controller_start_cancelled"
        static let systemExtensionActivationAttempt = "netp_system_extension_activation_attempt"
        static let systemExtensionActivationFailure = "netp_system_extension_activation_failure"
    }

    private enum TestError: CustomNSError, Equatable {
        case tokenRequestFailed

        static var errorDomain: String {
            "NetworkProtectionTunnelControllerTests.TestError"
        }

        var errorCode: Int {
            1
        }
    }

    private static let sysexBundleID = "com.duckduckgo.test.vpn.sysex"
    private static let appexBundleID = "com.duckduckgo.test.vpn.appex"

    private var defaults: UserDefaults!
    private var defaultsSuiteName: String!
    private var pixelDefaults: UserDefaults!
    private var pixelDefaultsSuiteName: String!
    private var firedPixels: FiredPixelRecorder!
    private var wideEvent: WideEventMock!

    /// The store behind the message the VPN UI shows the user. Pointed at the test's own suite so it
    /// neither reads nor writes the real one.
    private var errorStore: NetworkProtectionControllerErrorStore!

    override func setUp() {
        super.setUp()
        defaultsSuiteName = "NetworkProtectionTunnelControllerTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)

        pixelDefaultsSuiteName = "NetworkProtectionTunnelControllerTests-pixels-\(UUID().uuidString)"
        pixelDefaults = UserDefaults(suiteName: pixelDefaultsSuiteName)

        wideEvent = WideEventMock()
        errorStore = NetworkProtectionControllerErrorStore(userDefaults: defaults)

        firedPixels = FiredPixelRecorder()
        installPixelKit()
    }

    override func tearDown() {
        PixelKit.tearDown()
        firedPixels = nil
        wideEvent = nil
        errorStore = nil

        pixelDefaults.removePersistentDomain(forName: pixelDefaultsSuiteName)
        pixelDefaults = nil
        pixelDefaultsSuiteName = nil

        defaults.removePersistentDomain(forName: defaultsSuiteName)
        defaults = nil
        defaultsSuiteName = nil
        super.tearDown()
    }

    // MARK: - Startup option preparation

    func testPrepareStartupOptionsWhenBothTokenRequestsSucceedThenUsesTheTokenPreparedForTheTunnel() async throws {
        let tunnelToken = OAuthTokensFactory.makeValidTokenContainer()
        let refreshedAppToken = OAuthTokensFactory.makeTokenContainer(thatExpiresIn: 7_200)
        let subscriptionManager = SubscriptionManagerMock()
        subscriptionManager.getTokenContainerResults = [
            .success(tunnelToken),
            .success(refreshedAppToken)
        ]
        let controller = makeController(subscriptionManager: subscriptionManager)

        let options = try await controller.prepareStartupOptions()

        let tokenData = try XCTUnwrap(options[NetworkProtectionOptionKey.tokenContainer] as? NSData)
        XCTAssertEqual(try TokenContainer(with: tokenData), tunnelToken)
        XCTAssertEqual(subscriptionManager.getTokenContainerCalls, [
            AuthTokensCachePolicy.localValid.description,
            AuthTokensCachePolicy.localForceRefresh.description
        ])
    }

    func testPrepareStartupOptionsWhenNoLocalTokenIsAvailableThenMapsTheErrorAndSkipsTheForcedRefresh() async {
        let subscriptionManager = SubscriptionManagerMock()
        subscriptionManager.getTokenContainerResults = [
            .failure(SubscriptionManagerError.noTokenAvailable)
        ]
        let controller = makeController(subscriptionManager: subscriptionManager)

        do {
            _ = try await controller.prepareStartupOptions()
            XCTFail("Expected startup option preparation to fail")
        } catch NetworkProtectionTunnelController.StartError.noAuthToken {
            XCTAssertEqual(subscriptionManager.getTokenContainerCalls, [
                AuthTokensCachePolicy.localValid.description
            ])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testPrepareStartupOptionsWhenInitialTokenRetrievalFailsThenMapsTheErrorAndSkipsTheForcedRefresh() async {
        let underlyingError = TestError.tokenRequestFailed
        let subscriptionManager = SubscriptionManagerMock()
        subscriptionManager.getTokenContainerResults = [
            .failure(SubscriptionManagerError.errorRetrievingTokenContainer(error: underlyingError))
        ]
        let controller = makeController(subscriptionManager: subscriptionManager)

        do {
            _ = try await controller.prepareStartupOptions()
            XCTFail("Expected startup option preparation to fail")
        } catch NetworkProtectionTunnelController.StartError.failedToFetchAuthToken(let error) {
            let error = error as NSError
            XCTAssertEqual(error.domain, SubscriptionManagerError.errorDomain)
            XCTAssertEqual(error.code, 12001)
            XCTAssertEqual(error.userInfo[NSUnderlyingErrorKey] as? TestError, underlyingError)
            XCTAssertEqual(subscriptionManager.getTokenContainerCalls, [
                AuthTokensCachePolicy.localValid.description
            ])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testPrepareStartupOptionsWhenForcedRefreshFailsThenPreservesItsTopLevelError() async {
        let tunnelToken = OAuthTokensFactory.makeValidTokenContainer()
        let underlyingError = TestError.tokenRequestFailed
        let subscriptionManager = SubscriptionManagerMock()
        subscriptionManager.getTokenContainerResults = [
            .success(tunnelToken),
            .failure(SubscriptionManagerError.errorRetrievingTokenContainer(error: underlyingError))
        ]
        let controller = makeController(subscriptionManager: subscriptionManager)

        do {
            _ = try await controller.prepareStartupOptions()
            XCTFail("Expected startup option preparation to fail")
        } catch SubscriptionManagerError.errorRetrievingTokenContainer(let error) {
            XCTAssertEqual(error as? TestError, underlyingError)
            XCTAssertEqual(subscriptionManager.getTokenContainerCalls, [
                AuthTokensCachePolicy.localValid.description,
                AuthTokensCachePolicy.localForceRefresh.description
            ])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - The user enables the VPN and it connects

    func testStartWhenTheTunnelConnectsThenReportsSuccessAndSendsTheTunnelTokenToTheExtension() async throws {
        // Deliberately the entitled fixture: `makeValidTokenContainer()` carries no entitlements at all, and
        // this test would pass with it, which is the point made by the lapsed-subscription tests below.
        let tunnelToken = OAuthTokensFactory.makeValidTokenContainerWithEntitlements()
        let tunnelManager = MockVPNTunnelManager(providerBundleID: Self.sysexBundleID)
        let controller = makeController(
            subscriptionManager: makeSubscriptionManager(results: [
                .success(tunnelToken),
                .success(OAuthTokensFactory.makeTokenContainer(thatExpiresIn: 7_200))
            ]),
            tunnelManager: tunnelManager)

        await controller.start()

        try await assertPixelFired(PixelName.success)
        assertPixelNotFired(PixelName.failure)
        XCTAssertTrue(tunnelManager.isOnDemandEnabled)

        let tokenData = try XCTUnwrap(tunnelManager.startTunnelOptions?[NetworkProtectionOptionKey.tokenContainer] as? NSData)
        XCTAssertEqual(try TokenContainer(with: tokenData), tunnelToken)
    }

    // MARK: - The user has no subscription

    func testStartWhenThereIsNoTokenThenReportsFailureWithNoAuthToken() async throws {
        let controller = makeController(
            subscriptionManager: makeSubscriptionManager(results: [
                .failure(SubscriptionManagerError.noTokenAvailable)
            ]))

        await controller.start()

        let pixel = try await assertPixelFired(PixelName.failure)
        XCTAssertEqual(pixel.parameters[PixelKit.Parameters.errorDomain], NetworkProtectionTunnelController.StartError.errorDomain)
        XCTAssertEqual(pixel.parameters[PixelKit.Parameters.errorCode], "1")
        assertPixelNotFired(PixelName.success)
    }

    // MARK: - The token the tunnel needs can't be fetched

    /// The dominant enable failure in production: `StartError.failedToFetchAuthToken` (201) wrapping an
    /// `APIRequestV2Error.urlSession` (11400). The token the extension needs is genuinely unavailable, so
    /// failing the start is correct here.
    func testStartWhenTheTunnelTokenFetchFailsThenReportsFailureWithFailedToFetchAuthToken() async throws {
        let controller = makeController(
            subscriptionManager: makeSubscriptionManager(results: [
                .failure(SubscriptionManagerError.errorRetrievingTokenContainer(error: APIRequestV2Error.urlSession(URLError(.notConnectedToInternet))))
            ]))

        await controller.start()

        let pixel = try await assertPixelFired(PixelName.failure)
        XCTAssertEqual(pixel.parameters[PixelKit.Parameters.errorDomain], NetworkProtectionTunnelController.StartError.errorDomain)
        XCTAssertEqual(pixel.parameters[PixelKit.Parameters.errorCode], "201")
        XCTAssertEqual(pixel.parameters[PixelKit.Parameters.underlyingErrorDomain], SubscriptionManagerError.errorDomain)
        XCTAssertEqual(pixel.parameters[PixelKit.Parameters.underlyingErrorCode], "12001")
        assertPixelNotFired(PixelName.success)
    }

    // MARK: - The token-branching refresh fails after the tunnel token was already obtained

    /// MISREPORTS THE USER'S EXPERIENCE. The tunnel token has already been fetched and is sitting in the
    /// startup options; only the follow-up `.localForceRefresh` that branches the app's token from the
    /// extension's has failed. The VPN could have started, but the raw `SubscriptionManagerError` propagates
    /// out of `prepareStartupOptions()`, `startVPNTunnel` is never called, and the enable is counted as a
    /// failure. This is ~29% of production enable failures, reported under domain
    /// `SubscriptionManagerError` / code 12001 rather than a `StartError`.
    func testStartWhenTheTokenBranchingRefreshFailsThenReportsFailureEvenThoughTheTunnelTokenWasAvailable() async throws {
        let tunnelManager = MockVPNTunnelManager(providerBundleID: Self.sysexBundleID)
        let controller = makeController(
            subscriptionManager: makeSubscriptionManager(results: [
                .success(OAuthTokensFactory.makeValidTokenContainer()),
                .failure(SubscriptionManagerError.errorRetrievingTokenContainer(error: APIRequestV2Error.urlSession(URLError(.timedOut))))
            ]),
            tunnelManager: tunnelManager)

        await controller.start()

        let pixel = try await assertPixelFired(PixelName.failure)
        XCTAssertEqual(pixel.parameters[PixelKit.Parameters.errorDomain], SubscriptionManagerError.errorDomain)
        XCTAssertEqual(pixel.parameters[PixelKit.Parameters.errorCode], "12001")
        assertPixelNotFired(PixelName.success)

        // The tunnel was never asked to start, despite a usable token having been fetched.
        XCTAssertNil(tunnelManager.startTunnelOptions)
    }

    // MARK: - The tunnel starts but never confirms a healthy connection

    func testStartWhenTheStartupMonitorTimesOutThenReportsFailureWithStartTunnelFailure() async throws {
        let tunnelManager = MockVPNTunnelManager(providerBundleID: Self.sysexBundleID)
        tunnelManager.startSuccessError = VPNStartupMonitor.StartupError.startTunnelTimedOut
        let controller = makeController(
            subscriptionManager: makeSubscriptionManager(results: [
                .success(OAuthTokensFactory.makeValidTokenContainer()),
                .success(OAuthTokensFactory.makeTokenContainer(thatExpiresIn: 7_200))
            ]),
            tunnelManager: tunnelManager)

        await controller.start()

        let pixel = try await assertPixelFired(PixelName.failure)
        XCTAssertEqual(pixel.parameters[PixelKit.Parameters.errorDomain], NetworkProtectionTunnelController.StartError.errorDomain)
        XCTAssertEqual(pixel.parameters[PixelKit.Parameters.errorCode], "100")
        XCTAssertEqual(pixel.parameters[PixelKit.Parameters.underlyingErrorCode], "2")
        assertPixelNotFired(PixelName.success)
        XCTAssertNotNil(tunnelManager.startTunnelOptions)
    }

    func testStartWhenTheTunnelDisconnectsSilentlyThenReportsFailureWithStartTunnelFailure() async throws {
        let tunnelManager = MockVPNTunnelManager(providerBundleID: Self.sysexBundleID)
        tunnelManager.startSuccessError = VPNStartupMonitor.StartupError.startTunnelDisconnectedSilently(underlyingError: nil)
        let controller = makeController(
            subscriptionManager: makeSubscriptionManager(results: [
                .success(OAuthTokensFactory.makeValidTokenContainer()),
                .success(OAuthTokensFactory.makeTokenContainer(thatExpiresIn: 7_200))
            ]),
            tunnelManager: tunnelManager)

        await controller.start()

        let pixel = try await assertPixelFired(PixelName.failure)
        XCTAssertEqual(pixel.parameters[PixelKit.Parameters.errorCode], "100")
        XCTAssertEqual(pixel.parameters[PixelKit.Parameters.underlyingErrorCode], "1")
        assertPixelNotFired(PixelName.success)
    }

    // MARK: - The user is asked to allow the system extension

    /// MISREPORTS THE USER'S EXPERIENCE. Activation completes while the extension is still awaiting the
    /// user's approval, so the controller opens System Settings and returns without starting a tunnel. That
    /// early `return` is not an error, so the top-level `start()` treats it as a completed start and fires
    /// the success pixel. First-run users who have not yet approved the extension therefore inflate the
    /// numerator of the enable rate.
    func testStartWhenTheExtensionIsStillAwaitingApprovalThenReportsSuccessWithoutStartingTheTunnel() async throws {
        let networkExtensionController = MockNetworkExtensionController()
        networkExtensionController.reportsWaitingForUserApproval = true
        networkExtensionController.activationState = .awaitingUserApproval

        let tunnelManager = MockVPNTunnelManager(providerBundleID: Self.sysexBundleID)
        let controller = makeController(
            subscriptionManager: makeSubscriptionManager(results: [
                .success(OAuthTokensFactory.makeValidTokenContainer()),
                .success(OAuthTokensFactory.makeTokenContainer(thatExpiresIn: 7_200))
            ]),
            networkExtensionController: networkExtensionController,
            tunnelManager: tunnelManager)

        await controller.start()

        try await assertPixelFired(PixelName.success)
        assertPixelNotFired(PixelName.failure)
        assertPixelNotFired(PixelName.cancelled)

        XCTAssertTrue(networkExtensionController.didOpenSystemExtensionSettings)
        XCTAssertNil(tunnelManager.startTunnelOptions)
        XCTAssertEqual(controller.onboardingStatusRawValue, OnboardingStatus.isOnboarding(step: .userNeedsToAllowExtension).rawValue)
    }

    /// MISREPORTS THE USER'S EXPERIENCE. `SystemExtensionManager` gives the user 120 seconds to approve the
    /// extension before throwing `requestTimedOut`. A user who leaves the approval prompt alone for longer
    /// than that has not experienced a product failure, but the timeout is reported as a hard enable failure
    /// (domain `SystemExtensionManager.SystemExtensionRequestError`, code 2) rather than a cancellation.
    func testStartWhenTheApprovalPromptTimesOutThenReportsFailureRatherThanACancellation() async throws {
        let networkExtensionController = MockNetworkExtensionController()
        networkExtensionController.reportsWaitingForUserApproval = true
        networkExtensionController.activationError = SystemExtensionRequestError.requestTimedOut

        let controller = makeController(
            subscriptionManager: makeSubscriptionManager(),
            networkExtensionController: networkExtensionController)

        await controller.start()

        try await assertPixelFired(PixelName.systemExtensionActivationFailure)
        let pixel = try await assertPixelFired(PixelName.failure)
        XCTAssertEqual(pixel.parameters[PixelKit.Parameters.errorCode], "2")
        assertPixelNotFired(PixelName.cancelled)
        assertPixelNotFired(PixelName.success)
    }

    /// The one activation outcome that is classified correctly: `NetworkExtensionController` maps
    /// `OSSystemExtensionError.requestCanceled` to a `CancellationError`, which the controller reports as a
    /// cancellation and excludes from the enable rate.
    func testStartWhenTheUserCancelsExtensionApprovalThenReportsCancelled() async throws {
        let networkExtensionController = MockNetworkExtensionController()
        networkExtensionController.reportsWaitingForUserApproval = true
        networkExtensionController.activationError = CancellationError()

        let controller = makeController(
            subscriptionManager: makeSubscriptionManager(),
            networkExtensionController: networkExtensionController)

        await controller.start()

        try await assertPixelFired(PixelName.cancelled)
        assertPixelNotFired(PixelName.failure)
        assertPixelNotFired(PixelName.success)
    }

    // MARK: - The user declines the VPN configuration prompt

    /// Classified correctly: refusing the VPN configuration prompt surfaces as
    /// `NEVPNError.configurationReadWriteFailed`, which the controller reports as a cancellation.
    func testStartWhenTheVPNConfigurationPromptIsDeclinedThenReportsCancelled() async throws {
        let tunnelManager = MockVPNTunnelManager(providerBundleID: Self.sysexBundleID)
        tunnelManager.saveError = NEVPNError(.configurationReadWriteFailed)
        let controller = makeController(
            subscriptionManager: makeSubscriptionManager(),
            tunnelManager: tunnelManager)

        await controller.start()

        try await assertPixelFired(PixelName.cancelled)
        assertPixelNotFired(PixelName.failure)
        assertPixelNotFired(PixelName.success)
        XCTAssertEqual(controller.onboardingStatusRawValue,
                       OnboardingStatus.isOnboarding(step: .userNeedsToAllowVPNConfiguration).rawValue)
    }

    // MARK: - The subscription lapsed while the access token was still inside its window

    /// MISREPORTS THE USER'S EXPERIENCE. `.localValid` refreshes on access-token expiry only, never on
    /// entitlement loss, so for up to the token's remaining lifetime a lapsed subscriber still holds a
    /// structurally valid token. Nothing between `fetchTokenContainer()` and `startTunnel(options:)`
    /// inspects `subscriptionEntitlements`, so the controller forwards it and reports the enable as a
    /// success. Whatever the extension decides afterwards happens after the pixel has already been sent.
    func testStartWhenTheTokenCarriesNoVPNEntitlementThenReportsSuccessAndForwardsItAnyway() async throws {
        let unentitledToken = OAuthTokensFactory.makeValidTokenContainer()
        XCTAssertFalse(unentitledToken.decodedAccessToken.hasEntitlement(.networkProtection),
                       "Fixture precondition: this token must carry no VPN entitlement")

        let tunnelManager = MockVPNTunnelManager(providerBundleID: Self.sysexBundleID)
        let controller = makeController(
            subscriptionManager: makeSubscriptionManager(results: [
                .success(unentitledToken),
                .success(OAuthTokensFactory.makeTokenContainer(thatExpiresIn: 7_200))
            ]),
            tunnelManager: tunnelManager)

        await controller.start()

        try await assertPixelFired(PixelName.success)
        assertPixelNotFired(PixelName.failure)

        let tokenData = try XCTUnwrap(tunnelManager.startTunnelOptions?[NetworkProtectionOptionKey.tokenContainer] as? NSData)
        let forwardedToken = try TokenContainer(with: tokenData)
        XCTAssertTrue(forwardedToken.decodedAccessToken.subscriptionEntitlements.isEmpty)
    }

    /// MISREPORTS THE USER'S EXPERIENCE. The controller performs no expiry check of its own on the token it
    /// forwards, so an already-expired one is passed to the extension and the enable is reported as a
    /// success. Reachable in the field through clock skew, since expiry is judged against the local clock.
    func testStartWhenTheTokenHasAlreadyExpiredThenReportsSuccessAndForwardsItAnyway() async throws {
        let expiredToken = OAuthTokensFactory.makeExpiredTokenContainer()
        let tunnelManager = MockVPNTunnelManager(providerBundleID: Self.sysexBundleID)
        let controller = makeController(
            subscriptionManager: makeSubscriptionManager(results: [
                .success(expiredToken),
                .success(OAuthTokensFactory.makeTokenContainer(thatExpiresIn: 7_200))
            ]),
            tunnelManager: tunnelManager)

        await controller.start()

        try await assertPixelFired(PixelName.success)
        assertPixelNotFired(PixelName.failure)

        let tokenData = try XCTUnwrap(tunnelManager.startTunnelOptions?[NetworkProtectionOptionKey.tokenContainer] as? NSData)
        XCTAssertEqual(try TokenContainer(with: tokenData), expiredToken)
    }

    // MARK: - What the user is told when authentication fails

    /// MISREPORTS THE USER'S EXPERIENCE. `SubscriptionManager` throws `noTokenAvailable` not only when the
    /// user genuinely has no subscription, but also after it has just silently signed them out: on
    /// `OAuthClientError.unknownAccount`, and when recovery of an invalid refresh token fails or is not
    /// attempted. A paying subscriber whose refresh token was invalidated is therefore told they need to
    /// buy a subscription, which is a wrong diagnosis stated as fact and sends them to the wrong remedy.
    func testStartWhenTokenRetrievalReportsNoTokenThenTellsTheUserTheyNeedASubscription() async throws {
        let controller = makeController(
            subscriptionManager: makeSubscriptionManager(results: [
                .failure(SubscriptionManagerError.noTokenAvailable)
            ]))

        await controller.start()

        try await assertPixelFired(PixelName.failure)
        XCTAssertEqual(errorStore.lastErrorMessage, "You need a subscription to start the VPN")
    }

    /// By contrast, a transient network failure fetching the token surfaces the underlying networking
    /// error's own description, which is not phrased for an end user either but at least does not
    /// misattribute the cause.
    func testStartWhenTheTunnelTokenFetchFailsThenShowsTheUnderlyingNetworkingError() async throws {
        let controller = makeController(
            subscriptionManager: makeSubscriptionManager(results: [
                .failure(SubscriptionManagerError.errorRetrievingTokenContainer(error: APIRequestV2Error.urlSession(URLError(.notConnectedToInternet))))
            ]))

        await controller.start()

        try await assertPixelFired(PixelName.failure)
        let message = try XCTUnwrap(errorStore.lastErrorMessage)
        XCTAssertNotEqual(message, "You need a subscription to start the VPN")
    }

    // MARK: - Two enable requests arriving at once

    /// Nothing guards `start()` against re-entry. An enable arriving over IPC while the `connectOnLogin`
    /// auto-start is still in flight runs the whole flow twice: two attempts, and four token requests where
    /// two would do, which doubles the auth load exactly when the network is least likely to be up. The
    /// controller also holds a single `connectionWideEventData`, so the second attempt retires the first
    /// flow as `unknown` and then overwrites the property, losing the first attempt's measurements.
    func testConcurrentStartRequestsEachRunTheFullAuthFlow() async throws {
        let subscriptionManager = makeSubscriptionManager(results: [
            .success(OAuthTokensFactory.makeValidTokenContainerWithEntitlements()),
            .success(OAuthTokensFactory.makeTokenContainer(thatExpiresIn: 7_200)),
            .success(OAuthTokensFactory.makeValidTokenContainerWithEntitlements()),
            .success(OAuthTokensFactory.makeTokenContainer(thatExpiresIn: 7_200))
        ])
        let controller = makeController(subscriptionManager: subscriptionManager)

        async let first: Void = controller.start()
        async let second: Void = controller.start()
        _ = await (first, second)

        try await assertPixelFired(PixelName.success)
        XCTAssertEqual(firedPixels.count(containing: "\(PixelName.attempt)_c"), 2)
        XCTAssertEqual(subscriptionManager.getTokenContainerCalls.count, 4)

        let abandonedFlows = wideEvent.completions.filter { _, status in
            if case .unknown = status { return true } else { return false }
        }
        XCTAssertFalse(abandonedFlows.isEmpty, "Expected the first flow to be retired as unknown by the second attempt")
    }

    // MARK: - The user enables the VPN while it is already connected

    /// MISREPORTS THE USER'S EXPERIENCE, and in the direction that flatters the metric. When the tunnel is
    /// already connected the controller stops it "to allow recovery" and returns without throwing, so
    /// `start()` treats the pass as complete and fires the success pixel. The user asked for the VPN to be
    /// on, it ends up off, and the enable counts as a success. No token is fetched and no tunnel is started.
    func testStartWhenAlreadyConnectedThenStopsTheTunnelAndStillReportsSuccess() async throws {
        let tunnelManager = MockVPNTunnelManager(providerBundleID: Self.sysexBundleID)
        tunnelManager.connectionStatus = .connected
        let subscriptionManager = makeSubscriptionManager()
        let controller = makeController(subscriptionManager: subscriptionManager, tunnelManager: tunnelManager)

        await controller.start()

        try await assertPixelFired(PixelName.success)
        assertPixelNotFired(PixelName.failure)
        XCTAssertTrue(tunnelManager.didStopTunnel)
        XCTAssertNil(tunnelManager.startTunnelOptions)
        XCTAssertTrue(subscriptionManager.getTokenContainerCalls.isEmpty)
    }

    // MARK: - The tunnel connects but its on-demand rule can't be saved

    /// MISREPORTS THE USER'S EXPERIENCE. `enableOnDemand` shares a `do` block with `startTunnel`, so a
    /// preferences save that fails once the tunnel is up and healthy is reported as `startTunnelFailure`
    /// (100). The user has a working VPN that is merely missing its on-demand rule, and it counts against
    /// the enable rate. Note too that `NEVPNError.configurationReadWriteFailed` is treated as a
    /// cancellation when it surfaces from the tunnel-manager load, but as a failure here.
    func testStartWhenTheOnDemandRuleCannotBeSavedThenReportsFailureThoughTheTunnelIsUp() async throws {
        let tunnelManager = MockVPNTunnelManager(providerBundleID: Self.sysexBundleID)
        tunnelManager.saveErrorAfterTunnelStart = NEVPNError(.configurationReadWriteFailed)
        let controller = makeController(
            subscriptionManager: makeSubscriptionManager(),
            tunnelManager: tunnelManager)

        await controller.start()

        let pixel = try await assertPixelFired(PixelName.failure)
        XCTAssertEqual(pixel.parameters[PixelKit.Parameters.errorCode], "100")
        XCTAssertEqual(pixel.parameters[PixelKit.Parameters.underlyingErrorDomain], NEVPNError.errorDomain)
        XCTAssertEqual(pixel.parameters[PixelKit.Parameters.underlyingErrorCode],
                       "\(NEVPNError.Code.configurationReadWriteFailed.rawValue)")
        assertPixelNotFired(PixelName.cancelled)
        assertPixelNotFired(PixelName.success)

        // The tunnel did start and the startup monitor confirmed it before this failed.
        XCTAssertNotNil(tunnelManager.startTunnelOptions)
    }

    // MARK: - The VPN configuration reports an invalid connection

    /// The configuration recovers on the retry: the controller drops its cached manager, reloads, and the
    /// second pass connects. The retry re-runs system extension activation, so activation is attempted
    /// twice for a single user-visible enable.
    func testStartWhenTheConfigurationIsInvalidOnceThenRetriesAndConnects() async throws {
        let invalidManager = MockVPNTunnelManager(providerBundleID: Self.sysexBundleID)
        invalidManager.connectionStatus = .invalid
        let recoveredManager = MockVPNTunnelManager(providerBundleID: Self.sysexBundleID)

        // The flow loads three times: resolving system state, the first start attempt, and once more after
        // the invalid manager is dropped. Only the third load sees a usable configuration. The
        // `loadCallCount` assertion below exists so that a change in the flow's shape fails loudly here
        // rather than silently testing something else.
        let store = MockVPNTunnelManagerStore(managers: [invalidManager, invalidManager, recoveredManager])
        let networkExtensionController = MockNetworkExtensionController()
        let controller = makeController(
            subscriptionManager: makeSubscriptionManager(),
            networkExtensionController: networkExtensionController,
            tunnelManagerStore: store)

        await controller.start()

        try await assertPixelFired(PixelName.success)
        assertPixelNotFired(PixelName.failure)
        XCTAssertEqual(store.loadCallCount, 3)
        XCTAssertEqual(networkExtensionController.activationCount, 2)
        XCTAssertNotNil(recoveredManager.startTunnelOptions)
        XCTAssertNil(invalidManager.startTunnelOptions)
    }

    /// The configuration stays invalid, so the single retry is exhausted and the start fails with
    /// `connectionStatusInvalid` (2). Nothing reaches the auth step, so no token is requested.
    func testStartWhenTheConfigurationStaysInvalidThenReportsConnectionStatusInvalid() async throws {
        let invalidManager = MockVPNTunnelManager(providerBundleID: Self.sysexBundleID)
        invalidManager.connectionStatus = .invalid
        let subscriptionManager = makeSubscriptionManager()
        let controller = makeController(
            subscriptionManager: subscriptionManager,
            tunnelManager: invalidManager)

        await controller.start()

        let pixel = try await assertPixelFired(PixelName.failure)
        XCTAssertEqual(pixel.parameters[PixelKit.Parameters.errorDomain], NetworkProtectionTunnelController.StartError.errorDomain)
        XCTAssertEqual(pixel.parameters[PixelKit.Parameters.errorCode], "2")
        assertPixelNotFired(PixelName.success)
        XCTAssertTrue(subscriptionManager.getTokenContainerCalls.isEmpty)
    }

    // MARK: - App Store builds, which run an app extension rather than a system extension

    /// With both extensions available and the App Store sysex flag off, the resolver selects the app
    /// extension. Nothing in the start path should touch `OSSystemExtensionManager`, so none of the
    /// system extension activation outcomes can contribute to the enable rate on this build.
    func testStartOnTheAppExtensionPathThenConnectsWithoutTouchingTheSystemExtension() async throws {
        let tunnelManager = MockVPNTunnelManager(providerBundleID: Self.appexBundleID)
        let networkExtensionController = MockNetworkExtensionController()
        let controller = makeController(
            subscriptionManager: makeSubscriptionManager(),
            availableExtensions: .both(appexBundleID: Self.appexBundleID, sysexBundleID: Self.sysexBundleID),
            networkExtensionController: networkExtensionController,
            tunnelManager: tunnelManager)

        await controller.start()

        try await assertPixelFired(PixelName.success)
        assertPixelNotFired(PixelName.failure)
        assertPixelNotFired(PixelName.systemExtensionActivationAttempt)
        XCTAssertFalse(networkExtensionController.didActivateSystemExtension)
        XCTAssertNotNil(tunnelManager.startTunnelOptions)
    }

    // MARK: - Every enable attempt reports an attempt

    func testStartAlwaysReportsAnAttemptBeforeResolvingTheOutcome() async throws {
        let controller = makeController(
            subscriptionManager: makeSubscriptionManager(results: [
                .failure(SubscriptionManagerError.noTokenAvailable)
            ]))

        await controller.start()

        try await assertPixelFired(PixelName.attempt)
        try await assertPixelFired(PixelName.failure)
    }

    // MARK: - Helpers

    private func makeController(subscriptionManager: any SubscriptionManager,
                                availableExtensions: VPNExtensionResolver.AvailableExtensions
                                    = .sysex(sysexBundleID: NetworkProtectionTunnelControllerTests.sysexBundleID),
                                networkExtensionController: MockNetworkExtensionController = MockNetworkExtensionController(),
                                tunnelManager: MockVPNTunnelManager? = nil,
                                tunnelManagerStore: MockVPNTunnelManagerStore? = nil) -> NetworkProtectionTunnelController {
        NetworkProtectionTunnelController(
            availableExtensions: availableExtensions,
            networkExtensionController: networkExtensionController,
            featureFlagger: MockFeatureFlagger(),
            settings: VPNSettings(defaults: defaults),
            defaults: defaults,
            wideEvent: wideEvent,
            notificationCenter: NotificationCenter(),
            subscriptionManager: subscriptionManager,
            vpnAppState: VPNAppState(defaults: defaults),
            tunnelManagerStore: tunnelManagerStore ?? MockVPNTunnelManagerStore(
                manager: tunnelManager ?? MockVPNTunnelManager(providerBundleID: Self.sysexBundleID)),
            controllerErrorStore: errorStore)
    }

    /// A subscription manager that answers both token calls in the start path successfully.
    private func makeSubscriptionManager(
        results: [Result<Networking.TokenContainer, Error>]? = nil
    ) -> SubscriptionManagerMock {
        let subscriptionManager = SubscriptionManagerMock()
        subscriptionManager.getTokenContainerResults = results ?? [
            .success(OAuthTokensFactory.makeValidTokenContainer()),
            .success(OAuthTokensFactory.makeTokenContainer(thatExpiresIn: 7_200))
        ]
        return subscriptionManager
    }

    private func installPixelKit() {
        PixelKit.tearDown()

        let recorder = firedPixels!
        PixelKit.setUp(dryRun: false,
                       appVersion: "1.0.0",
                       source: "test",
                       session: UUID().uuidString,
                       defaultHeaders: [:],
                       defaults: pixelDefaults) { pixelName, _, parameters, _, _, onComplete in
            recorder.record(name: pixelName, parameters: parameters)
            onComplete(true, nil)
        }
    }

    /// Waits for a pixel whose name contains `name` and returns the first match.
    ///
    /// Pixels are fired without awaiting, so a short poll is needed rather than an immediate assertion.
    @discardableResult
    private func assertPixelFired(_ name: String,
                                  timeout: TimeInterval = 3,
                                  file: StaticString = #filePath,
                                  line: UInt = #line) async throws -> FiredPixelRecorder.FiredPixel {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if let pixel = firedPixels.firstPixel(containing: name) {
                return pixel
            }
            try await Task.sleep(nanoseconds: 10 * NSEC_PER_MSEC)
        }

        XCTFail("Expected a pixel containing \"\(name)\", fired: \(firedPixels.names)", file: file, line: line)
        throw MissingPixelError(name: name)
    }

    private struct MissingPixelError: Error {
        let name: String
    }

    /// Only meaningful once the flow's terminal pixel has been observed, so call it after `assertPixelFired`.
    private func assertPixelNotFired(_ name: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNil(firedPixels.firstPixel(containing: name),
                     "Did not expect a pixel containing \"\(name)\", fired: \(firedPixels.names)",
                     file: file,
                     line: line)
    }
}

// MARK: - Test doubles

private final class FiredPixelRecorder: @unchecked Sendable {

    struct FiredPixel {
        let name: String
        let parameters: [String: String]
    }

    private let lock = NSLock()
    private var pixels: [FiredPixel] = []

    func record(name: String, parameters: [String: String]) {
        lock.lock()
        defer { lock.unlock() }
        pixels.append(FiredPixel(name: name, parameters: parameters))
    }

    var names: [String] {
        lock.lock()
        defer { lock.unlock() }
        return pixels.map(\.name)
    }

    func firstPixel(containing name: String) -> FiredPixel? {
        lock.lock()
        defer { lock.unlock() }
        return pixels.first { $0.name.contains(name) }
    }

    func count(containing name: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return pixels.filter { $0.name.contains(name) }.count
    }
}

private final class MockNetworkExtensionController: NetworkExtensionControlling {

    /// Whether activation reports back that it's waiting on the user before completing.
    var reportsWaitingForUserApproval = false
    var activationError: Error?
    var activationState: SystemExtensionActivationState = .enabled

    private(set) var didOpenSystemExtensionSettings = false
    private(set) var activationCount = 0

    var didActivateSystemExtension: Bool {
        activationCount > 0
    }

    func activateSystemExtension(waitingForUserApproval: @escaping () -> Void) async throws {
        activationCount += 1

        if reportsWaitingForUserApproval {
            waitingForUserApproval()
        }

        if let activationError {
            throw activationError
        }
    }

    func deactivateSystemExtension() async throws {}

    func openSystemExtensionSettings() {
        didOpenSystemExtensionSettings = true
    }

    func systemExtensionActivationState() async -> SystemExtensionActivationState {
        activationState
    }
}

private final class MockVPNTunnelManager: VPNTunnelManaging, @unchecked Sendable {

    var isEnabled = true
    var localizedDescription: String?
    var protocolConfiguration: NEVPNProtocol?
    var onDemandRules: [NEOnDemandRule]?
    var isOnDemandEnabled = false
    var connectionStatus: NEVPNStatus = .disconnected

    var vpnConnection: NEVPNConnection? { nil }
    var providerSession: NETunnelProviderSession? { nil }

    var loadError: Error?
    var saveError: Error?

    /// Fails preference saves only once the tunnel is running, which is the window `enableOnDemand`
    /// writes in. A plain `saveError` would instead fail the earlier configuration save.
    var saveErrorAfterTunnelStart: Error?

    var startTunnelError: Error?
    private(set) var didRemoveFromPreferences = false

    /// The error the startup monitor reports, standing in for a tunnel that starts but never confirms.
    var startSuccessError: Error?

    private(set) var startTunnelOptions: [String: NSObject]?
    private(set) var didStopTunnel = false

    init(providerBundleID: String) {
        let configuration = NETunnelProviderProtocol()
        configuration.providerBundleIdentifier = providerBundleID
        protocolConfiguration = configuration
    }

    func loadFromPreferences() async throws {
        if let loadError {
            throw loadError
        }
    }

    func saveToPreferences() async throws {
        if let saveError {
            throw saveError
        }

        if startTunnelOptions != nil, let saveErrorAfterTunnelStart {
            throw saveErrorAfterTunnelStart
        }
    }

    func removeFromPreferences() async throws {
        didRemoveFromPreferences = true
    }

    func startTunnel(options: [String: NSObject]?) throws {
        if let startTunnelError {
            throw startTunnelError
        }
        startTunnelOptions = options
    }

    func stopTunnel() {
        didStopTunnel = true
    }

    func waitForStartSuccess() async throws {
        if let startSuccessError {
            throw startSuccessError
        }
    }
}

private final class MockVPNTunnelManagerStore: VPNTunnelManagerStore, @unchecked Sendable {

    /// Handed out one per load, in order, repeating the last. This lets a test model the VPN configuration
    /// changing between the controller's cached-manager invalidations, which is what the `.invalid` retry
    /// depends on.
    private var queuedManagers: [any VPNTunnelManaging]

    private(set) var loadCallCount = 0

    init(managers: [any VPNTunnelManaging]) {
        precondition(!managers.isEmpty, "A tunnel manager store needs at least one manager")
        queuedManagers = managers
    }

    convenience init(manager: any VPNTunnelManaging) {
        self.init(managers: [manager])
    }

    func loadAllManagers() async throws -> [any VPNTunnelManaging] {
        loadCallCount += 1

        let next = queuedManagers[0]
        if queuedManagers.count > 1 {
            queuedManagers.removeFirst()
        }
        return [next]
    }

    func makeManager() -> any VPNTunnelManaging {
        queuedManagers[0]
    }
}

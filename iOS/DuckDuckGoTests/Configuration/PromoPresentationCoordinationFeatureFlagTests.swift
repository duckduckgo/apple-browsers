//
//  PromoPresentationCoordinationFeatureFlagTests.swift
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

import Core
import Combine
import FeatureFlags_iOS
import Foundation
import PersistenceTestingUtils
import PrivacyConfig
import PrivacyConfigTestsUtils
import RemoteMessaging
import Testing
@testable import DuckDuckGo

@MainActor
@Suite("Promo Presentation Coordination Feature Flag", .serialized)
struct PromoPresentationCoordinationFeatureFlagTests {

    // MARK: - Flag declaration

    @available(iOS 16, *)
    @Test("Promo presentation coordination is disabled by default", .timeLimit(.minutes(1)))
    func whenInspectingPromoPresentationCoordinationThenDefaultIsDisabled() {
        guard case .disabled = FeatureFlag.promoPresentationCoordination.defaultValue else {
            Issue.record("Expected promo presentation coordination to be disabled by default")
            return
        }
    }

    @available(iOS 16, *)
    @Test("Promo presentation coordination maps to its remote-releasable promo queue subfeature", .timeLimit(.minutes(1)))
    func whenInspectingPromoPresentationCoordinationThenSourceIsRemoteReleasablePromoQueueSubfeature() {
        guard case .remoteReleasable(let subfeature) = FeatureFlag.promoPresentationCoordination.source else {
            Issue.record("Expected promo presentation coordination to use a remote-releasable source")
            return
        }

        #expect(subfeature as? iOSPromoQueueSubfeature == .iOSPromoPresentationCoordination)
    }

    @available(iOS 16, *)
    @Test("Promo presentation coordination supports local overriding", .timeLimit(.minutes(1)))
    func whenInspectingPromoPresentationCoordinationThenLocalOverridingIsSupported() {
        #expect(FeatureFlag.promoPresentationCoordination.supportsLocalOverriding)
    }

    // MARK: - Embedded privacy configuration

    @available(iOS 16, *)
    @Test("Embedded privacy config ships no promo queue entry, so the flag default is what decides", .timeLimit(.minutes(1)))
    func whenReadingEmbeddedPrivacyConfigThenPromoQueueFeatureIsMissing() throws {
        let privacyConfig = try makeEmbeddedPrivacyConfiguration()

        guard case .disabled(.featureMissing) = privacyConfig.stateFor(featureKey: .promoQueue) else {
            Issue.record("Expected the embedded privacy config to omit the promo queue parent feature")
            return
        }

        guard case .disabled(.featureMissing) = privacyConfig.stateFor(iOSPromoQueueSubfeature.iOSPromoPresentationCoordination) else {
            Issue.record("Expected the embedded privacy config to omit the promo presentation coordination subfeature")
            return
        }
    }

    // MARK: - Startup resolution

    @available(iOS 16, *)
    @Test(
        "Factory latches the startup privacy configuration",
        .timeLimit(.minutes(1)),
        arguments: StartupPrivacyConfigurationScenario.allCases
    )
    func whenConstructingServiceThenStartupPrivacyConfigurationIsResolved(
        scenario: StartupPrivacyConfigurationScenario
    ) {
        let privacyConfigManager = makePrivacyConfigurationManager(for: scenario)
        let featureFlagger = makeDefaultFeatureFlagger(privacyConfigManager: privacyConfigManager)

        let service = makeService(
            featureFlagger: featureFlagger,
            privacyConfigManager: privacyConfigManager
        )

        #expect(service.promoCoordinationMode == scenario.expectedMode)
    }

    @available(iOS 16, *)
    @Test("Factory sees a local launch override applied before service construction", .timeLimit(.minutes(1)))
    func whenLocalLaunchOverrideIsAppliedBeforeFactoryConstructionThenServiceStartsCoordinated() throws {
        let privacyConfigManager = makePrivacyConfigurationManager(for: .embeddedDisabled)
        let overrideStore = InMemoryKeyValueStore()
        let localOverrides = FeatureFlagLocalOverrides(
            keyValueStore: overrideStore,
            actionHandler: FeatureFlagOverridesPublishingHandler<FeatureFlag>()
        )
        let launchDefaultsSuite = "PromoPresentationCoordinationFeatureFlagTests.\(UUID().uuidString)"
        let launchDefaults = try #require(UserDefaults(suiteName: launchDefaultsSuite))
        defer { launchDefaults.removePersistentDomain(forName: launchDefaultsSuite) }

        let launchOverrideKey = "ff.\(FeatureFlag.promoPresentationCoordination.rawValue)"
        launchDefaults.set("true", forKey: launchOverrideKey)
        let launchOptionsHandler = LaunchOptionsHandler(
            environment: ["UITEST_MODE": "1"],
            userDefaults: launchDefaults,
            arguments: ["-\(launchOverrideKey)", "true"],
            internalUserStore: MockInternalUserStoring(),
            isIpad: false,
            systemVersion: "18.0"
        )
        let featureFlagger = makeDefaultFeatureFlagger(
            privacyConfigManager: privacyConfigManager,
            localOverrides: localOverrides,
            allowOverrides: { launchOptionsHandler.isUITesting }
        )

        launchOptionsHandler.applyUITestOverrides(
            featureFlagOverrideStore: overrideStore,
            configRolloutStore: launchDefaults
        )
        let service = makeService(
            featureFlagger: featureFlagger,
            privacyConfigManager: privacyConfigManager
        )

        #expect(service.promoCoordinationMode == .coordinated)
    }

    @available(iOS 16, *)
    @Test("Factory samples promo mode once without subscribing", .timeLimit(.minutes(1)))
    func whenFactoryConstructsServiceThenLaterFlagUpdatesDoNotResample() {
        let privacyConfigManager = makePrivacyConfigurationManager(for: .embeddedDisabled)
        let featureFlagger = CountingPromoFeatureFlagger(isPromoPresentationCoordinationEnabled: true)
        let service = makeService(
            featureFlagger: featureFlagger,
            privacyConfigManager: privacyConfigManager
        )

        #expect(service.promoCoordinationMode == .coordinated)
        #expect(featureFlagger.promoPresentationCoordinationReadCount == 1)
        #expect(featureFlagger.updatesPublisherSubscriptionCount == 0)

        featureFlagger.isPromoPresentationCoordinationEnabled = false
        featureFlagger.triggerUpdate()

        #expect(service.promoCoordinationMode == .coordinated)
        #expect(featureFlagger.promoPresentationCoordinationReadCount == 1)
        #expect(featureFlagger.updatesPublisherSubscriptionCount == 0)
    }

    @available(iOS 16, *)
    @Test("A local override change affects only a fresh service graph", .timeLimit(.minutes(1)))
    func whenLocalOverrideChangesThenRunningGraphStaysLegacyAndFreshGraphIsCoordinated() {
        let overrideStore = InMemoryKeyValueStore()
        let firstPrivacyConfigManager = makePrivacyConfigurationManager(for: .embeddedDisabled, isInternalUser: true)
        let firstLocalOverrides = FeatureFlagLocalOverrides(
            keyValueStore: overrideStore,
            actionHandler: FeatureFlagOverridesPublishingHandler<FeatureFlag>()
        )
        let firstFeatureFlagger = makeDefaultFeatureFlagger(
            privacyConfigManager: firstPrivacyConfigManager,
            localOverrides: firstLocalOverrides,
            allowOverrides: { true }
        )
        let runningService = makeService(
            featureFlagger: firstFeatureFlagger,
            privacyConfigManager: firstPrivacyConfigManager
        )
        #expect(runningService.promoCoordinationMode == .legacy)

        firstLocalOverrides.toggleOverride(for: FeatureFlag.promoPresentationCoordination)

        #expect(firstFeatureFlagger.isFeatureOn(.promoPresentationCoordination))
        #expect(runningService.promoCoordinationMode == .legacy)

        let freshPrivacyConfigManager = makePrivacyConfigurationManager(for: .embeddedDisabled, isInternalUser: true)
        let freshLocalOverrides = FeatureFlagLocalOverrides(
            keyValueStore: overrideStore,
            actionHandler: FeatureFlagOverridesPublishingHandler<FeatureFlag>()
        )
        let freshFeatureFlagger = makeDefaultFeatureFlagger(
            privacyConfigManager: freshPrivacyConfigManager,
            localOverrides: freshLocalOverrides,
            allowOverrides: { true }
        )
        let freshService = makeService(
            featureFlagger: freshFeatureFlagger,
            privacyConfigManager: freshPrivacyConfigManager
        )

        #expect(freshService.promoCoordinationMode == .coordinated)
        #expect(runningService.promoCoordinationMode == .legacy)
    }

    @available(iOS 16, *)
    @Test("Fresh graph starts without a transient Promo Queue owner", .timeLimit(.minutes(1)))
    func whenFreshGraphIsConstructedThenItHasNoTransientOwner() {
        let privacyConfigManager = makePrivacyConfigurationManager(for: .embeddedDisabled)
        let featureFlagger = CountingPromoFeatureFlagger(isPromoPresentationCoordinationEnabled: true)
        let arbiter = PromoQueueLeaseArbiter()

        let service = makeService(
            featureFlagger: featureFlagger,
            privacyConfigManager: privacyConfigManager,
            promoQueueLeaseArbiter: arbiter
        )

        #expect(service.promoCoordinationMode == .coordinated)
        #expect(!arbiter.snapshot.hasModalLease)
        #expect(arbiter.snapshot.activeOwner == nil)
    }

    @available(iOS 16, *)
    @Test("Legacy graph bypasses Promo Queue lease acquisition", .timeLimit(.minutes(1)))
    func whenLegacyGraphRequestsVisibleAdmissionThenNoLeaseIsAcquired() {
        let privacyConfigManager = makePrivacyConfigurationManager(for: .embeddedDisabled)
        let featureFlagger = CountingPromoFeatureFlagger(isPromoPresentationCoordinationEnabled: false)
        let arbiter = PromoQueueLeaseArbiter()
        let service = makeService(
            featureFlagger: featureFlagger,
            privacyConfigManager: privacyConfigManager,
            promoQueueLeaseArbiter: arbiter
        )

        guard case .deferred = service.admitRemoteMessage(
            VisiblePromoIdentity(surfaceID: UUID(), promoType: .remoteMessage, promoID: "legacy")
        ) else {
            Issue.record("Expected legacy admission to bypass arbitration")
            return
        }

        #expect(!arbiter.snapshot.hasModalLease)
        #expect(arbiter.snapshot.activeOwner == nil)
    }

    // MARK: - Helpers

    /// The privacy configuration the app actually ships, so "disabled by default" is asserted against
    /// production data rather than a hand-written stand-in.
    private func makeEmbeddedPrivacyConfiguration() throws -> AppPrivacyConfiguration {
        let data = try PrivacyConfigurationData(data: AppPrivacyConfigurationDataProvider().embeddedData)
        return makePrivacyConfiguration(data: data)
    }

    private func makePrivacyConfiguration(data: PrivacyConfigurationData) -> AppPrivacyConfiguration {
        AppPrivacyConfiguration(
            data: data,
            identifier: "promo-presentation-coordination-tests",
            localProtection: MockDomainsProtectionStore(),
            internalUserDecider: MockInternalUserDecider()
        )
    }

    private func makePrivacyConfigurationManager(
        for scenario: StartupPrivacyConfigurationScenario,
        isInternalUser: Bool = false
    ) -> PrivacyConfigurationManager {
        let selectedData = makePromoQueuePrivacyConfigurationData(isEnabled: scenario.isEnabled)
        let embeddedData = scenario.isPersisted
            ? makePromoQueuePrivacyConfigurationData(isEnabled: !scenario.isEnabled)
            : selectedData

        return PrivacyConfigurationManager(
            fetchedETag: scenario.isPersisted ? "persisted-promo-queue-config" : nil,
            fetchedData: scenario.isPersisted ? selectedData : nil,
            embeddedDataProvider: MockEmbeddedDataProvider(data: embeddedData, etag: "embedded-promo-queue-config"),
            localProtection: MockDomainsProtectionStore(),
            internalUserDecider: MockInternalUserDecider(isInternalUser: isInternalUser)
        )
    }

    private func makePromoQueuePrivacyConfigurationData(isEnabled: Bool) -> Data {
        let state = isEnabled ? "enabled" : "disabled"
        return Data(
            """
            {
                "features": {
                    "promoQueue": {
                        "state": "enabled",
                        "features": {
                            "iOSPromoPresentationCoordination": {
                                "state": "\(state)"
                            }
                        },
                        "exceptions": []
                    }
                },
                "unprotectedTemporary": []
            }
            """.utf8
        )
    }

    private func makeDefaultFeatureFlagger(
        privacyConfigManager: PrivacyConfigurationManaging,
        localOverrides: FeatureFlagLocalOverriding? = nil,
        allowOverrides: (() -> Bool)? = nil
    ) -> DefaultFeatureFlagger {
        let previousTestMode = ProcessInfo.processInfo.environment["TESTS_FEATUREFLAGGER_MODE"]
        setenv("TESTS_FEATUREFLAGGER_MODE", "1", 1)
        defer {
            if let previousTestMode {
                setenv("TESTS_FEATUREFLAGGER_MODE", previousTestMode, 1)
            } else {
                unsetenv("TESTS_FEATUREFLAGGER_MODE")
            }
        }

        if let localOverrides {
            return DefaultFeatureFlagger(
                internalUserDecider: privacyConfigManager.internalUserDecider,
                privacyConfigManager: privacyConfigManager,
                localOverrides: localOverrides,
                allowOverrides: allowOverrides,
                experimentManager: nil,
                for: FeatureFlag.self
            )
        }

        return DefaultFeatureFlagger(
            internalUserDecider: privacyConfigManager.internalUserDecider,
            privacyConfigManager: privacyConfigManager,
            experimentManager: nil
        )
    }

    private func makeService(
        featureFlagger: FeatureFlagger,
        privacyConfigManager: PrivacyConfigurationManaging,
        promoQueueLeaseArbiter: PromoQueueLeaseArbitrating? = nil
    ) -> PromoCoordinationService {
        let subscriptionPromoCoordinator = StartupSubscriptionPromoCoordinator()
        let subscriptionPromoPresenter = SubscriptionPromoPresenter(coordinator: subscriptionPromoCoordinator)

        return PromoCoordinationFactory.makeService(
            dependency: .init(
                launchSourceManager: LaunchSourceManager(),
                contextualOnboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
                keyValueFileStoreService: InMemoryThrowingKeyValueStore(),
                privacyConfigurationManager: privacyConfigManager,
                featureFlagger: featureFlagger,
                promoQueueLeaseArbiter: promoQueueLeaseArbiter ?? PromoQueueLeaseArbiter(),
                whatsNewRepository: MockWhatsNewMessageRepository(scheduledRemoteMessage: nil),
                remoteMessagingActionHandler: MockRemoteMessagingActionHandler(),
                remoteMessagingPixelReporter: MockRemoteMessagingPixelReporter(),
                remoteMessagingImageLoader: MockRemoteMessagingImageLoader(),
                appSettings: AppSettingsMock(),
                aiChatSettings: MockAIChatSettingsProvider(),
                experimentalAIChatManager: ExperimentalAIChatManager(featureFlagger: featureFlagger),
                defaultBrowserPromptPresenter: MockDefaultBrowserPromptPresenter(viewControllerToReturn: nil),
                winBackOfferPresenter: MockWinBackOfferPresenter(),
                winBackOfferCoordinator: MockWinBackOfferCoordinator(),
                subscriptionPromoPresenter: subscriptionPromoPresenter,
                subscriptionPromoCoordinator: subscriptionPromoCoordinator,
                subscriptionPromoExistingUserPresenter: subscriptionPromoPresenter,
                subscriptionPromoExistingUserCoordinator: subscriptionPromoCoordinator,
                userScriptsDependencies: .makeMock(privacyConfig: privacyConfigManager),
                omniBarFocuser: OmniBarFocuserProvider()
            )
        )
    }
}

enum StartupPrivacyConfigurationScenario: CaseIterable {
    case embeddedEnabled
    case embeddedDisabled
    case persistedEnabled
    case persistedDisabled

    var isEnabled: Bool {
        switch self {
        case .embeddedEnabled, .persistedEnabled:
            true
        case .embeddedDisabled, .persistedDisabled:
            false
        }
    }

    var isPersisted: Bool {
        switch self {
        case .embeddedEnabled, .embeddedDisabled:
            false
        case .persistedEnabled, .persistedDisabled:
            true
        }
    }

    var expectedMode: PromoCoordinationMode {
        isEnabled ? .coordinated : .legacy
    }
}

private final class CountingPromoFeatureFlagger: FeatureFlagger {
    var internalUserDecider: InternalUserDecider = DefaultInternalUserDecider(store: MockInternalUserStoring())
    var localOverrides: FeatureFlagLocalOverriding?
    var allActiveExperiments: Experiments = [:]
    var isPromoPresentationCoordinationEnabled: Bool

    private(set) var promoPresentationCoordinationReadCount = 0
    private(set) var updatesPublisherSubscriptionCount = 0
    private let updatesSubject = PassthroughSubject<Void, Never>()

    init(isPromoPresentationCoordinationEnabled: Bool) {
        self.isPromoPresentationCoordinationEnabled = isPromoPresentationCoordinationEnabled
    }

    var updatesPublisher: AnyPublisher<Void, Never> {
        Deferred { [weak self] () -> AnyPublisher<Void, Never> in
            guard let self else {
                return Empty(completeImmediately: false).eraseToAnyPublisher()
            }
            updatesPublisherSubscriptionCount += 1
            return updatesSubject.eraseToAnyPublisher()
        }
        .eraseToAnyPublisher()
    }

    func triggerUpdate() {
        updatesSubject.send()
    }

    func isFeatureOn<Flag: FeatureFlagDescribing>(for featureFlag: Flag, allowOverride: Bool) -> Bool {
        guard featureFlag.rawValue == FeatureFlag.promoPresentationCoordination.rawValue else {
            return false
        }
        promoPresentationCoordinationReadCount += 1
        return isPromoPresentationCoordinationEnabled
    }

    func resolveCohort<Flag: FeatureFlagDescribing>(
        for featureFlag: Flag,
        allowOverride: Bool
    ) -> (any FeatureFlagCohortDescribing)? {
        nil
    }

    func assignedCohort<Flag: FeatureFlagDescribing>(
        for featureFlag: Flag,
        allowOverride: Bool
    ) -> (any FeatureFlagCohortDescribing)? {
        nil
    }
}

private final class StartupSubscriptionPromoCoordinator: SubscriptionPromoCoordinating {
    func isEligibleToPresent(isOnboardingComplete: Bool) -> Bool { false }
    func shouldPresentLaunchPrompt() -> Bool { false }
    func markLaunchPromptPresented() {}
    func promoTitle() -> String { "" }
    func proceedButtonText() -> String { "" }
    func promoMessage() -> AttributedString { AttributedString("") }
    func handleCTAAction() {}
    func handleDismissAction() {}
}

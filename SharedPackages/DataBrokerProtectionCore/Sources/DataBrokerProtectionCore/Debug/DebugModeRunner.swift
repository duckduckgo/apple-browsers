//
//  DebugModeRunner.swift
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

import BrowserServicesKit
import Common
import ConcurrencyExtensions
import Foundation
import os.log
import PrivacyConfig

/// Nothing it runs is saved to the PIR database.
public final class DebugModeRunner: DebugModeEmailConfirmationLookup {

    public let debugEmailConfirmationStore = DebugEmailConfirmationStore()
    let captchaService: CaptchaService
    let privacyConfigManager: PrivacyConfigurationManaging
    public let pixelHandler: EventMapping<DataBrokerProtectionSharedPixels>
    let fakePixelHandler: EventMapping<DataBrokerProtectionSharedPixels> = EventMapping { event, _, _, _ in
        Logger.dataBrokerProtection.debug("Debug event: \(String(describing: event), privacy: .public)")
    }
    let contentScopeProperties: ContentScopeProperties
    public let featureFlagger: DBPFeatureFlagging
    public let brokerJobExecutionConfig = BrokerJobExecutionConfig()

    public var emailConfirmationEventHandler: ((String) -> Void)? {
        get { emailConfirmationEvents.handler }
        set { emailConfirmationEvents.handler = newValue }
    }

    let emailConfirmationDataService: EmailConfirmationDataServiceProvider
    private let emailConfirmationEvents: EmailConfirmationEvents
    private let vault: any DataBrokerProtectionSecureVault
    private let contentBlocking: DBPWebViewContentBlocking?

    public var emailConfirmationStore: EmailConfirmationSupporting {
        debugEmailConfirmationStore
    }

    public init(authenticationManager: DataBrokerProtectionAuthenticationManaging,
                featureFlagger: DBPFeatureFlagging,
                privacyConfigManager: PrivacyConfigurationManaging,
                pixelHandler: EventMapping<DataBrokerProtectionSharedPixels>,
                vault: any DataBrokerProtectionSecureVault,
                settings dbpSettings: DataBrokerProtectionSettings,
                contentBlocking: DBPWebViewContentBlocking? = nil) {
        self.featureFlagger = featureFlagger
        self.privacyConfigManager = privacyConfigManager
        self.pixelHandler = pixelHandler
        self.vault = vault
        self.contentBlocking = contentBlocking
        let features = ContentScopeFeatureToggles(emailProtection: false,
                                                  emailProtectionIncontextSignup: false,
                                                  credentialsAutofill: false,
                                                  identitiesAutofill: false,
                                                  creditCardsAutofill: false,
                                                  credentialsSaving: false,
                                                  passwordGeneration: false,
                                                  inlineIconCredentials: false,
                                                  thirdPartyCredentialsProvider: false,
                                                  unknownUsernameCategorization: false,
                                                  partialFormSaves: false,
                                                  passwordVariantCategorization: false,
                                                  inputFocusApi: false,
                                                  autocompleteAttributeSupport: false)

        self.contentScopeProperties = ContentScopeProperties(gpcEnabled: false,
                                                             sessionKey: UUID().uuidString,
                                                             messageSecret: UUID().uuidString,
                                                             featureToggles: features)

        let backendServicePixels = DefaultDataBrokerProtectionBackendServicePixels(pixelHandler: fakePixelHandler,
                                                                                   settings: dbpSettings)
        let emailService = EmailService(authenticationManager: authenticationManager,
                                        settings: dbpSettings,
                                        servicePixel: backendServicePixels)
        let emailServiceV1 = EmailServiceV1(authenticationManager: authenticationManager,
                                            settings: dbpSettings,
                                            servicePixel: backendServicePixels)
        self.captchaService = CaptchaService(authenticationManager: authenticationManager,
                                             settings: dbpSettings,
                                             servicePixel: backendServicePixels)

        let emailConfirmationEvents = EmailConfirmationEvents()
        self.emailConfirmationEvents = emailConfirmationEvents
        self.emailConfirmationDataService = EmailConfirmationDataService(emailConfirmationStore: debugEmailConfirmationStore,
                                                                         database: nil,
                                                                         emailServiceV0: emailService,
                                                                         emailServiceV1: emailServiceV1,
                                                                         pixelHandler: pixelHandler,
                                                                         debugEventHandler: { message in
                                                                            emailConfirmationEvents.handler?(message)
                                                                         })
    }

    public func storedBrokerResources() throws -> [BrokerResource] {
        try vault.fetchAllBrokerResources()
    }

    public func brokerProfileQueryData(for broker: DataBroker, profile: DataBrokerProtectionProfile) -> [BrokerProfileQueryData] {
        let resolvedBroker = broker.with(id: DebugHelper.stableId(for: broker))
        return profile.profileQueries.map { profileQuery in
            let profileQueryId = DebugHelper.stableId(for: profileQuery)
            let fakeScanJobData = ScanJobData(brokerId: DebugHelper.stableId(for: resolvedBroker),
                                              profileQueryId: profileQueryId,
                                              historyEvents: [HistoryEvent]())
            return BrokerProfileQueryData(dataBroker: resolvedBroker,
                                          profileQuery: profileQuery.with(id: profileQueryId),
                                          scanJobData: fakeScanJobData)
        }
    }

    public func scan(_ query: BrokerProfileQueryData,
                     showWebView: Bool,
                     timeout: TimeInterval?,
                     stageCalculator: FakeStageDurationCalculator,
                     onWebRunnerStarted: ((any SubJobWebRunning) -> Void)? = nil) async throws -> [ExtractedProfile] {
        let runner = BrokerProfileScanSubJobWebRunner(
            privacyConfig: privacyConfigManager,
            prefs: contentScopeProperties,
            context: query,
            emailConfirmationDataService: emailConfirmationDataService,
            captchaService: captchaService,
            featureFlagger: featureFlagger,
            stageDurationCalculator: stageCalculator,
            pixelHandler: fakePixelHandler,
            executionConfig: brokerJobExecutionConfig,
            contentBlocking: contentBlocking,
            shouldRunNextStep: { true }
        )
        onWebRunnerStarted?(runner)
        let extractedProfiles = try await withOptionalTimeout(timeout) {
            try await runner.scan(showWebView: showWebView) { true }
        }
        let brokerId = DebugHelper.stableId(for: query.dataBroker)
        let profileQueryId = DebugHelper.stableId(for: query.profileQuery)
        return extractedProfiles.map { profile in
            debugEmailConfirmationStore.storeExtractedProfile(profile,
                                                             brokerId: brokerId,
                                                             profileQueryId: profileQueryId,
                                                             stableId: DebugHelper.stableId(for: profile))
        }
    }

    /// Returns `true` when the opt-out still needs its email confirmation link.
    public func optOut(_ scanResult: DebugScanResult,
                       dataBroker: DataBroker,
                       showWebView: Bool,
                       timeout: TimeInterval?,
                       stageCalculator: FakeStageDurationCalculator,
                       onWebRunnerStarted: ((any SubJobWebRunning) -> Void)? = nil) async throws -> Bool {
        let runner = BrokerProfileOptOutSubJobWebRunner(
            privacyConfig: privacyConfigManager,
            prefs: contentScopeProperties,
            context: optOutQueryData(for: scanResult, dataBroker: dataBroker),
            emailConfirmationDataService: emailConfirmationDataService,
            captchaService: captchaService,
            featureFlagger: featureFlagger,
            stageCalculator: stageCalculator,
            pixelHandler: fakePixelHandler,
            executionConfig: brokerJobExecutionConfig,
            actionsHandlerMode: .optOut,
            contentBlocking: contentBlocking,
            shouldRunNextStep: { true }
        )
        onWebRunnerStarted?(runner)

        try await withOptionalTimeout(timeout) {
            try await runner.optOut(extractedProfile: scanResult.extractedProfile,
                                    showWebView: showWebView) { true }
        }

        return scanResult.dataBroker.requiresEmailConfirmationDuringOptOut()
    }

    public func checkForEmailConfirmation() async throws {
        try await emailConfirmationDataService.checkForEmailConfirmationData()
    }

    public func continueOptOut(_ scanResult: DebugScanResult,
                               confirmationURL: URL,
                               showWebView: Bool,
                               timeout: TimeInterval? = nil,
                               stageCalculator: FakeStageDurationCalculator,
                               onWebRunnerStarted: ((any SubJobWebRunning) -> Void)? = nil) async throws {
        let runner = BrokerProfileOptOutSubJobWebRunner(
            privacyConfig: privacyConfigManager,
            prefs: contentScopeProperties,
            context: optOutQueryData(for: scanResult, dataBroker: scanResult.dataBroker),
            emailConfirmationDataService: emailConfirmationDataService,
            captchaService: captchaService,
            featureFlagger: featureFlagger,
            stageCalculator: stageCalculator,
            pixelHandler: fakePixelHandler,
            executionConfig: .init(),
            actionsHandlerMode: .emailConfirmation(confirmationURL),
            contentBlocking: contentBlocking,
            shouldRunNextStep: { true }
        )
        onWebRunnerStarted?(runner)

        try await withOptionalTimeout(timeout) {
            try await runner.optOut(extractedProfile: scanResult.extractedProfile,
                                    showWebView: showWebView) { true }
        }
    }

    private func optOutQueryData(for scanResult: DebugScanResult, dataBroker: DataBroker) -> BrokerProfileQueryData {
        BrokerProfileQueryData(
            dataBroker: dataBroker,
            profileQuery: scanResult.profileQuery,
            scanJobData: ScanJobData(
                brokerId: DebugHelper.stableId(for: scanResult.dataBroker),
                profileQueryId: DebugHelper.stableId(for: scanResult.profileQuery),
                historyEvents: [HistoryEvent]()
            )
        )
    }

    private func withOptionalTimeout<T: Sendable>(_ timeout: TimeInterval?,
                                                  do operation: @escaping @Sendable () async throws -> T) async throws -> T {
        guard let timeout else {
            return try await operation()
        }

        return try await withTimeout(timeout,
                                     throwing: DataBrokerProtectionError.jobTimeout,
                                     do: operation)
    }
}

/// Lets the email confirmation service built in `init` reach a handler set later.
private final class EmailConfirmationEvents: @unchecked Sendable {
    var handler: ((String) -> Void)?
}

extension DebugModeRunner {

    public static func actionSummary(stepType: StepType, actionType: ActionType?) -> String {
        let typeText = actionType?.rawValue ?? "unknown"
        return "\(stepType.rawValue) > \(typeText)"
    }

    public static func currentActionText(stepType: StepType, actionType: ActionType?, prefix: String) -> String {
        let typeText = actionType?.rawValue ?? "unknown"
        return "\(prefix): \(stepType.rawValue) > \(typeText)"
    }

    public static func runnerEventText(kind: DebugEventKind,
                                       actionType: ActionType?,
                                       stepType: StepType,
                                       broker: DataBroker) -> (summary: String, progressText: String) {
        guard kind != .challenge else {
            return ("\(broker.name) > Challenge", "Challenge: \(broker.name)")
        }
        return (actionSummary(stepType: stepType, actionType: actionType),
                currentActionText(stepType: stepType, actionType: actionType, prefix: kind.rawValue))
    }

    public static func profileQueryText(for profileQuery: ProfileQuery) -> String {
        let nameText = "\(profileQuery.firstName) \(profileQuery.lastName)"
        let locationText = "\(profileQuery.city) \(profileQuery.state)"
        return "\(nameText) x \(locationText)"
    }

    public static func historyEventDescription(_ type: HistoryEvent.EventType) -> String {
        switch type {
        case .noMatchFound: return "No Match"
        case .matchesFound(let count): return "Matches (\(count))"
        case .error(let error): return "Error: \(error.name) - \(error.localizedDescription)"
        case .optOutStarted: return "Opt-out Started"
        case .optOutRequested: return "Opt-out Requested"
        case .optOutSubmittedAndAwaitingEmailConfirmation: return "Opt-out Awaiting Email"
        case .optOutConfirmed: return "Opt-out Confirmed"
        case .scanStarted: return "Scan Started"
        case .reAppearence: return "Reappearance"
        case .matchRemovedByUser: return "Removed by User"
        }
    }

    public static func historyError(_ error: Error) -> HistoryEvent.EventType {
        .error(error: (error as? DataBrokerProtectionError) ?? .unknown(error.localizedDescription))
    }
}

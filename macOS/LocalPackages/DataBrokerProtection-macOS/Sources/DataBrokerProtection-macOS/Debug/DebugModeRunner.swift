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
import ContentScopeScripts
import DataBrokerProtectionCore
import Foundation
import os.log
import PixelKit
import PrivacyConfig

/// Nothing it runs is saved to the PIR database.
final class DebugModeRunner: DebugModeEmailConfirmationLookup {

    let debugEmailConfirmationStore = DebugEmailConfirmationStore()
    let captchaService: CaptchaService
    let privacyConfigManager: PrivacyConfigurationManaging
    let pixelHandler: EventMapping<DataBrokerProtectionSharedPixels>
    let fakePixelHandler: EventMapping<DataBrokerProtectionSharedPixels> = EventMapping { event, _, _, _ in
        Logger.dataBrokerProtection.debug("Debug event: \(String(describing: event), privacy: .public)")
    }
    let contentScopeProperties: ContentScopeProperties
    let featureFlagger: DBPFeatureFlagging
    let brokerJobExecutionConfig = BrokerJobExecutionConfig()

    var emailConfirmationEventHandler: ((String) -> Void)? {
        get { emailConfirmationEvents.handler }
        set { emailConfirmationEvents.handler = newValue }
    }

    let emailConfirmationDataService: EmailConfirmationDataServiceProvider
    private let emailConfirmationEvents: EmailConfirmationEvents
    private let vault: any DataBrokerProtectionSecureVault

    var emailConfirmationStore: EmailConfirmationSupporting {
        debugEmailConfirmationStore
    }

    init(authenticationManager: DataBrokerProtectionAuthenticationManaging,
         featureFlagger: DBPFeatureFlagging) throws {
        self.featureFlagger = featureFlagger
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

        let dbpSettings = DataBrokerProtectionSettings(defaults: .dbp)
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

        let privacyConfigurationManager = DBPPrivacyConfigurationManager()
        self.privacyConfigManager = privacyConfigurationManager

        let pixelKit = PixelKit.shared!
        let sharedPixelsHandler = DataBrokerProtectionSharedPixelsHandler(pixelKit: pixelKit, platform: .macOS)
        self.pixelHandler = sharedPixelsHandler
        let reporter = DataBrokerProtectionSecureVaultErrorReporter(pixelHandler: sharedPixelsHandler, privacyConfigManager: privacyConfigurationManager)
        let databaseURL = DefaultDataBrokerProtectionDatabaseProvider.databaseFilePath(directoryName: DatabaseConstants.directoryName, fileName: DatabaseConstants.fileName, appGroupIdentifier: Bundle.main.appGroupName)
        let vaultFactory = createDataBrokerProtectionSecureVaultFactory(appGroupName: Bundle.main.appGroupName, databaseFileURL: databaseURL)
        self.vault = try vaultFactory.makeVault(reporter: reporter)

        let emailConfirmationEvents = EmailConfirmationEvents()
        self.emailConfirmationEvents = emailConfirmationEvents
        self.emailConfirmationDataService = EmailConfirmationDataService(emailConfirmationStore: debugEmailConfirmationStore,
                                                                         database: nil,
                                                                         emailServiceV0: emailService,
                                                                         emailServiceV1: emailServiceV1,
                                                                         pixelHandler: sharedPixelsHandler,
                                                                         debugEventHandler: { message in
                                                                            emailConfirmationEvents.handler?(message)
                                                                         })
    }

    func storedBrokerResources() throws -> [BrokerResource] {
        try vault.fetchAllBrokerResources()
    }

    func brokerProfileQueryData(for broker: DataBroker, profile: DataBrokerProtectionProfile) -> [BrokerProfileQueryData] {
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

    func scan(_ query: BrokerProfileQueryData,
              showWebView: Bool,
              timeout: TimeInterval?,
              stageCalculator: FakeStageDurationCalculator) async throws -> [ExtractedProfile] {
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
            shouldRunNextStep: { true }
        )
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
    func optOut(_ scanResult: DebugScanResult,
                dataBroker: DataBroker,
                showWebView: Bool,
                timeout: TimeInterval?,
                stageCalculator: FakeStageDurationCalculator) async throws -> Bool {
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
            shouldRunNextStep: { true }
        )

        try await withOptionalTimeout(timeout) {
            try await runner.optOut(extractedProfile: scanResult.extractedProfile,
                                    showWebView: showWebView) { true }
        }

        return scanResult.dataBroker.requiresEmailConfirmationDuringOptOut()
    }

    func checkForEmailConfirmation() async throws {
        try await emailConfirmationDataService.checkForEmailConfirmationData()
    }

    func continueOptOut(_ scanResult: DebugScanResult,
                        confirmationURL: URL,
                        showWebView: Bool,
                        timeout: TimeInterval? = nil,
                        stageCalculator: FakeStageDurationCalculator) async throws {
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
            shouldRunNextStep: { true }
        )

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

    static func actionSummary(stepType: StepType, actionType: ActionType?) -> String {
        let typeText = actionType?.rawValue ?? "unknown"
        return "\(stepType.rawValue) > \(typeText)"
    }

    static func currentActionText(stepType: StepType, actionType: ActionType?, prefix: String) -> String {
        let typeText = actionType?.rawValue ?? "unknown"
        return "\(prefix): \(stepType.rawValue) > \(typeText)"
    }

    static func runnerEventText(kind: DebugEventKind,
                                actionType: ActionType?,
                                stepType: StepType,
                                broker: DataBroker) -> (summary: String, progressText: String) {
        guard kind != .challenge else {
            return ("\(broker.name) > Challenge", "Challenge: \(broker.name)")
        }
        return (actionSummary(stepType: stepType, actionType: actionType),
                currentActionText(stepType: stepType, actionType: actionType, prefix: kind.rawValue))
    }

    static func profileQueryText(for profileQuery: ProfileQuery) -> String {
        let nameText = "\(profileQuery.firstName) \(profileQuery.lastName)"
        let locationText = "\(profileQuery.city) \(profileQuery.state)"
        return "\(nameText) x \(locationText)"
    }

    static func historyEventDescription(_ type: HistoryEvent.EventType) -> String {
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

    static func historyError(_ error: Error) -> HistoryEvent.EventType {
        .error(error: (error as? DataBrokerProtectionError) ?? .unknown(error.localizedDescription))
    }
}

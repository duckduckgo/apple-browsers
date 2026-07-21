//
//  PIRDebugSession.swift
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
import Combine
import Common
import BrowserServicesKit
import DataBrokerProtectionCore

/// UI-agnostic engine behind the "Run Personal Information Removal Debug Mode" window. Configured
/// once via ``PIRDebugSessionConfiguration``, it runs scans and opt-outs headless (or headed) using
/// the same `BrokerProfileScanSubJobWebRunner` / `BrokerProfileOptOutSubJobWebRunner` as the app,
/// and streams debug events.
///
/// No AppKit; no vault/keychain; no real pixels. Landmines (`Bundle.appGroupName`,
/// `UserDefaults.dbp`, `PixelKit.shared!`) are never reached.
public final class PIRDebugSession {

    public let configuration: PIRDebugSessionConfiguration

    /// Emits every action/response/wait/retry/history event across scans and opt-outs.
    public let events: AsyncStream<PIRDebugEvent>
    private let eventContinuation: AsyncStream<PIRDebugEvent>.Continuation

    private let privacyConfigManager: PIRDebugPrivacyConfigurationManager
    private let contentScopeProperties: ContentScopeProperties
    private let emailService: EmailService
    private let emailServiceV1: EmailServiceV1
    private let captchaService: CaptchaService
    /// The in-memory email-confirmation store backing this session. Exposed so a host UI (the debug
    /// window) can query awaiting/with-link state to drive its email-confirmation buttons.
    public let emailConfirmationStore = DebugEmailConfirmationStore()
    private let emailConfirmationDataService: EmailConfirmationDataService

    private let settings: DataBrokerProtectionSettings
    private let userDefaultsSuiteName: String

    /// Maps an extracted-profile stable id → the profile query it came from, for opt-out resolution
    /// within the same session.
    private var profileQueryIndex: [Int64: ProfileQuery] = [:]

    private struct PendingOptOut {
        let broker: DataBroker
        let profileQuery: ProfileQuery
        let extractedProfile: ExtractedProfile
    }
    private var pendingOptOut: PendingOptOut?

    public init(configuration: PIRDebugSessionConfiguration) throws {
        self.configuration = configuration

        if let data = configuration.privacyConfigData {
            self.privacyConfigManager = try PIRDebugPrivacyConfigurationManager(configData: data)
        } else {
            self.privacyConfigManager = try PIRDebugPrivacyConfigurationManager.bundled()
        }

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

        // Settings over an ephemeral UserDefaults suite — never UserDefaults.standard / UserDefaults.dbp.
        let suiteName = "com.duckduckgo.pir-debug.session.\(UUID().uuidString)"
        self.userDefaultsSuiteName = suiteName
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        let settings = DataBrokerProtectionSettings(defaults: defaults)
        settings.selectedEnvironment = configuration.servicesEndpoint.selectedEnvironment
        self.settings = settings

        let baseURL = configuration.servicesEndpoint.baseURL
        let backendServicePixels = DefaultDataBrokerProtectionBackendServicePixels(pixelHandler: configuration.pixelHandler,
                                                                                   settings: settings)
        self.emailService = EmailService(authenticationManager: configuration.authManager,
                                         settings: settings,
                                         servicePixel: backendServicePixels,
                                         baseURL: baseURL)
        self.emailServiceV1 = EmailServiceV1(authenticationManager: configuration.authManager,
                                             settings: settings,
                                             servicePixel: backendServicePixels,
                                             baseURL: baseURL)
        self.captchaService = CaptchaService(authenticationManager: configuration.authManager,
                                             settings: settings,
                                             servicePixel: backendServicePixels,
                                             baseURL: baseURL)

        var continuation: AsyncStream<PIRDebugEvent>.Continuation!
        self.events = AsyncStream<PIRDebugEvent> { continuation = $0 }
        self.eventContinuation = continuation

        let store = emailConfirmationStore
        let emailV0 = emailService
        let emailV1 = emailServiceV1
        let pixelHandler = configuration.pixelHandler
        let sink = continuation
        self.emailConfirmationDataService = EmailConfirmationDataService(
            emailConfirmationStore: store,
            database: nil,
            emailServiceV0: emailV0,
            emailServiceV1: emailV1,
            pixelHandler: pixelHandler,
            debugEventHandler: { message in
                sink?.yield(PIRDebugEvent(profileQueryLabel: "-",
                                          kind: .history,
                                          actionType: nil,
                                          details: message))
            })
    }

    deinit {
        eventContinuation.finish()
        UserDefaults.standard.removeSuite(named: userDefaultsSuiteName)
    }

    // MARK: - Rules

    public func fetchBrokers() async throws -> [DataBroker] {
        try await configuration.rulesSource.fetchBrokers()
    }

    // MARK: - Scan

    @MainActor
    public func scan(broker: DataBroker,
                     profile: DataBrokerProtectionProfile) async throws -> PIRScanResult {
        let start = Date()
        let resolvedBroker = broker.with(id: DebugHelper.stableId(for: broker))
        let brokerId = DebugHelper.stableId(for: resolvedBroker)

        var eventCount = 0
        var statuses: [PIRScanResult.QueryStatus] = []
        var records: [PIRExtractedProfileRecord] = []

        for profileQuery in profile.profileQueries {
            let profileQueryId = DebugHelper.stableId(for: profileQuery)
            let label = Self.profileQueryLabel(profileQuery)
            let resolvedQuery = profileQuery.with(id: profileQueryId)
            let context = BrokerProfileQueryData(
                dataBroker: resolvedBroker,
                profileQuery: resolvedQuery,
                scanJobData: ScanJobData(brokerId: brokerId, profileQueryId: profileQueryId, historyEvents: []))

            let stageCalculator = PIRDebugStageDurationCalculator(profileQueryLabel: label) { [weak self] event in
                eventCount += 1
                self?.eventContinuation.yield(event)
            }

            let runner = BrokerProfileScanSubJobWebRunner(
                privacyConfig: privacyConfigManager,
                prefs: contentScopeProperties,
                context: context,
                emailConfirmationDataService: emailConfirmationDataService,
                captchaService: captchaService,
                featureFlagger: configuration.featureFlagger,
                applicationNameForUserAgentProvider: { [name = configuration.userAgentApplicationName] in name },
                operationAwaitTime: configuration.operationAwaitTime,
                stageDurationCalculator: stageCalculator,
                pixelHandler: configuration.pixelHandler,
                executionConfig: configuration.executionConfig,
                customContentScopeJSURL: configuration.scriptSource.customContentScopeJSURL,
                shouldRunNextStep: { true })

            do {
                let extracted = try await runner.scan(showWebView: configuration.showWebView) { true }
                let assigned: [ExtractedProfile] = extracted.map { profile in
                    emailConfirmationStore.storeExtractedProfile(profile,
                                                                 brokerId: brokerId,
                                                                 profileQueryId: profileQueryId,
                                                                 stableId: DebugHelper.stableId(for: profile))
                }
                for assignedProfile in assigned {
                    profileQueryIndex[assignedProfile.id ?? profileQueryId] = resolvedQuery
                    records.append(PIRExtractedProfileRecord(brokerId: brokerId,
                                                             profileQueryId: profileQueryId,
                                                             profileQueryLabel: label,
                                                             extractedProfile: assignedProfile))
                }
                statuses.append(PIRScanResult.QueryStatus(
                    profileQueryId: profileQueryId,
                    profileQueryLabel: label,
                    outcome: assigned.isEmpty ? .noMatch : .matches,
                    extractedProfileCount: assigned.count,
                    error: nil))
            } catch {
                statuses.append(PIRScanResult.QueryStatus(
                    profileQueryId: profileQueryId,
                    profileQueryLabel: label,
                    outcome: .error,
                    extractedProfileCount: 0,
                    error: error.localizedDescription))
            }
        }

        return PIRScanResult(brokerName: resolvedBroker.name,
                             brokerURL: resolvedBroker.url,
                             brokerVersion: resolvedBroker.version,
                             brokerId: brokerId,
                             queryStatuses: statuses,
                             extractedProfiles: records,
                             duration: Date().timeIntervalSince(start),
                             eventCount: eventCount)
    }

    // MARK: - Opt-out

    @MainActor
    public func optOut(broker: DataBroker,
                       profile: DataBrokerProtectionProfile,
                       extractedProfile: ExtractedProfile) async throws -> PIROptOutResult {
        let resolvedBroker = broker.with(id: DebugHelper.stableId(for: broker))
        let profileQuery = try resolveProfileQuery(for: extractedProfile, in: profile)
        return await runOptOut(broker: resolvedBroker,
                               profileQuery: profileQuery,
                               extractedProfile: extractedProfile,
                               mode: .optOut)
    }

    /// Opt-out variant that takes the exact `ProfileQuery` the extracted profile came from, rather
    /// than resolving it from a `DataBrokerProtectionProfile`. The debug window uses this because it
    /// already holds the originating profile query and may run a multi-query profile against a fresh
    /// session (where index-based resolution is unavailable).
    @MainActor
    public func optOut(broker: DataBroker,
                       profileQuery: ProfileQuery,
                       extractedProfile: ExtractedProfile) async throws -> PIROptOutResult {
        let resolvedBroker = broker.with(id: DebugHelper.stableId(for: broker))
        return await runOptOut(broker: resolvedBroker,
                               profileQuery: profileQuery,
                               extractedProfile: extractedProfile,
                               mode: .optOut)
    }

    /// Runs `EmailConfirmationDataService.checkForEmailConfirmationData()` and returns the
    /// confirmation URL now available for the pending opt-out (or `nil` if not ready yet).
    public func checkEmailConfirmation() async throws -> URL? {
        try await emailConfirmationDataService.checkForEmailConfirmationData()
        guard let pending = pendingOptOut else { return nil }
        return confirmationURL(broker: pending.broker,
                               profileQuery: pending.profileQuery,
                               extractedProfile: pending.extractedProfile)
    }

    /// Continues the pending opt-out with the given confirmation URL (mirrors the debug window's
    /// "Continue opt-out" button; `actionsHandlerMode: .emailConfirmation(url)`).
    @MainActor
    public func continueOptOut(afterEmailURL url: URL) async throws -> PIROptOutResult {
        guard let pending = pendingOptOut else {
            throw PIRDebugError.noPendingOptOut
        }
        return await runOptOut(broker: pending.broker,
                               profileQuery: pending.profileQuery,
                               extractedProfile: pending.extractedProfile,
                               mode: .emailConfirmation(url))
    }

    // MARK: - Internals

    @MainActor
    private func runOptOut(broker: DataBroker,
                           profileQuery: ProfileQuery,
                           extractedProfile: ExtractedProfile,
                           mode: BrokerProfileOptOutSubJobWebRunner.ActionsHandlerMode) async -> PIROptOutResult {
        let start = Date()
        let brokerId = DebugHelper.stableId(for: broker)
        let profileQueryId = DebugHelper.stableId(for: profileQuery)
        let resolvedQuery = profileQuery.with(id: profileQueryId)
        let label = Self.profileQueryLabel(profileQuery)

        // Ensure the store knows this extracted profile so email confirmation can key off it.
        if let extractedProfileId = extractedProfile.id {
            _ = emailConfirmationStore.storeExtractedProfile(extractedProfile,
                                                             brokerId: brokerId,
                                                             profileQueryId: profileQueryId,
                                                             stableId: extractedProfileId)
        }

        let context = BrokerProfileQueryData(
            dataBroker: broker,
            profileQuery: resolvedQuery,
            scanJobData: ScanJobData(brokerId: brokerId, profileQueryId: profileQueryId, historyEvents: []))

        var eventCount = 0
        var lastStage: String?
        let stageCalculator = PIRDebugStageDurationCalculator(profileQueryLabel: label) { [weak self] event in
            eventCount += 1
            lastStage = event.details
            self?.eventContinuation.yield(event)
        }

        let runner = BrokerProfileOptOutSubJobWebRunner(
            privacyConfig: privacyConfigManager,
            prefs: contentScopeProperties,
            context: context,
            emailConfirmationDataService: emailConfirmationDataService,
            captchaService: captchaService,
            featureFlagger: configuration.featureFlagger,
            applicationNameForUserAgentProvider: { [name = configuration.userAgentApplicationName] in name },
            operationAwaitTime: configuration.operationAwaitTime,
            stageCalculator: stageCalculator,
            pixelHandler: configuration.pixelHandler,
            executionConfig: configuration.executionConfig,
            actionsHandlerMode: mode,
            customContentScopeJSURL: configuration.scriptSource.customContentScopeJSURL,
            shouldRunNextStep: { true })

        func result(success: Bool, awaiting: Bool, error: String?) -> PIROptOutResult {
            PIROptOutResult(brokerName: broker.name,
                            brokerURL: broker.url,
                            brokerVersion: broker.version,
                            brokerId: brokerId,
                            profileQueryId: profileQueryId,
                            profileQueryLabel: label,
                            extractedProfileId: extractedProfile.id,
                            lastStage: lastStage,
                            success: success,
                            awaitingEmailConfirmation: awaiting,
                            error: error,
                            duration: Date().timeIntervalSince(start),
                            eventCount: eventCount)
        }

        do {
            try await runner.optOut(extractedProfile: extractedProfile, showWebView: configuration.showWebView) { true }

            // A fresh opt-out (not an email-confirmation continuation) for a broker requiring email
            // confirmation halts awaiting the link.
            if case .optOut = mode, broker.requiresEmailConfirmationDuringOptOut() {
                pendingOptOut = PendingOptOut(broker: broker, profileQuery: resolvedQuery, extractedProfile: extractedProfile)
                return result(success: false, awaiting: true, error: nil)
            }

            pendingOptOut = nil
            return result(success: true, awaiting: false, error: nil)
        } catch {
            return result(success: false, awaiting: false, error: error.localizedDescription)
        }
    }

    private func resolveProfileQuery(for extractedProfile: ExtractedProfile,
                                     in profile: DataBrokerProtectionProfile) throws -> ProfileQuery {
        if let id = extractedProfile.id, let known = profileQueryIndex[id] {
            return known
        }
        let queries = profile.profileQueries
        if queries.count == 1 {
            return queries[0]
        }
        throw PIRDebugError.ambiguousProfileQuery
    }

    private func confirmationURL(broker: DataBroker,
                                 profileQuery: ProfileQuery,
                                 extractedProfile: ExtractedProfile) -> URL? {
        guard let extractedProfileId = extractedProfile.id,
              let confirmations = try? emailConfirmationStore.fetchOptOutEmailConfirmationsWithLink() else {
            return nil
        }
        let brokerId = DebugHelper.stableId(for: broker)
        let profileQueryId = DebugHelper.stableId(for: profileQuery)
        guard let match = confirmations.first(where: {
            $0.brokerId == brokerId && $0.profileQueryId == profileQueryId && $0.extractedProfileId == extractedProfileId
        }), let link = match.emailConfirmationLink else {
            return nil
        }
        return URL(string: link)
    }

    static func profileQueryLabel(_ profileQuery: ProfileQuery) -> String {
        "\(profileQuery.firstName) \(profileQuery.lastName) x \(profileQuery.city) \(profileQuery.state)"
    }
}

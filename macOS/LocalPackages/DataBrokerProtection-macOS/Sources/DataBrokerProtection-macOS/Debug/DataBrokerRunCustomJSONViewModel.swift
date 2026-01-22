//
//  DataBrokerRunCustomJSONViewModel.swift
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

import Foundation
import BrowserServicesKit
import DataBrokerProtectionCore
import Common
import ContentScopeScripts
import os.log
import FeatureFlags
import PixelKit
import PrivacyConfig
import enum UserScript.UserScriptError

struct ExtractedAddress: Codable {
    let state: String
    let city: String
}

struct UserData: Codable {
    let firstName: String
    let lastName: String
    let middleName: String?
    let state: String
    let email: String?
    let city: String
    let age: Int
    let addresses: [ExtractedAddress]
}

struct ProfileUrl: Codable {
    let profileUrl: String
    let identifier: String
}

struct AlertUI {
    var title: String = ""
    var description: String = ""

    static func noResults() -> AlertUI {
        AlertUI(title: "No results", description: "No results were found.")
    }

    static func from(error: DataBrokerProtectionError) -> AlertUI {
        AlertUI(title: error.title, description: error.localizedDescription)
    }
}

final class NameUI: ObservableObject {
    let id = UUID()
    @Published var first: String
    @Published var middle: String
    @Published var last: String

    init(first: String, middle: String = "", last: String) {
        self.first = first
        self.middle = middle
        self.last = last
    }

    init?(components: PersonNameComponents) {
        let first = components.givenName ?? ""
        let middle = components.middleName ?? ""
        let last = components.familyName ?? ""
        if first.isEmpty && middle.isEmpty && last.isEmpty {
            return nil
        }
        self.first = first
        self.middle = middle
        self.last = last
    }

    static func empty() -> NameUI {
        .init(first: "", middle: "", last: "")
    }

    func toModel() -> DataBrokerProtectionProfile.Name? {
        let trimmedFirst = first.trimmed()
        let trimmedMiddle = middle.trimmed()
        let trimmedLast = last.trimmed()
        if trimmedFirst.isEmpty, trimmedMiddle.isEmpty, trimmedLast.isEmpty {
            return nil
        }
        return .init(firstName: trimmedFirst,
                     lastName: trimmedLast,
                     middleName: trimmedMiddle.isEmpty ? nil : trimmedMiddle)
    }
}

final class AddressUI: ObservableObject {
    let id = UUID()
    @Published var city: String
    @Published var state: String

    init(city: String, state: String) {
        self.city = city
        self.state = state
    }

    static func empty() -> AddressUI {
        .init(city: "", state: "")
    }

    func toModel() -> DataBrokerProtectionProfile.Address? {
        let trimmedCity = city.trimmed()
        let trimmedState = state.trimmed()
        if trimmedCity.isEmpty || trimmedState.isEmpty {
            return nil
        }
        return .init(city: trimmedCity, state: trimmedState)
    }
}

struct ScanResult {
    let id = UUID()
    let dataBroker: DataBroker
    let profileQuery: ProfileQuery
    let extractedProfile: ExtractedProfile
}

/// Preset entries look like this:
///
/// John Smith
/// Dallas, TX
/// 2000
///
/// Jane Doe / Janet Doe
/// Chicago, IL / Los Angeles, LA
/// 1980
struct ProfilePreset: Identifiable, CustomStringConvertible {
    enum Constants {
        static let entrySeparator = "/"
        static let partSeparator = ","
        static let fieldSeparator = "\n"
        static let profileSeparator = "\n\n"
        static let presetKey = "dataBrokerProtectionDebugPresets"
    }

    let id = UUID()
    let names: [NameUI]
    let addresses: [AddressUI]
    let birthYear: String

    var description: String {
        let firstName = (names.first?.first ?? "Unnamed").trimmed()
        let firstAddress = addresses.first.map {
            "\($0.city.trimmed()), \($0.state.trimmed())"
        } ?? "Nowhere"
        let yob = birthYear.trimmed()
        return "\(firstName) - \(firstAddress) - \(yob)"
    }
}

// swiftlint:disable force_try
final class DataBrokerRunCustomJSONViewModel: ObservableObject {
    enum Constants {
        static let maxNames = 3
        static let maxAddresses = 5
    }

    @Published var birthYear: String = ""
    @Published var age: String = ""
    @Published var results = [ScanResult]()
    @Published var showAlert = false
    @Published var showNoResults = false
    @Published var names = [NameUI.empty()]
    @Published var addresses = [AddressUI.empty()]
    @Published var debugEvents: [DebugLogEvent] = []
    @Published var progressText: String = "Idle"
    @Published var isProgressActive: Bool = false
    @Published var isEditingPresets: Bool = false
    @Published var presetsText: String = ""
    @Published var presets: [ProfilePreset] = []

    var alert: AlertUI?
    var selectedDataBroker: DataBroker?
    var error: Error?
    var profileQueryLabels: [Int64: String] = [:]

    let brokers: [DataBroker]

    private let emailService: EmailService
    lazy var emailConfirmationDataService: EmailConfirmationDataServiceProvider = {
        EmailConfirmationDataService(emailConfirmationStore: emailConfirmationStore,
                                     database: nil,
                                     emailServiceV0: emailService,
                                     emailServiceV1: emailServiceV1,
                                     featureFlagger: featureFlagger,
                                     pixelHandler: pixelHandler,
                                     debugEventHandler: { [weak self] message in
                                        self?.addHistoryDebugEvent(summary: "Email confirmation", details: message)
                                     })
    }()
    let emailConfirmationStore = DebugEmailConfirmationStore()
    let captchaService: CaptchaService
    private let emailServiceV1: EmailServiceV1Protocol
    let privacyConfigManager: PrivacyConfigurationManaging
    let pixelHandler: EventMapping<DataBrokerProtectionSharedPixels>
    let fakePixelHandler: EventMapping<DataBrokerProtectionSharedPixels> = EventMapping { event, _, _, _ in
        Logger.dataBrokerProtection.debug("Debug event: \(String(describing: event), privacy: .public)")
    }
    let contentScopeProperties: ContentScopeProperties
    private let authenticationManager: DataBrokerProtectionAuthenticationManaging
    let featureFlagger: DBPFeatureFlagging

    private var isSyncingAgeFields = false
    var awaitingEmailConfirmationProfileIds = Set<Int64>()

    var combinedDebugEvents: [DebugEventRow] {
        let debugRows = debugEvents.map { event in
            DebugEventRow(
                id: event.id.uuidString,
                timestamp: event.timestamp,
                kind: event.kind.rawValue,
                profileQueryLabel: event.profileQueryLabel,
                summary: event.summary,
                details: event.details
            )
        }
        return debugRows.sorted(by: { $0.timestamp > $1.timestamp })
    }

    init(authenticationManager: DataBrokerProtectionAuthenticationManaging,
         featureFlagger: DBPFeatureFlagging) {
        let privacyConfigurationManager = DBPPrivacyConfigurationManager()
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

        let sessionKey = UUID().uuidString
        let messageSecret = UUID().uuidString
        self.authenticationManager = authenticationManager
        let contentScopeProperties = ContentScopeProperties(gpcEnabled: false,
                                                            sessionKey: sessionKey,
                                                            messageSecret: messageSecret,
                                                            featureToggles: features)

        let dbpSettings = DataBrokerProtectionSettings(defaults: .dbp)
        let backendServicePixels = DefaultDataBrokerProtectionBackendServicePixels(pixelHandler: fakePixelHandler,
                                                                                   settings: dbpSettings)
        self.emailService = EmailService(authenticationManager: authenticationManager,
                                         settings: dbpSettings,
                                         servicePixel: backendServicePixels)
        self.captchaService = CaptchaService(authenticationManager: authenticationManager,
                                             settings: dbpSettings,
                                             servicePixel: backendServicePixels)

        self.privacyConfigManager = privacyConfigurationManager
        self.contentScopeProperties = contentScopeProperties

        let pixelKit = PixelKit.shared!
        let sharedPixelsHandler = DataBrokerProtectionSharedPixelsHandler(pixelKit: pixelKit, platform: .macOS)
        self.pixelHandler = sharedPixelsHandler
        let reporter = DataBrokerProtectionSecureVaultErrorReporter(pixelHandler: sharedPixelsHandler, privacyConfigManager: privacyConfigurationManager)
        let databaseURL = DefaultDataBrokerProtectionDatabaseProvider.databaseFilePath(directoryName: DatabaseConstants.directoryName, fileName: DatabaseConstants.fileName, appGroupIdentifier: Bundle.main.appGroupName)
        let vaultFactory = createDataBrokerProtectionSecureVaultFactory(appGroupName: Bundle.main.appGroupName, databaseFileURL: databaseURL)
        let vault = try! vaultFactory.makeVault(reporter: reporter)

        self.brokers = try! vault.fetchAllBrokers()

        self.emailServiceV1 = EmailServiceV1(authenticationManager: authenticationManager,
                                             settings: dbpSettings,
                                             servicePixel: backendServicePixels)

        if #available(macOS 12.0, *) {
            loadPresets()
        }
    }

    @MainActor
    func runJSON(jsonString: String) {
        self.error = nil
        self.results.removeAll()
        self.debugEvents.removeAll()
        self.awaitingEmailConfirmationProfileIds.removeAll()
        self.emailConfirmationStore.reset()
        self.isProgressActive = true
        self.progressText = "Starting scan..."
        if let data = jsonString.data(using: .utf8) {
            do {
                let decoder = JSONDecoder()
                let dataBroker = try decoder.decode(DataBroker.self, from: data)
                self.selectedDataBroker = dataBroker
                let brokerProfileQueryData = createBrokerProfileQueryData(for: dataBroker)
                let group = DispatchGroup()

                for query in brokerProfileQueryData {
                    group.enter()

                    Task {
                        do {
                            addScanStartedEvent(for: query)
                            let stageCalculator = FakeStageDurationCalculator { [weak self] kind, actionType, details in
                                let profileQuery = self?.profileQueryText(for: query.profileQuery) ?? "-"
                                let summary = self?.actionSummary(stepType: .scan,
                                                                  actionType: actionType) ?? "-"
                                let progressText = self?.currentActionText(stepType: .scan,
                                                                           actionType: actionType,
                                                                           prefix: kind.rawValue) ?? "-"
                                self?.addDebugEvent(kind: kind,
                                                    summary: summary,
                                                    profileQueryLabel: profileQuery,
                                                    details: details,
                                                    progressText: progressText)
                            }
                            let runner = BrokerProfileScanSubJobWebRunner(
                                privacyConfig: self.privacyConfigManager,
                                prefs: self.contentScopeProperties,
                                context: query,
                                emailConfirmationDataService: self.emailConfirmationDataService,
                                captchaService: self.captchaService,
                                featureFlagger: self.featureFlagger,
                                stageDurationCalculator: stageCalculator,
                                pixelHandler: fakePixelHandler,
                                executionConfig: .init(),
                                shouldRunNextStep: { true }
                            )
                            let extractedProfiles = try await runner.scan(query, showWebView: true) { true }
                            let brokerId = DebugHelper.stableId(for: query.dataBroker)
                            let profileQueryId = DebugHelper.stableId(for: query.profileQuery)
                            let assignedProfiles: [ExtractedProfile] = extractedProfiles.map { profile in
                                emailConfirmationStore.storeExtractedProfile(profile,
                                                                             brokerId: brokerId,
                                                                             profileQueryId: profileQueryId,
                                                                             stableId: DebugHelper.stableId(for: profile))
                            }
                            addScanResultEvents(for: query, extractedProfiles: assignedProfiles)

                            Task { @MainActor in
                                for extractedProfile in assignedProfiles {
                                    self.results.append(ScanResult(dataBroker: query.dataBroker,
                                                                   profileQuery: query.profileQuery,
                                                                   extractedProfile: extractedProfile))
                                }
                            }
                            group.leave()
                        } catch let UserScriptError.failedToLoadJS(jsFile, error) {
                            pixelHandler.fire(.userScriptLoadJSFailed(jsFile: jsFile, error: error))
                            try await Task.sleep(interval: 1.0) // give time for the pixel to be sent
                            fatalError("Failed to load JS file \(jsFile): \(error.localizedDescription)")
                        } catch {
                            addScanErrorEvent(for: query, error: error)
                            self.error = error
                            group.leave()
                        }
                    }
                }
                group.notify(queue: .main) {
                    self.isProgressActive = false
                    self.progressText = "Idle"
                    if let error = self.error {
                        self.showAlert(for: error)
                    } else if self.results.count == 0 {
                        self.showNoResultsAlert()
                    }
                }
            } catch {
                self.isProgressActive = false
                self.progressText = "Idle"
                showAlert(for: error)
            }
        }
    }

    @MainActor
    func runOptOut(scanResult: ScanResult) {
        isProgressActive = true
        progressText = "Starting opt-out..."
        addOptOutStartedEvent(for: scanResult)
        let brokerProfileQueryData = BrokerProfileQueryData(
            dataBroker: scanResult.dataBroker,
            profileQuery: scanResult.profileQuery,
            scanJobData: ScanJobData(
                brokerId: DebugHelper.stableId(for: scanResult.dataBroker),
                profileQueryId: DebugHelper.stableId(for: scanResult.profileQuery),
                historyEvents: [HistoryEvent]()
            )
        )
        Task {
            do {
                let stageCalculator = FakeStageDurationCalculator { [weak self] kind, actionType, details in
                    let profileQuery = self?.profileQueryText(for: brokerProfileQueryData.profileQuery) ?? "-"
                    let summary = self?.actionSummary(stepType: .optOut, actionType: actionType) ?? "-"
                    let progressText = self?.currentActionText(stepType: .optOut,
                                                               actionType: actionType,
                                                               prefix: kind.rawValue) ?? "-"
                    self?.addDebugEvent(kind: kind,
                                        summary: summary,
                                        profileQueryLabel: profileQuery,
                                        details: details,
                                        progressText: progressText)
                }
                let runner = BrokerProfileOptOutSubJobWebRunner(
                    privacyConfig: self.privacyConfigManager,
                    prefs: self.contentScopeProperties,
                    context: brokerProfileQueryData,
                    emailConfirmationDataService: self.emailConfirmationDataService,
                    captchaService: self.captchaService,
                    featureFlagger: self.featureFlagger,
                    stageCalculator: stageCalculator,
                    pixelHandler: fakePixelHandler,
                    executionConfig: .init(),
                    actionsHandlerMode: .optOut,
                    shouldRunNextStep: { true }
                )

                try await runner.optOut(profileQuery: brokerProfileQueryData,
                                        extractedProfile: scanResult.extractedProfile,
                                        showWebView: true) { true }

                if self.featureFlagger.isEmailConfirmationDecouplingFeatureOn,
                   scanResult.dataBroker.requiresEmailConfirmationDuringOptOut() {
                    addOptOutAwaitingEmailConfirmationEvent(for: scanResult)
                    Task { @MainActor in
                        self.isProgressActive = false
                        self.progressText = "Awaiting email confirmation"
                        self.showAlert = true
                        self.alert = AlertUI(title: "Opt-out submitted awaiting email confirmation",
                                             description: "Use \"Check for email confirmation\" to continue. You may need to run it multiple times.")
                    }
                    return
                }

                addOptOutConfirmedEvent(for: scanResult)
                Task { @MainActor in
                    self.isProgressActive = false
                    self.progressText = "Idle"
                    self.showAlert = true
                    self.alert = AlertUI(title: "Success!", description: "We finished the opt out process for the selected profile.")
                }

            } catch let UserScriptError.failedToLoadJS(jsFile, error) {
                pixelHandler.fire(.userScriptLoadJSFailed(jsFile: jsFile, error: error))
                try await Task.sleep(interval: 1.0) // give time for the pixel to be sent
                fatalError("Failed to load JS file \(jsFile): \(error.localizedDescription)")
            } catch {
                addOptOutErrorEvent(for: scanResult, error: error)
                Task { @MainActor in
                    self.isProgressActive = false
                    self.progressText = "Idle"
                }
                showAlert(for: error)
            }
        }
    }

    private func createBrokerProfileQueryData(for broker: DataBroker) -> [BrokerProfileQueryData] {
        let profile: DataBrokerProtectionProfile =
            .init(
                names: names.compactMap { $0.toModel() },
                addresses: addresses.compactMap { $0.toModel() },
                phones: [String](),
                birthYear: Int(birthYear) ?? 1990
            )
        let profileQueries = profile.profileQueries
        var brokerProfileQueryData = [BrokerProfileQueryData]()

        let resolvedBroker = brokerWithId(broker)
        for profileQuery in profileQueries {
            let profileQueryId = DebugHelper.stableId(for: profileQuery)
            let fakeScanJobData = ScanJobData(brokerId: DebugHelper.stableId(for: resolvedBroker),
                                              profileQueryId: profileQueryId,
                                              historyEvents: [HistoryEvent]())
            brokerProfileQueryData.append(
                .init(dataBroker: resolvedBroker,
                      profileQuery: profileQuery.with(id: profileQueryId),
                      scanJobData: fakeScanJobData)
            )
            profileQueryLabels[profileQueryId] = profileQueryText(for: profileQuery)
        }

        return brokerProfileQueryData
    }

    private func showNoResultsAlert() {
        Task { @MainActor in
            self.showAlert = true
            self.alert = AlertUI.noResults()
        }
    }

    private func brokerWithId(_ broker: DataBroker) -> DataBroker {
        guard broker.id == nil else { return broker }
        return broker.with(id: DebugHelper.stableId(for: broker))
    }

    func showAlert(for error: Error) {
        Task { @MainActor in
            self.showAlert = true
            if let dbpError = error as? DataBrokerProtectionError {
                self.alert = AlertUI.from(error: dbpError)
            }

            Logger.dataBrokerProtection.error("Error when scanning: \(error.localizedDescription, privacy: .public)")
        }
    }

    func syncAge(fromBirthYear newValue: String) {
        guard !isSyncingAgeFields else { return }
        if newValue.isEmpty {
            guard !age.isEmpty else { return }
            isSyncingAgeFields = true
            age = ""
            isSyncingAgeFields = false
            return
        }
        guard let year = Int(newValue) else { return }
        let currentYear = Calendar.current.component(.year, from: Date())
        guard year > 0, year <= currentYear else { return }
        let computedAge = currentYear - year
        let computedAgeText = String(computedAge)
        guard age != computedAgeText else { return }
        isSyncingAgeFields = true
        age = computedAgeText
        isSyncingAgeFields = false
    }

    func syncBirthYear(fromAge newValue: String) {
        guard !isSyncingAgeFields else { return }
        if newValue.isEmpty {
            guard !birthYear.isEmpty else { return }
            isSyncingAgeFields = true
            birthYear = ""
            isSyncingAgeFields = false
            return
        }
        guard let parsedAge = Int(newValue) else { return }
        let currentYear = Calendar.current.component(.year, from: Date())
        let computedYear = currentYear - parsedAge
        guard computedYear > 0 else { return }
        let computedYearText = String(computedYear)
        guard birthYear != computedYearText else { return }
        isSyncingAgeFields = true
        birthYear = computedYearText
        isSyncingAgeFields = false
    }

    func appVersion() -> String {
        AppVersion.shared.versionNumber
    }

    var dbpEndpoint: String {
        DataBrokerProtectionSettings(defaults: .dbp).endpointURL.absoluteString
    }

    func addDebugEvent(kind: DebugEventKind, summary: String, profileQueryLabel: String, details: String, progressText: String) {
        let event = DebugLogEvent(
            timestamp: Date(),
            kind: kind,
            profileQueryLabel: profileQueryLabel,
            summary: summary,
            details: details
        )
        Task { @MainActor in
            self.debugEvents.append(event)
        }
        updateProgress(progressText)
    }

    func addHistoryDebugEvent(summary: String, details: String) {
        let event = DebugLogEvent(
            timestamp: Date(),
            kind: .history,
            profileQueryLabel: "-",
            summary: summary,
            details: details
        )
        Task { @MainActor in
            self.debugEvents.append(event)
        }
    }

    func actionSummary(stepType: StepType, actionType: ActionType?) -> String {
        let typeText = actionType?.rawValue ?? "unknown"
        return "\(stepType.rawValue) > \(typeText)"
    }

    func currentActionText(stepType: StepType, actionType: ActionType?, prefix: String) -> String {
        let typeText = actionType?.rawValue ?? "unknown"
        return "\(prefix): \(stepType.rawValue) > \(typeText)"
    }

    func profileQueryText(for profileQuery: ProfileQuery) -> String {
        let nameText = "\(profileQuery.firstName) \(profileQuery.lastName)"
        let locationText = "\(profileQuery.city) \(profileQuery.state)"
        return "\(nameText) x \(locationText)"
    }

    func updateProgress(_ text: String) {
        Task { @MainActor in
            self.progressText = text
            self.isProgressActive = true
        }
    }
}

extension DataBrokerRunCustomJSONViewModel {
    func loadPresets() {
        guard #available(macOS 12.0, *) else { return }
        presetsText = UserDefaults.dbp.string(forKey: ProfilePreset.Constants.presetKey) ?? ""
        presets = parsePresets(from: presetsText)
    }

    func savePresets() {
        guard #available(macOS 12.0, *) else { return }
        UserDefaults.dbp.set(presetsText, forKey: ProfilePreset.Constants.presetKey)
        presets = parsePresets(from: presetsText)
    }

    func applyPreset(_ preset: ProfilePreset) {
        guard #available(macOS 12.0, *) else { return }
        names = Array(preset.names.prefix(Constants.maxNames))
        addresses = Array(preset.addresses.prefix(Constants.maxAddresses))
        if names.isEmpty { names = [NameUI.empty()] }
        if addresses.isEmpty { addresses = [AddressUI.empty()] }
        birthYear = preset.birthYear
        syncAge(fromBirthYear: birthYear)
    }

    func saveCurrentFormAsPreset() {
        guard #available(macOS 12.0, *) else { return }

        let namesLine = names.compactMap { name in
            guard let components = PersonNameComponents(name: name) else { return nil }
            let formatted = PersonNameComponentsFormatter().string(from: components)
            return formatted.isEmpty ? nil : formatted
        }.joined(separator: ProfilePreset.Constants.entrySeparator)

        let addressesLine = addresses.compactMap { address -> String? in
            guard let model = address.toModel() else { return nil }
            return "\(model.city)\(ProfilePreset.Constants.partSeparator) \(model.state)"
        }.joined(separator: ProfilePreset.Constants.entrySeparator)

        let birthYearLine = birthYear.trimmed()

        guard !namesLine.isEmpty, !addressesLine.isEmpty, !birthYearLine.isEmpty else {
            return
        }

        let profileBlock = [namesLine, addressesLine, birthYearLine].joined(separator: ProfilePreset.Constants.fieldSeparator)

        presetsText = "\(presetsText)\(ProfilePreset.Constants.profileSeparator)\(profileBlock)"
        savePresets()
    }

    private func parsePresets(from text: String) -> [ProfilePreset] {
        let profileBlocks = text.split(by: ProfilePreset.Constants.profileSeparator)
        var parsedPresets: [ProfilePreset] = []

        for block in profileBlocks {
            let lines = block.split(by: ProfilePreset.Constants.fieldSeparator)
            guard lines.count >= 3 else { continue }

            let names = lines[0].toNames()
            let addresses = lines[1].toAddresses()
            let birthYear = lines[2].trimmed()

            parsedPresets.append(ProfilePreset(names: names, addresses: addresses, birthYear: birthYear))
        }

        return parsedPresets
    }

}

fileprivate extension String {
    func trimmed() -> String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func toNames() -> [NameUI] {
        split(by: ProfilePreset.Constants.entrySeparator).compactMap { entry in
            guard #available(macOS 12.0, *) else { return nil }
            let formatter = PersonNameComponentsFormatter()
            let components = formatter.personNameComponents(from: entry)
            return components.flatMap { NameUI(components: $0) }
        }
    }

    func toAddresses() -> [AddressUI] {
        split(by: ProfilePreset.Constants.entrySeparator).compactMap { entry in
            let parts = entry.components(separatedBy: ProfilePreset.Constants.partSeparator).map { $0.trimmed() }
            guard parts.count == 2 else { return nil }
            return AddressUI(city: parts[0], state: parts[1])
        }
    }

    func split(by separator: String) -> [String] {
        components(separatedBy: separator)
            .map { $0.trimmed() }
            .filter { !$0.isEmpty }
    }
}

fileprivate extension PersonNameComponents {
    init?(name: NameUI) {
        let trimmedFirst = name.first.trimmed()
        let trimmedMiddle = name.middle.trimmed()
        let trimmedLast = name.last.trimmed()
        if trimmedFirst.isEmpty && trimmedMiddle.isEmpty && trimmedLast.isEmpty {
            return nil
        }

        guard #available(macOS 12.0, *) else { return nil }

        self.init()
        self.givenName = trimmedFirst
        self.middleName = trimmedMiddle.isEmpty ? nil : trimmedMiddle
        self.familyName = trimmedLast
    }
}

struct DebugLogEvent: Identifiable {
    let id = UUID()
    let timestamp: Date
    let kind: DebugEventKind
    let profileQueryLabel: String
    let summary: String
    let details: String
}

struct DebugEventRow: Identifiable {
    let id: String
    let timestamp: Date
    let kind: String
    let profileQueryLabel: String
    let summary: String
    let details: String
}

final class FakeStageDurationCalculator: StageDurationCalculator, DebugEventReporting {

    var attemptId: UUID = UUID()
    var isImmediateOperation: Bool = false
    var tries = 1
    private let onDebugEvent: ((DebugEventKind, ActionType?, String) -> Void)?

    init(onDebugEvent: ((DebugEventKind, ActionType?, String) -> Void)? = nil) {
        self.onDebugEvent = onDebugEvent
    }

    func durationSinceLastStage() -> Double {
        0.0
    }

    func durationSinceStartTime() -> Double {
        0.0
    }

    func fireOptOutStart() {
    }

    func setEmailPattern(_ emailPattern: String?) {
    }

    func fireOptOutEmailGenerate() {
    }

    func fireOptOutCaptchaParse() {
    }

    func fireOptOutCaptchaSend() {
    }

    func fireOptOutCaptchaSolve() {
    }

    func fireOptOutSubmit() {
    }

    func fireOptOutEmailReceive() {
    }

    func fireOptOutEmailConfirm() {
    }

    func fireOptOutFillForm() {
    }

    func fireOptOutValidate() {
    }

    func fireOptOutSubmitSuccess(tries: Int) {
    }

    func fireOptOutFailure(tries: Int, error: Error) {
    }

    func fireScanSuccess(matchesFound: Int) {
    }

    func fireScanNoResults() {
    }

    func fireScanError(error: Error) {
    }

    func setStage(_ stage: Stage) {
    }

    func setLastAction(_ action: Action) {
    }

    func fireOptOutConditionFound() {
    }

    func fireOptOutConditionNotFound() {
    }

    func resetTries() {
        self.tries = 1
    }

    func incrementTries() {
        self.tries += 1
    }

    func recordDebugEvent(kind: DebugEventKind,
                          actionType: ActionType?,
                          details: String) {
        onDebugEvent?(kind, actionType, details)
    }
}

extension DataBroker {
    func toJSONString() -> String {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted // Optional: for pretty-printed JSON
            let jsonData = try encoder.encode(self)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            }

            return ""
        } catch {
            print("Error encoding object to JSON: \(error)")
            return ""
        }

    }
}

extension DataBrokerProtectionError {
    var title: String {
        switch self {
        case .httpError(let code):
            if code == 404 {
                return "No results (404)"
            } else {
                return "Error."
            }
        default: return "Error"
        }
    }
}

// swiftlint:enable force_try

private struct MockLocalBrokerJSONService: LocalBrokerJSONServiceProvider {
    func bundledBrokers() throws -> [DataBroker]? { [] }
    func checkForUpdates() async throws {}
}

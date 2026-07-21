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

import BrowserServicesKit
import Common
import DataBrokerProtectionCore
import FeatureFlags
import Foundation
import FoundationExtensions
import os.log
import PIRDebugKit
import PixelKit
import PrivacyConfig

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
    @Published var results = [DebugScanResult]()
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

    /// Optional path to a custom `contentScopeIsolated.js` used for debug-mode runs. Empty means the
    /// bundled script. Threaded through `InjectedScriptSource.file(url)` into the session.
    @Published var customContentScopeScriptPath: String = ""

    var alert: AlertUI?
    var selectedDataBroker: DataBroker?
    var error: Error?
    var profileQueryLabels: [Int64: String] = [:]

    let brokerResources: [BrokerResource]
    var brokers: [DataBroker] { brokerResources.map(\.broker) }

    /// Real PixelKit-backed handler (stays app-side; used by the vault error reporter for the broker
    /// picker). Never passed into PIRDebugKit — the session gets ``fakePixelHandler`` instead.
    let pixelHandler: EventMapping<DataBrokerProtectionSharedPixels>
    let fakePixelHandler: EventMapping<DataBrokerProtectionSharedPixels> = EventMapping { event, _, _, _ in
        Logger.dataBrokerProtection.debug("Debug event: \(String(describing: event), privacy: .public)")
    }
    private let authenticationManager: DataBrokerProtectionAuthenticationManaging
    let featureFlagger: DBPFeatureFlagging
    let applicationNameForUserAgentProvider: () -> String?

    /// The engine. Recreated at the start of each scan and each fresh opt-out (so edited broker JSON
    /// and a changed script path take effect); the email-confirmation check/continue reuse the
    /// session that ran the opt-out.
    private(set) var session: PIRDebugSession?
    private var eventTask: Task<Void, Never>?
    var currentStepType: StepType = .scan
    /// Fallback store used only before any session has been created.
    let placeholderEmailConfirmationStore = DebugEmailConfirmationStore()

    private var isSyncingAgeFields = false

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
         featureFlagger: DBPFeatureFlagging,
         applicationNameForUserAgentProvider: @escaping () -> String?) {
        self.featureFlagger = featureFlagger
        self.applicationNameForUserAgentProvider = applicationNameForUserAgentProvider
        self.authenticationManager = authenticationManager

        // Real pixels + vault are app-side only: the vault backs the broker picker and requires app
        // entitlements. The scan/opt-out engine (PIRDebugSession) is built lazily per run and never
        // touches the vault, PixelKit, or the app group.
        let pixelKit = PixelKit.shared!
        let sharedPixelsHandler = DataBrokerProtectionSharedPixelsHandler(pixelKit: pixelKit, platform: .macOS)
        self.pixelHandler = sharedPixelsHandler
        let reporter = DataBrokerProtectionSecureVaultErrorReporter(pixelHandler: sharedPixelsHandler,
                                                                    privacyConfigManager: DBPPrivacyConfigurationManager())
        let databaseURL = DefaultDataBrokerProtectionDatabaseProvider.databaseFilePath(directoryName: DatabaseConstants.directoryName, fileName: DatabaseConstants.fileName, appGroupIdentifier: Bundle.main.appGroupName)
        let vaultFactory = createDataBrokerProtectionSecureVaultFactory(appGroupName: Bundle.main.appGroupName, databaseFileURL: databaseURL)
        let vault = try! vaultFactory.makeVault(reporter: reporter)

        self.brokerResources = try! vault.fetchAllBrokerResources()

        loadPresets()
    }

    deinit {
        eventTask?.cancel()
    }

    // MARK: - Session

    /// The injected-script source derived from the optional custom script path.
    private var scriptSource: InjectedScriptSource {
        let trimmed = customContentScopeScriptPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .bundled }
        return .file(URL(fileURLWithPath: trimmed))
    }

    /// Email/captcha endpoint matching the app's configured DBP endpoint (passed to the session as an
    /// explicit base URL so targeting doesn't depend on the `#if DEBUG` serviceRoot override).
    private var servicesEndpoint: PIRServicesEndpoint {
        .custom(DataBrokerProtectionSettings(defaults: .dbp).endpointURL)
    }

    /// Builds a fresh session for the current inputs and starts consuming its event stream.
    @MainActor
    private func recreateSession() throws -> PIRDebugSession {
        eventTask?.cancel()
        let configuration = try PIRDebugSessionConfiguration(
            rulesSource: InlineJSONBrokerRulesProvider(json: "{}"), // unused: the debug window scans a broker it decodes itself
            authManager: authenticationManager,
            scriptSource: scriptSource,
            showWebView: true,
            operationAwaitTime: 3,
            servicesEndpoint: servicesEndpoint,
            userAgentApplicationName: applicationNameForUserAgentProvider(),
            featureFlagger: featureFlagger,
            pixelHandler: fakePixelHandler)
        let newSession = try PIRDebugSession(configuration: configuration)
        self.session = newSession
        let stream = newSession.events
        eventTask = Task { [weak self] in
            for await event in stream {
                await self?.handleSessionEvent(event)
            }
        }
        return newSession
    }

    @MainActor
    private func handleSessionEvent(_ event: PIRDebugEvent) {
        let kind = Self.debugEventKind(from: event.kind)
        let summary: String
        if event.kind == .history {
            summary = "Email confirmation"
        } else {
            summary = "\(currentStepType.rawValue) > \(event.actionType ?? "unknown")"
        }
        debugEvents.append(DebugLogEvent(timestamp: event.timestamp,
                                         kind: kind,
                                         profileQueryLabel: event.profileQueryLabel,
                                         summary: summary,
                                         details: event.details))
        if event.kind != .history {
            updateProgress("\(kind.rawValue): \(summary)")
        }
    }

    private static func debugEventKind(from kind: PIRDebugEvent.Kind) -> DebugEventKind {
        switch kind {
        case .actionPayload: return .actionPayload
        case .actionResponse: return .actionResponse
        case .actionRetry: return .actionRetry
        case .wait: return .wait
        case .history: return .history
        }
    }

    private func makeProfile() -> DataBrokerProtectionProfile {
        .init(names: names.compactMap { $0.toModel() },
              addresses: addresses.compactMap { $0.toModel() },
              phones: [String](),
              birthYear: Int(birthYear) ?? 1990)
    }

    @MainActor
    func runJSON(jsonString: String) {
        self.error = nil
        self.results.removeAll()
        self.debugEvents.removeAll()
        self.isProgressActive = true
        self.progressText = "Starting scan..."

        guard let data = jsonString.data(using: .utf8) else {
            self.isProgressActive = false
            self.progressText = "Idle"
            return
        }

        let dataBroker: DataBroker
        do {
            dataBroker = try JSONDecoder().decode(DataBroker.self, from: data)
        } catch {
            self.isProgressActive = false
            self.progressText = "Idle"
            showAlert(for: error)
            return
        }
        self.selectedDataBroker = dataBroker

        let profile = makeProfile()
        let queries = createBrokerProfileQueryData(for: dataBroker)
        var queriesById: [Int64: BrokerProfileQueryData] = [:]
        for query in queries {
            queriesById[DebugHelper.stableId(for: query.profileQuery)] = query
        }

        let session: PIRDebugSession
        do {
            session = try recreateSession()
        } catch {
            self.isProgressActive = false
            self.progressText = "Idle"
            showAlert(for: error)
            return
        }

        currentStepType = .scan
        for query in queries {
            addScanStartedEvent(for: query)
        }

        Task { @MainActor in
            do {
                let result = try await session.scan(broker: dataBroker, profile: profile)

                for record in result.extractedProfiles {
                    guard let query = queriesById[record.profileQueryId] else { continue }
                    self.results.append(DebugScanResult(dataBroker: query.dataBroker,
                                                        profileQuery: query.profileQuery,
                                                        extractedProfile: record.extractedProfile))
                }

                for status in result.queryStatuses {
                    guard let query = queriesById[status.profileQueryId] else { continue }
                    switch status.outcome {
                    case .matches, .noMatch:
                        let profilesForQuery = result.extractedProfiles
                            .filter { $0.profileQueryId == status.profileQueryId }
                            .map { $0.extractedProfile }
                        addScanResultEvents(for: query, extractedProfiles: profilesForQuery)
                    case .error:
                        let error = DataBrokerProtectionError.unknown(status.error ?? "Unknown error")
                        addScanErrorEvent(for: query, error: error)
                        self.error = error
                    }
                }

                self.isProgressActive = false
                self.progressText = "Idle"
                if let error = self.error {
                    self.showAlert(for: error)
                } else if self.results.isEmpty {
                    self.showNoResultsAlert()
                }
            } catch {
                self.isProgressActive = false
                self.progressText = "Idle"
                self.showAlert(for: error)
            }
        }
    }

    @MainActor
    func runOptOut(scanResult: DebugScanResult, jsonString: String) {
        // Re-decode broker from current JSON editor content so edits take effect without re-scanning
        let dataBroker: DataBroker
        if let data = jsonString.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(DataBroker.self, from: data) {
            dataBroker = decoded.with(id: DebugHelper.stableId(for: decoded))
        } else {
            dataBroker = scanResult.dataBroker
        }

        isProgressActive = true
        progressText = "Starting opt-out..."
        addOptOutStartedEvent(for: scanResult)
        currentStepType = .optOut

        let session: PIRDebugSession
        do {
            session = try recreateSession()
        } catch {
            isProgressActive = false
            progressText = "Idle"
            showAlert(for: error)
            return
        }

        Task { @MainActor in
            do {
                let result = try await session.optOut(broker: dataBroker,
                                                      profileQuery: scanResult.profileQuery,
                                                      extractedProfile: scanResult.extractedProfile)

                if result.awaitingEmailConfirmation {
                    self.addOptOutAwaitingEmailConfirmationEvent(for: scanResult)
                    self.isProgressActive = false
                    self.progressText = "Awaiting email confirmation"
                    self.showAlert = true
                    self.alert = AlertUI(title: "Opt-out submitted awaiting email confirmation",
                                         description: "Use \"Check for email confirmation\" to continue. You may need to run it multiple times.")
                } else if result.success {
                    self.addOptOutConfirmedEvent(for: scanResult)
                    self.isProgressActive = false
                    self.progressText = "Idle"
                    self.showAlert = true
                    self.alert = AlertUI(title: "Success!", description: "We finished the opt out process for the selected profile.")
                } else {
                    let error = DataBrokerProtectionError.unknown(result.error ?? "Unknown error")
                    self.addOptOutErrorEvent(for: scanResult, error: error)
                    self.isProgressActive = false
                    self.progressText = "Idle"
                    self.showAlert(for: error)
                }
            } catch {
                self.addOptOutErrorEvent(for: scanResult, error: error)
                self.isProgressActive = false
                self.progressText = "Idle"
                self.showAlert(for: error)
            }
        }
    }

    private func createBrokerProfileQueryData(for broker: DataBroker) -> [BrokerProfileQueryData] {
        let profileQueries = makeProfile().profileQueries
        var brokerProfileQueryData = [BrokerProfileQueryData]()

        let resolvedBroker = broker.with(id: DebugHelper.stableId(for: broker))
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

    func brokerJSONString(for brokerURL: String) -> String {
        guard let brokerResource = brokerResources.first(where: { $0.broker.url == brokerURL }) else {
            return ""
        }

        return DebugHelper.prettyJSONString(from: brokerResource.rawJSON) ?? (String(data: brokerResource.rawJSON, encoding: .utf8) ?? "")
    }

    var dbpEndpoint: String {
        DataBrokerProtectionSettings(defaults: .dbp).endpointURL.absoluteString
    }

    var applicationNameForUserAgentDisplayValue: String {
        applicationNameForUserAgentProvider() ?? "nil"
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
        presetsText = UserDefaults.dbp.string(forKey: ProfilePreset.Constants.presetKey) ?? ""
        presets = parsePresets(from: presetsText)
    }

    func savePresets() {
        UserDefaults.dbp.set(presetsText, forKey: ProfilePreset.Constants.presetKey)
        presets = parsePresets(from: presetsText)
    }

    func applyPreset(_ preset: ProfilePreset) {
        names = Array(preset.names.prefix(Constants.maxNames))
        addresses = Array(preset.addresses.prefix(Constants.maxAddresses))
        if names.isEmpty { names = [NameUI.empty()] }
        if addresses.isEmpty { addresses = [AddressUI.empty()] }
        birthYear = preset.birthYear
        syncAge(fromBirthYear: birthYear)
    }

    func saveCurrentFormAsPreset() {
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
    func bundledBrokers() throws -> [BrokerResource]? { [] }
    func checkForUpdates() async throws {}
}

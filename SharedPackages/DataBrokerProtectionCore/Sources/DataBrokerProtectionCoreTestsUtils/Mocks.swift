//
//  Mocks.swift
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
import Combine
import Common
import Foundation
import GRDB
import SecureStorage

@testable import DataBrokerProtectionCore

// swiftlint:disable force_try
// swiftlint:disable identifier_name
// swiftlint:disable large_tuple

public extension BrokerProfileQueryData {

    static func mock(with steps: [Step] = [Step](),
                     dataBrokerName: String = "test",
                     url: String = "test.com",
                     parentURL: String? = nil,
                     optOutUrl: String? = nil,
                     lastRunDate: Date? = nil,
                     preferredRunDate: Date? = nil,
                     extractedProfile: ExtractedProfile? = nil,
                     scanHistoryEvents: [HistoryEvent] = [HistoryEvent](),
                     mirrorSites: [MirrorSite] = [MirrorSite](),
                     deprecated: Bool = false,
                     optOutJobData: [OptOutJobData]? = nil) -> BrokerProfileQueryData {
        BrokerProfileQueryData(
            dataBroker: DataBroker(
                name: dataBrokerName,
                url: url,
                steps: steps,
                version: "1.0.0",
                schedulingConfig: DataBrokerScheduleConfig.mock,
                parent: parentURL,
                mirrorSites: mirrorSites,
                optOutUrl: optOutUrl ?? "",
                eTag: ""
            ),
            profileQuery: ProfileQuery(firstName: "John", lastName: "Doe", city: "Miami", state: "FL", birthYear: 50, deprecated: deprecated),
            scanJobData: ScanJobData(brokerId: 1,
                                     profileQueryId: 1,
                                     preferredRunDate: preferredRunDate,
                                     historyEvents: scanHistoryEvents,
                                     lastRunDate: lastRunDate),
            optOutJobData: optOutJobData ?? (extractedProfile != nil ? [.mock(with: extractedProfile!)] : [OptOutJobData]())
        )
    }

    static var queryDataWithMultipleSuccessfulOptOutRequestsIn24Hours: [BrokerProfileQueryData] {
        let optOutJobDataParams: [(Int64, Int64, Int, Int, Int)] = [
            (1, 1, 24, 23, 25)
        ]
        return [createQueryData(brokerId: 1, optOutJobDataParams: optOutJobDataParams)]
    }

    static var queryDataTwoBrokers50PercentSuccessEach: [BrokerProfileQueryData] {
        let broker1OptOutJobDataParams: [(Int64, Int64, Int, Int, Int)] = [
            (1, 1, 24, 23, 25),
            (2, 2, 24, 0, 25)
        ]

        let broker2OptOutJobDataParams: [(Int64, Int64, Int, Int, Int)] = [
            (3, 3, 24, 23, 25),
            (4, 4, 24, 0, 25)
        ]

        let broker1Data = createQueryData(brokerId: 1, optOutJobDataParams: broker1OptOutJobDataParams)
        let broker2Data = createQueryData(brokerId: 2, optOutJobDataParams: broker2OptOutJobDataParams)

        return [broker1Data, broker2Data]
    }

    static var queryDataWithNoOptOutsInDateRange: [BrokerProfileQueryData] {
        let optOutJobDataParams: [(Int64, Int64, Int, Int, Int)] = [
            (1, 1, 48, 47, 49)
        ]
        return [createQueryData(brokerId: 1, optOutJobDataParams: optOutJobDataParams)]
    }

    static var queryDataMultipleBrokersVaryingSuccessRates: [BrokerProfileQueryData] {
        let broker1OptOutJobDataParams: [(Int64, Int64, Int, Int, Int)] = [
            (1, 1, 24, 23, 25),
            (2, 2, 24, 23, 25),
            (3, 3, 24, 23, 25),
            (4, 4, 24, 0, 25)
        ]

        let broker2OptOutJobDataParams: [(Int64, Int64, Int, Int, Int)] = [
            (5, 5, 24, 23, 25),
            (6, 6, 24, 0, 25)
        ]

        let broker3OptOutJobDataParams: [(Int64, Int64, Int, Int, Int)] = [
            (7, 7, 24, 23, 25)
        ]

        let broker1Data = createQueryData(brokerId: 1, optOutJobDataParams: broker1OptOutJobDataParams)
        let broker2Data = createQueryData(brokerId: 2, optOutJobDataParams: broker2OptOutJobDataParams)
        let broker3Data = createQueryData(brokerId: 3, optOutJobDataParams: broker3OptOutJobDataParams)

        return [broker1Data, broker2Data, broker3Data]
    }

    static func createOptOutJobData(extractedProfileId: Int64, brokerId: Int64, profileQueryId: Int64, preferredRunDate: Date?) -> OptOutJobData {

        let extractedProfile = ExtractedProfile(id: extractedProfileId)

        return OptOutJobData(brokerId: brokerId, profileQueryId: profileQueryId, createdDate: Date(), preferredRunDate: preferredRunDate, historyEvents: [], attemptCount: 0, extractedProfile: extractedProfile)
    }

    static func createOptOutJobData(extractedProfileId: Int64, brokerId: Int64, profileQueryId: Int64, startEventHoursAgo: Int, requestEventHoursAgo: Int, jobCreatedHoursAgo: Int) -> OptOutJobData {

        let extractedProfile = ExtractedProfile(id: extractedProfileId)

        let startedEvent = optOutEvent(extractedProfileId: extractedProfileId, brokerId: brokerId, profileQueryId: profileQueryId, type: .optOutStarted, date: .nowMinus(hours: startEventHoursAgo))

        if requestEventHoursAgo != 0 {
            let requestedEvent = optOutEvent(extractedProfileId: extractedProfileId, brokerId: brokerId, profileQueryId: profileQueryId, type: .optOutRequested, date: .nowMinus(hours: requestEventHoursAgo))

            return OptOutJobData(brokerId: brokerId, profileQueryId: profileQueryId, createdDate: .nowMinus(hours: jobCreatedHoursAgo), historyEvents: [startedEvent, requestedEvent], attemptCount: 0, extractedProfile: extractedProfile)
        } else {
            return OptOutJobData(brokerId: brokerId, profileQueryId: profileQueryId, createdDate: .nowMinus(hours: jobCreatedHoursAgo), historyEvents: [startedEvent], attemptCount: 0, extractedProfile: extractedProfile)
        }
    }

    static func createQueryData(brokerId: Int64, optOutJobDataParams: [(extractedProfileId: Int64, profileQueryId: Int64, startEventHoursAgo: Int, requestEventHoursAgo: Int, jobCreatedHoursAgo: Int)]) -> BrokerProfileQueryData {

        let optOutJobDataList = optOutJobDataParams.map { params in
            createOptOutJobData(extractedProfileId: params.extractedProfileId, brokerId: brokerId, profileQueryId: params.profileQueryId, startEventHoursAgo: params.startEventHoursAgo, requestEventHoursAgo: params.requestEventHoursAgo, jobCreatedHoursAgo: params.jobCreatedHoursAgo)
        }

        return BrokerProfileQueryData(dataBroker: .mock(withId: brokerId), profileQuery: .mock, scanJobData: .mock(withBrokerId: brokerId), optOutJobData: optOutJobDataList)
    }

    static func optOutEvent(extractedProfileId: Int64, brokerId: Int64, profileQueryId: Int64, type: HistoryEvent.EventType, date: Date) -> HistoryEvent {
        HistoryEvent(extractedProfileId: extractedProfileId, brokerId: brokerId, profileQueryId: profileQueryId, type: type, date: date)
    }
}

public extension HistoryEvent {
    static func mockScanEvent(with date: Date) -> HistoryEvent {
        HistoryEvent(brokerId: 1, profileQueryId: 1, type: .scanStarted, date: date)
    }

    static func mock(type: EventType, date: Date = Date()) -> HistoryEvent {
        HistoryEvent(brokerId: 1, profileQueryId: 1, type: type, date: date)
    }
}

public extension DataBrokerScheduleConfig {
    static var mock: DataBrokerScheduleConfig {
        DataBrokerScheduleConfig(retryError: 1, confirmOptOutScan: 2, maintenanceScan: 3, maxAttempts: -1)
    }
}

public final class InternalUserDeciderStoreMock: InternalUserStoring {
    public var isInternalUser: Bool = false
}

public final class PrivacyConfigurationManagingMock: PrivacyConfigurationManaging {
    public var currentConfig: Data = Data()

    public var updatesPublisher: AnyPublisher<Void, Never> = .init(Just(()))

    public var privacyConfig: BrowserServicesKit.PrivacyConfiguration = PrivacyConfigurationMock()

    public var internalUserDecider: InternalUserDecider = DefaultInternalUserDecider(store: InternalUserDeciderStoreMock())

    public init() {}

    public func reload(etag: String?, data: Data?) -> PrivacyConfigurationManager.ReloadResult {
        .downloaded
    }
}

public final class PrivacyConfigurationMock: PrivacyConfiguration {

    public var identifier: String = "mock"
    public var version: String? = "123456789"

    public var userUnprotectedDomains = [String]()

    public var tempUnprotectedDomains = [String]()

    public var trackerAllowlist = BrowserServicesKit.PrivacyConfigurationData.TrackerAllowlist(entries: [String: [PrivacyConfigurationData.TrackerAllowlist.Entry]](), state: "mock")

    public var isSubfeatureEnabledCheck: ((any PrivacySubfeature) -> Bool)?

    public func isSubfeatureEnabled(_ subfeature: any PrivacySubfeature, versionProvider: AppVersionProvider, randomizer: (Range<Double>) -> Double, defaultValue: Bool) -> Bool {
        return isSubfeatureEnabledCheck?(subfeature) ?? false
    }

    public func isEnabled(featureKey: PrivacyFeature, versionProvider: AppVersionProvider, defaultValue: Bool) -> Bool {
        false
    }

    public func stateFor(featureKey: BrowserServicesKit.PrivacyFeature, versionProvider: BrowserServicesKit.AppVersionProvider) -> BrowserServicesKit.PrivacyConfigurationFeatureState {
        .disabled(.disabledInConfig)
    }

    public func stateFor(_ subfeature: any PrivacySubfeature, versionProvider: BrowserServicesKit.AppVersionProvider, randomizer: (Range<Double>) -> Double) -> BrowserServicesKit.PrivacyConfigurationFeatureState {
        .disabled(.disabledInConfig)
    }

    public func exceptionsList(forFeature featureKey: BrowserServicesKit.PrivacyFeature) -> [String] {
        [String]()
    }

    public func isFeature(_ feature: BrowserServicesKit.PrivacyFeature, enabledForDomain: String?) -> Bool {
        false
    }

    public func isProtected(domain: String?) -> Bool {
        false
    }

    public func isUserUnprotected(domain: String?) -> Bool {
        false
    }

    public func isTempUnprotected(domain: String?) -> Bool {
        false
    }

    public func isInExceptionList(domain: String?, forFeature featureKey: BrowserServicesKit.PrivacyFeature) -> Bool {
        false
    }

    public func settings(for feature: BrowserServicesKit.PrivacyFeature) -> BrowserServicesKit.PrivacyConfigurationData.PrivacyFeature.FeatureSettings {
        [String: Any]()
    }

    public func settings(for subfeature: any BrowserServicesKit.PrivacySubfeature) -> PrivacyConfigurationData.PrivacyFeature.SubfeatureSettings? {
        return nil
    }

    public func userEnabledProtection(forDomain: String) {

    }

    public func userDisabledProtection(forDomain: String) {

    }

    public func stateFor(subfeatureID: SubfeatureID, parentFeatureID: ParentFeatureID, versionProvider: AppVersionProvider, randomizer: (Range<Double>) -> Double) -> PrivacyConfigurationFeatureState {
        return .disabled(.disabledInConfig)
    }

    public func cohorts(for subfeature: any PrivacySubfeature) -> [PrivacyConfigurationData.Cohort]? {
        return nil
    }

    public func cohorts(subfeatureID: SubfeatureID, parentFeatureID: ParentFeatureID) -> [PrivacyConfigurationData.Cohort]? {
        return nil
    }
}

public final class VPNBypassServiceProviderMock: VPNBypassServiceProvider {
    public var isSupported: Bool = false
    public var isEnabled: Bool = false
    public var bypassStatus: VPNBypassStatus = .off
    public var isOnboardingShown: Bool = false

    public init() {}

    public func applyVPNBypass(_ bypass: Bool) {
        // Mock implementation - no-op
    }
}

public extension ContentScopeProperties {
    static var mock: ContentScopeProperties {
        ContentScopeProperties(
            gpcEnabled: false,
            sessionKey: "sessionKey",
            messageSecret: "messageSecret",
            featureToggles: ContentScopeFeatureToggles.mock
        )
    }
}

public extension ContentScopeFeatureToggles {

    static var mock: ContentScopeFeatureToggles {
        ContentScopeFeatureToggles(
            emailProtection: false,
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
            autocompleteAttributeSupport: false
        )
    }
}

public final class WebViewHandlerMock: NSObject, WebViewHandler {
    public var wasInitializeWebViewCalled = false
    public var wasLoadCalledWithURL: URL?
    public var wasWaitForWebViewLoadCalled = false
    public var wasFinishCalled = false
    public var wasExecuteCalledForUserData = false
    public var wasExecuteCalledForSolveCaptcha = false
    public var wasExecuteJavascriptCalled = false
    public var wasSetCookiesCalled = false
    public var errorStatusCodeToThrow: Int?

    public func initializeWebView(showWebView: Bool) async {
        wasInitializeWebViewCalled = true
    }

    public func load(url: URL) async throws {
        wasLoadCalledWithURL = url

        guard let statusCode = errorStatusCodeToThrow else { return }
        throw DataBrokerProtectionError.httpError(code: statusCode)
    }

    public func waitForWebViewLoad() async throws {
        wasWaitForWebViewLoadCalled = true
    }

    public func finish() async {
        wasFinishCalled = true
    }

    public func execute(action: Action, ofType stepType: StepType?, data: CCFRequestData) async {
        switch data {
        case .solveCaptcha:
            wasExecuteCalledForSolveCaptcha = true
            wasExecuteCalledForUserData = false
        case .userData:
            wasExecuteCalledForUserData = true
            wasExecuteCalledForSolveCaptcha = false
        }
    }

    public func evaluateJavaScript(_ javaScript: String) async throws {
        wasExecuteJavascriptCalled = true
    }

    public func takeSnaphost(path: String, fileName: String) async throws {

    }

    public func saveHTML(path: String, fileName: String) async throws {

    }

    public func setCookies(_ cookies: [HTTPCookie]) async {
        wasSetCookiesCalled = true
    }

    public func reset() {
        wasInitializeWebViewCalled = false
        wasLoadCalledWithURL = nil
        wasWaitForWebViewLoadCalled = false
        wasFinishCalled = false
        wasExecuteCalledForSolveCaptcha = false
        wasExecuteJavascriptCalled = false
        wasExecuteCalledForUserData = false
        wasSetCookiesCalled = false
    }
}

public final class MockCookieHandler: CookieHandler {
    public var cookiesToReturn: [HTTPCookie]?

    public init() {}

    public func getAllCookiesFromDomain(_ url: URL) async -> [HTTPCookie]? {
        return cookiesToReturn
    }

    public func clear() {
        cookiesToReturn = nil
    }
}

public final class EmailServiceMock: EmailServiceProtocol {

    public var shouldThrow: Bool = false

    public init() {}

    public func getEmail(dataBrokerURL: String, attemptId: UUID) async throws -> EmailData {
        if shouldThrow {
            throw DataBrokerProtectionError.emailError(nil)
        }

        return EmailData(pattern: nil, emailAddress: "test@duck.com")
    }

    public func getConfirmationLink(from email: String, numberOfRetries: Int, pollingInterval: TimeInterval, attemptId: UUID, shouldRunNextStep: @escaping () -> Bool) async throws -> URL {
        if shouldThrow {
            throw DataBrokerProtectionError.emailError(nil)
        }

        return URL(string: "https://www.duckduckgo.com")!
    }

    public func reset() {
        shouldThrow = false
    }
}

public final class CaptchaServiceMock: CaptchaServiceProtocol {

    public var wasSubmitCaptchaInformationCalled = false
    public var wasSubmitCaptchaToBeResolvedCalled = false
    public var shouldThrow = false

    public init() {}

    public func submitCaptchaInformation(_ captchaInfo: GetCaptchaInfoResponse, retries: Int, pollingInterval: TimeInterval, attemptId: UUID, shouldRunNextStep: @escaping () -> Bool) async throws -> CaptchaTransactionId {
        if shouldThrow {
            throw CaptchaServiceError.errorWhenSubmittingCaptcha
        }

        wasSubmitCaptchaInformationCalled = true

        return "transactionID"
    }

    public func submitCaptchaToBeResolved(for transactionID: CaptchaTransactionId, retries: Int, pollingInterval: TimeInterval, attemptId: UUID, shouldRunNextStep: @escaping () -> Bool) async throws -> CaptchaResolveData {
        if shouldThrow {
            throw CaptchaServiceError.errorWhenFetchingCaptchaResult
        }

        wasSubmitCaptchaToBeResolvedCalled = true

        return CaptchaResolveData()
    }

    public func reset() {
        wasSubmitCaptchaInformationCalled = false
        wasSubmitCaptchaToBeResolvedCalled = false
    }
}

public final class BrokerUpdaterRepositoryMock: BrokerUpdaterRepository {
    public var wasSaveLatestAppVersionCheckCalled = false
    public var lastCheckedVersion: String?

    public init() {}

    public func saveLatestAppVersionCheck(version: String) {
        wasSaveLatestAppVersionCheckCalled = true
    }

    public func getLastCheckedVersion() -> String? {
        return lastCheckedVersion
    }

    public func reset() {
        wasSaveLatestAppVersionCheckCalled = false
        lastCheckedVersion = nil
    }
}

public final class ResourcesRepositoryMock: ResourcesRepository {
    public var wasFetchBrokerFromResourcesFilesCalled = false
    public var brokersList: [DataBroker]?

    public init() {}

    public func fetchBrokerFromResourceFiles() -> [DataBroker]? {
        wasFetchBrokerFromResourcesFilesCalled = true
        return brokersList
    }

    public func reset() {
        wasFetchBrokerFromResourcesFilesCalled = false
        brokersList?.removeAll()
        brokersList = nil
    }
}

public final class EmptySecureStorageKeyStoreProviderMock: SecureStorageKeyStoreProvider {
    public var generatedPasswordEntryName: String = ""

    public var l1KeyEntryName: String = ""

    public var l2KeyEntryName: String = ""

    public var keychainServiceName: String = ""

    public init() {}

    public func attributesForEntry(named: String, serviceName: String) -> [String: Any] {
        return [String: Any]()
    }
}

public final class EmptySecureStorageCryptoProviderMock: SecureStorageCryptoProvider {
    public var passwordSalt: Data = Data()

    public var keychainServiceName: String = ""

    public var keychainAccountName: String = ""

    public init() {}
}

public final class SecureStorageDatabaseProviderMock: SecureStorageDatabaseProvider {
    public let db: DatabaseWriter

    public init() throws {
        do {
            self.db = try DatabaseQueue()
        } catch {
            throw DataBrokerProtectionError.unknown("")
        }
    }
}

public final class DataBrokerProtectionSecureVaultMock: DataBrokerProtectionSecureVault {
    public var shouldReturnOldVersionBroker = false
    public var shouldReturnNewVersionBroker = false
    public var wasBrokerUpdateCalled = false
    public var wasBrokerSavedCalled = false
    public var wasUpdateProfileQueryCalled = false
    public var wasDeleteProfileQueryCalled = false
    public var wasSaveProfileQueryCalled = false
    public var profile: DataBrokerProtectionProfile?
    public var profileQueries = [ProfileQuery]()
    public var brokers = [DataBroker]()
    public var scanJobData = [ScanJobData]()
    public var optOutJobData = [OptOutJobData]()
    public var lastPreferredRunDateOnScan: Date?

    public typealias DatabaseProvider = SecureStorageDatabaseProviderMock

    required public init(providers: SecureStorageProviders<SecureStorageDatabaseProviderMock>) {
    }

    public func reset() {
        shouldReturnOldVersionBroker = false
        shouldReturnNewVersionBroker = false
        wasBrokerUpdateCalled = false
        wasBrokerSavedCalled = false
        wasUpdateProfileQueryCalled = false
        wasDeleteProfileQueryCalled = false
        wasSaveProfileQueryCalled = false
        profile = nil
        profileQueries.removeAll()
        brokers.removeAll()
        scanJobData.removeAll()
        optOutJobData.removeAll()
        lastPreferredRunDateOnScan = nil
    }

    public func save(profile: DataBrokerProtectionProfile) throws -> Int64 {
        return 1
    }

    public func fetchProfile(with id: Int64) throws -> DataBrokerProtectionProfile? {
        profile
    }

    public func deleteProfileData() throws {
        return
    }

    public func save(broker: DataBroker) throws -> Int64 {
        wasBrokerSavedCalled = true
        return 1
    }

    public func update(_ broker: DataBroker, with id: Int64) throws {
        wasBrokerUpdateCalled = true
    }

    public func fetchBroker(with id: Int64) throws -> DataBroker? {
        return nil
    }

    public func fetchBroker(with name: String) throws -> DataBroker? {
        if shouldReturnOldVersionBroker {
            return .init(id: 1, name: "Broker", url: "broker.com", steps: [Step](), version: "1.0.0", schedulingConfig: .mock, optOutUrl: "", eTag: "")
        } else if shouldReturnNewVersionBroker {
            return .init(id: 1, name: "Broker", url: "broker.com", steps: [Step](), version: "1.0.1", schedulingConfig: .mock, optOutUrl: "", eTag: "")
        }

        return nil
    }

    public func fetchAllBrokers() throws -> [DataBroker] {
        return brokers
    }

    public func save(profileQuery: ProfileQuery, profileId: Int64) throws -> Int64 {
        wasSaveProfileQueryCalled = true
        return 1
    }

    public func fetchProfileQuery(with id: Int64) throws -> ProfileQuery? {
        return nil
    }

    public func fetchAllProfileQueries(for profileId: Int64) throws -> [ProfileQuery] {
        return profileQueries
    }

    public func save(brokerId: Int64, profileQueryId: Int64, lastRunDate: Date?, preferredRunDate: Date?) throws {
        lastPreferredRunDateOnScan = preferredRunDate
    }

    public func updatePreferredRunDate(_ date: Date?, brokerId: Int64, profileQueryId: Int64) throws {
    }

    public func updateLastRunDate(_ date: Date?, brokerId: Int64, profileQueryId: Int64) throws {
    }

    public func updateSubmittedSuccessfullyDate(_ date: Date?, forBrokerId brokerId: Int64, profileQueryId: Int64, extractedProfileId: Int64) throws {
    }

    public func updateSevenDaysConfirmationPixelFired(_ pixelFired: Bool, forBrokerId brokerId: Int64, profileQueryId: Int64, extractedProfileId: Int64) throws {
    }

    public func updateFourteenDaysConfirmationPixelFired(_ pixelFired: Bool, forBrokerId brokerId: Int64, profileQueryId: Int64, extractedProfileId: Int64) throws {
    }

    public func updateTwentyOneDaysConfirmationPixelFired(_ pixelFired: Bool, forBrokerId brokerId: Int64, profileQueryId: Int64, extractedProfileId: Int64) throws {

    }

    public func fetchScan(brokerId: Int64, profileQueryId: Int64) throws -> ScanJobData? {
        scanJobData.first
    }

    public func fetchAllScans() throws -> [ScanJobData] {
        return scanJobData
    }

    public func save(brokerId: Int64,
                     profileQueryId: Int64,
                     extractedProfile: ExtractedProfile,
                     createdDate: Date,
                     lastRunDate: Date?,
                     preferredRunDate: Date?,
                     attemptCount: Int64,
                     submittedSuccessfullyDate: Date?,
                     sevenDaysConfirmationPixelFired: Bool,
                     fourteenDaysConfirmationPixelFired: Bool,
                     twentyOneDaysConfirmationPixelFired: Bool) throws {
    }

    public func updatePreferredRunDate(_ date: Date?, brokerId: Int64, profileQueryId: Int64, extractedProfileId: Int64) throws {
    }

    public func updateLastRunDate(_ date: Date?, brokerId: Int64, profileQueryId: Int64, extractedProfileId: Int64) throws {
    }

    public func updateAttemptCount(_ count: Int64, brokerId: Int64, profileQueryId: Int64, extractedProfileId: Int64) throws {
    }

    public func incrementAttemptCount(brokerId: Int64, profileQueryId: Int64, extractedProfileId: Int64) throws {
    }

    public func fetchOptOut(brokerId: Int64, profileQueryId: Int64, extractedProfileId: Int64) throws -> OptOutJobData? {
        optOutJobData.first
    }

    public func fetchOptOuts(brokerId: Int64, profileQueryId: Int64) throws -> [OptOutJobData] {
        return optOutJobData
    }

    public func fetchOptOuts(brokerId: Int64) throws -> [OptOutJobData] {
        return optOutJobData
    }

    public func fetchAllOptOuts() throws -> [OptOutJobData] {
        return optOutJobData
    }

    public func save(historyEvent: HistoryEvent, brokerId: Int64, profileQueryId: Int64) throws {
    }

    public func save(historyEvent: HistoryEvent, brokerId: Int64, profileQueryId: Int64, extractedProfileId: Int64) throws {
    }

    public func fetchEvents(brokerId: Int64, profileQueryId: Int64) throws -> [HistoryEvent] {
        return [HistoryEvent]()
    }

    public func save(extractedProfile: ExtractedProfile, brokerId: Int64, profileQueryId: Int64) throws -> Int64 {
        return 1
    }

    public func fetchExtractedProfile(with id: Int64) throws -> (brokerId: Int64, profileQueryId: Int64, profile: ExtractedProfile)? {
        return nil
    }

    public func fetchExtractedProfiles(for brokerId: Int64, with profileQueryId: Int64) throws -> [ExtractedProfile] {
        return [ExtractedProfile]()
    }

    public func fetchExtractedProfiles(for brokerId: Int64) throws -> [ExtractedProfile] {
        return [ExtractedProfile]()
    }

    public func updateRemovedDate(for extractedProfileId: Int64, with date: Date?) throws {
    }

    public func hasMatches() throws -> Bool {
        false
    }

    public func fetchChildBrokers(for parentBroker: String) throws -> [DataBroker] {
        return [DataBroker]()
    }

    public func update(profile: DataBrokerProtectionProfile) throws -> Int64 {
        return 1
    }

    public func delete(profileQuery: ProfileQuery, profileId: Int64) throws {
        wasDeleteProfileQueryCalled = true
    }

    public func update(_ profileQuery: ProfileQuery, brokerIDs: [Int64], profileId: Int64) throws -> Int64 {
        wasUpdateProfileQueryCalled = true
        return 1
    }

    public func fetchAllAttempts() throws -> [AttemptInformation] {
        []
    }

    public func fetchAttemptInformation(for extractedProfileId: Int64) throws -> AttemptInformation? {
        return nil
    }

    public func save(extractedProfileId: Int64, attemptUUID: UUID, dataBroker: String, lastStageDate: Date, startTime: Date) throws {
    }

    public func fetchFirstEligibleJobDate() throws -> Date? {
        return nil
    }
}

public class MockDataBrokerProtectionPixelsHandler: EventMapping<DataBrokerProtectionSharedPixels> {

    public static var lastPixelsFired = [DataBrokerProtectionSharedPixels]()

    public init() {
        super.init { event, _, _, _ in
            MockDataBrokerProtectionPixelsHandler.lastPixelsFired.append(event)
        }
    }

    override init(mapping: @escaping EventMapping<DataBrokerProtectionSharedPixels>.Mapping) {
        fatalError("Use init()")
    }

    public func clear() {
        MockDataBrokerProtectionPixelsHandler.lastPixelsFired.removeAll()
    }
}

public final class MockDatabase: DataBrokerProtectionRepository {
    public enum MockError: Error {
        case saveFailed
    }

    public var wasSaveProfileCalled = false
    public var wasFetchProfileCalled = false
    public var wasDeleteProfileDataCalled = false
    public var wasSaveOptOutOperationCalled = false
    public var wasBrokerProfileQueryDataCalled = false
    public var wasFetchAllBrokerProfileQueryDataCalled = false
    public var wasFetchAllDataBrokersCalled = false
    public var wasUpdatedPreferredRunDateForScanCalled = false
    public var wasUpdatedPreferredRunDateForOptOutCalled = false
    public var wasUpdateLastRunDateForScanCalled = false
    public var wasUpdateLastRunDateForOptOutCalled = false
    public var wasUpdateSubmittedSuccessfullyDateForOptOutCalled = false
    public var wasUpdateSevenDaysConfirmationPixelFired = false
    public var wasUpdateFourteenDaysConfirmationPixelFired = false
    public var wasUpdateTwentyOneDaysConfirmationPixelFired = false
    public var wasUpdateRemoveDateCalled = false
    public var wasAddHistoryEventCalled = false
    public var wasFetchLastHistoryEventCalled = false

    public var fetchAllBrokerProfileQueryDataError: Error?
    public var lastHistoryEventToReturn: HistoryEvent?
    public var lastPreferredRunDateOnScan: Date?
    public var lastPreferredRunDateOnOptOut: Date?
    public var submittedSuccessfullyDate: Date?
    public var extractedProfileRemovedDate: Date?
    public var extractedProfilesFromBroker = [ExtractedProfile]()
    public var childBrokers = [DataBroker]()
    public var lastParentBrokerWhereChildSitesWhereFetched: String?
    public var lastProfileQueryIdOnScanUpdatePreferredRunDate: Int64?
    public var brokerProfileQueryDataToReturn = [BrokerProfileQueryData]()
    public var dataBrokersToReturn = [DataBroker]()
    public var profile: DataBrokerProtectionProfile?
    public var attemptInformation: AttemptInformation?
    public var attemptCount: Int64 = 0
    public private(set) var scanEvents = [HistoryEvent]()
    public private(set) var optOutEvents = [HistoryEvent]()

    public var saveResult: Result<Void, Error> = .success(())

    public lazy var callsList: [Bool] = [
        wasSaveProfileCalled,
        wasFetchProfileCalled,
        wasDeleteProfileDataCalled,
        wasSaveOptOutOperationCalled,
        wasBrokerProfileQueryDataCalled,
        wasFetchAllDataBrokersCalled,
        wasFetchAllBrokerProfileQueryDataCalled,
        wasUpdatedPreferredRunDateForScanCalled,
        wasUpdatedPreferredRunDateForOptOutCalled,
        wasUpdateSubmittedSuccessfullyDateForOptOutCalled,
        wasUpdateSevenDaysConfirmationPixelFired,
        wasUpdateFourteenDaysConfirmationPixelFired,
        wasUpdateTwentyOneDaysConfirmationPixelFired,
        wasUpdateLastRunDateForScanCalled,
        wasUpdateLastRunDateForOptOutCalled,
        wasUpdateRemoveDateCalled,
        wasAddHistoryEventCalled,
        wasFetchLastHistoryEventCalled]

    public var wasDatabaseCalled: Bool {
        callsList.filter { $0 }.count > 0 // If one value is true. The database was called
    }

    public init() {}

    public func save(_ profile: DataBrokerProtectionProfile) throws {
        wasSaveProfileCalled = true
        switch saveResult {
        case .success:
            return
        case .failure(let error):
            throw error
        }
    }

    public func fetchProfile() -> DataBrokerProtectionProfile? {
        wasFetchProfileCalled = true
        return profile
    }

    public func setFetchedProfile(_ profile: DataBrokerProtectionProfile?) {
        self.profile = profile
    }

    public func deleteProfileData() {
        wasDeleteProfileDataCalled = true
    }

    public func saveOptOutJob(optOut: OptOutJobData, extractedProfile: ExtractedProfile) throws {
        wasSaveOptOutOperationCalled = true
    }

    public func brokerProfileQueryData(for brokerId: Int64, and profileQueryId: Int64) -> BrokerProfileQueryData? {
        wasBrokerProfileQueryDataCalled = true

        if !brokerProfileQueryDataToReturn.isEmpty {
            return brokerProfileQueryDataToReturn.first
        }

        if let lastHistoryEventToReturn = self.lastHistoryEventToReturn {
            let scanJobData = ScanJobData(brokerId: brokerId, profileQueryId: profileQueryId, historyEvents: [lastHistoryEventToReturn])

            return BrokerProfileQueryData(dataBroker: .mock, profileQuery: .mock, scanJobData: scanJobData)
        } else {
            return nil
        }
    }

    public func fetchAllBrokerProfileQueryData() throws -> [BrokerProfileQueryData] {
        wasFetchAllBrokerProfileQueryDataCalled = true

        if let fetchAllBrokerProfileQueryDataError {
            throw fetchAllBrokerProfileQueryDataError
        }

        return brokerProfileQueryDataToReturn
    }

    public func fetchAllDataBrokers() throws -> [DataBrokerProtectionCore.DataBroker] {
        wasFetchAllDataBrokersCalled = true

        return dataBrokersToReturn
    }

    public func updatePreferredRunDate(_ date: Date?, brokerId: Int64, profileQueryId: Int64) {
        lastPreferredRunDateOnScan = date
        lastProfileQueryIdOnScanUpdatePreferredRunDate = profileQueryId
        wasUpdatedPreferredRunDateForScanCalled = true
    }

    public func updatePreferredRunDate(_ date: Date?, brokerId: Int64, profileQueryId: Int64, extractedProfileId: Int64) {
        lastPreferredRunDateOnOptOut = date
        wasUpdatedPreferredRunDateForOptOutCalled = true
    }

    public func updateAttemptCount(_ count: Int64, brokerId: Int64, profileQueryId: Int64, extractedProfileId: Int64) throws {
        attemptCount = count
    }

    public func incrementAttemptCount(brokerId: Int64, profileQueryId: Int64, extractedProfileId: Int64) throws {
        attemptCount += 1
    }

    public func updateSubmittedSuccessfullyDate(_ date: Date?, forBrokerId brokerId: Int64, profileQueryId: Int64, extractedProfileId: Int64) throws {
        submittedSuccessfullyDate = date
        wasUpdateSubmittedSuccessfullyDateForOptOutCalled = true
    }

    public func updateSevenDaysConfirmationPixelFired(_ pixelFired: Bool, forBrokerId brokerId: Int64, profileQueryId: Int64, extractedProfileId: Int64) throws {
        wasUpdateSevenDaysConfirmationPixelFired = true
    }

    public func updateFourteenDaysConfirmationPixelFired(_ pixelFired: Bool, forBrokerId brokerId: Int64, profileQueryId: Int64, extractedProfileId: Int64) throws {
        wasUpdateFourteenDaysConfirmationPixelFired = true
    }

    public func updateTwentyOneDaysConfirmationPixelFired(_ pixelFired: Bool, forBrokerId brokerId: Int64, profileQueryId: Int64, extractedProfileId: Int64) throws {
        wasUpdateTwentyOneDaysConfirmationPixelFired = true
    }

    public func updateLastRunDate(_ date: Date?, brokerId: Int64, profileQueryId: Int64) {
        wasUpdateLastRunDateForScanCalled = true
    }

    public func updateLastRunDate(_ date: Date?, brokerId: Int64, profileQueryId: Int64, extractedProfileId: Int64) {
        wasUpdateLastRunDateForOptOutCalled = true
    }

    public func updateRemovedDate(_ date: Date?, on extractedProfileId: Int64) {
        extractedProfileRemovedDate = date
        wasUpdateRemoveDateCalled = true
    }

    public func add(_ historyEvent: HistoryEvent) {
        wasAddHistoryEventCalled = true
        if historyEvent.extractedProfileId != nil {
            optOutEvents.append(historyEvent)
        } else {
            scanEvents.append(historyEvent)
        }
    }

    public func fetchLastEvent(brokerId: Int64, profileQueryId: Int64) -> HistoryEvent? {
        wasFetchLastHistoryEventCalled = true
        if let event = brokerProfileQueryDataToReturn.first?.events.last {
            return event
        }
        return lastHistoryEventToReturn
    }

    public func fetchScanHistoryEvents(brokerId: Int64, profileQueryId: Int64) -> [HistoryEvent] {
        return scanEvents
    }

    public func fetchOptOutHistoryEvents(brokerId: Int64, profileQueryId: Int64, extractedProfileId: Int64) -> [HistoryEvent] {
        return optOutEvents
    }

    public func hasMatches() -> Bool {
        false
    }

    public func matchRemovedByUser(_ matchID: Int64) throws {

    }

    public func fetchExtractedProfiles(for brokerId: Int64) -> [ExtractedProfile] {
        return extractedProfilesFromBroker
    }

    public func fetchAllAttempts() throws -> [AttemptInformation] {
        [attemptInformation].compactMap { $0 }
    }

    public func fetchAttemptInformation(for extractedProfileId: Int64) -> AttemptInformation? {
        return attemptInformation
    }

    public func addAttempt(extractedProfileId: Int64, attemptUUID: UUID, dataBroker: String, lastStageDate: Date, startTime: Date) {
    }

    public func fetchChildBrokers(for parentBroker: String) -> [DataBroker] {
        lastParentBrokerWhereChildSitesWhereFetched = parentBroker
        return childBrokers
    }

    public func fetchExtractedProfile(with id: Int64) throws -> (brokerId: Int64, profileQueryId: Int64, profile: ExtractedProfile)? {
        nil
    }

    public func fetchFirstEligibleJobDate() throws -> Date? {
        return nil
    }

    public func saveProfileQuery(profileQuery: DataBrokerProtectionCore.ProfileQuery, profileId: Int64) throws -> Int64 {
        1
    }

    public func saveScanJob(brokerId: Int64, profileQueryId: Int64, lastRunDate: Date?, preferredRunDate: Date?) throws {
    }

    public func saveBroker(dataBroker: DataBroker) throws -> Int64 {
        1
    }

    public func clear() {
        wasSaveProfileCalled = false
        wasFetchProfileCalled = false
        wasSaveOptOutOperationCalled = false
        wasBrokerProfileQueryDataCalled = false
        wasFetchAllBrokerProfileQueryDataCalled = false
        wasFetchAllDataBrokersCalled = false
        wasUpdatedPreferredRunDateForScanCalled = false
        wasUpdatedPreferredRunDateForOptOutCalled = false
        wasUpdateLastRunDateForScanCalled = false
        wasUpdateLastRunDateForOptOutCalled = false
        wasUpdateRemoveDateCalled = false
        wasAddHistoryEventCalled = false
        wasFetchLastHistoryEventCalled = false
        lastHistoryEventToReturn = nil
        lastPreferredRunDateOnScan = nil
        lastPreferredRunDateOnOptOut = nil
        extractedProfileRemovedDate = nil
        extractedProfilesFromBroker.removeAll()
        childBrokers.removeAll()
        lastParentBrokerWhereChildSitesWhereFetched = nil
        lastProfileQueryIdOnScanUpdatePreferredRunDate = nil
        brokerProfileQueryDataToReturn.removeAll()
        dataBrokersToReturn.removeAll()
        profile = nil
        attemptInformation = nil
        scanEvents.removeAll()
        optOutEvents.removeAll()
    }
}

public final class MockAppVersion: AppVersionNumberProvider {

    public var versionNumber: String

    public init(versionNumber: String) {
        self.versionNumber = versionNumber
    }
}

public final class MockStageDurationCalculator: StageDurationCalculator {
    public var isImmediateOperation: Bool = false
    public var attemptId: UUID = UUID()
    public var tries = 1
    public var stage: Stage?

    public init() {}

    public func durationSinceLastStage() -> Double {
        return 0.0
    }

    public func durationSinceStartTime() -> Double {
        return 0.0
    }

    public func fireOptOutStart() {
    }

    public func fireOptOutEmailGenerate() {
    }

    public func fireOptOutCaptchaParse() {
    }

    public func fireOptOutCaptchaSend() {
    }

    public func fireOptOutCaptchaSolve() {
    }

    public func fireOptOutSubmit() {
    }

    public func fireOptOutEmailReceive() {
    }

    public func fireOptOutEmailConfirm() {
    }

    public func fireOptOutValidate() {
    }

    public func fireOptOutSubmitSuccess(tries: Int) {
    }

    public func fireOptOutFillForm() {
    }

    public func fireOptOutFailure(tries: Int) {
    }

    public func fireScanStarted() {
    }

    public func fireScanSuccess(matchesFound: Int) {
    }

    public func fireScanFailed() {
    }

    public func fireScanError(error: any Error) {
    }

    public func setStage(_ stage: Stage) {
        self.stage = stage
    }

    public func setEmailPattern(_ emailPattern: String?) {
    }

    public func setLastActionId(_ actionID: String) {
    }

    public func resetTries() {
        self.tries = 1
    }

    public func incrementTries() {
        self.tries += 1
    }

    func clear() {
        self.stage = nil
    }
}

public final class MockDataBrokerProtectionBackendServicePixels: DataBrokerProtectionBackendServicePixels {

    public init() { }

    public var fireEmptyAccessTokenWasCalled = false
    public var fireGenerateEmailHTTPErrorWasCalled = false
    public var statusCode: Int?

    public func fireGenerateEmailHTTPError(statusCode: Int) {
        fireGenerateEmailHTTPErrorWasCalled = true
        self.statusCode = statusCode
    }

    public func fireEmptyAccessToken(callSite: BackendServiceCallSite) {
        fireEmptyAccessTokenWasCalled = true
    }

    public func reset() {
        fireEmptyAccessTokenWasCalled = false
        fireGenerateEmailHTTPErrorWasCalled = false
        statusCode = nil
    }
}

public final class MockPixelHandler: EventMapping<DataBrokerProtectionSharedPixels> {

    public var lastFiredEvent: DataBrokerProtectionSharedPixels?
    public var lastPassedParameters: [String: String]?

    public init() {
        var mockMapping: Mapping! = nil

        super.init(mapping: { event, error, params, onComplete in
            // Call the closure after initialization
            mockMapping(event, error, params, onComplete)
        })

        // Now, set the real closure that captures self and stores parameters.
        mockMapping = { [weak self] (event, _, params, _) in
            // Capture the inputs when fire is called
            self?.lastFiredEvent = event
            self?.lastPassedParameters = params
        }
    }

    public func resetCapturedData() {
        lastFiredEvent = nil
        lastPassedParameters = nil
    }
}

public extension ProfileQuery {

    static var mock: ProfileQuery {
        .init(id: 1, firstName: "First", lastName: "Last", city: "City", state: "State", birthYear: 1980)
    }

    static var mockWithoutId: ProfileQuery {
        .init(firstName: "First", lastName: "Last", city: "City", state: "State", birthYear: 1980)
    }
}

public extension ScanJobData {

    static var mock: ScanJobData {
        .init(
            brokerId: 1,
            profileQueryId: 1,
            historyEvents: [HistoryEvent]()
        )
    }

    static func mockWith(historyEvents: [HistoryEvent]) -> ScanJobData {
        ScanJobData(brokerId: 1, profileQueryId: 1, historyEvents: historyEvents)
    }

    static func mock(withBrokerId brokerId: Int64) -> ScanJobData {
        .init(
            brokerId: brokerId,
            profileQueryId: 1,
            historyEvents: [HistoryEvent]()
        )
    }

    static func mock(historyEvents: [HistoryEvent], preferredRunDate: Date?) -> ScanJobData {
        .init(
            brokerId: 1,
            profileQueryId: 1,
            preferredRunDate: preferredRunDate,
            historyEvents: historyEvents
        )
    }
}

public extension OptOutJobData {
    static func mock(with extractedProfile: ExtractedProfile,
                     brokerId: Int64 = 1,
                     profileQueryId: Int64 = 1,
                     createdDate: Date = Date(),
                     preferredRunDate: Date? = nil,
                     historyEvents: [HistoryEvent] = [HistoryEvent]()) -> OptOutJobData {
        .init(brokerId: brokerId, profileQueryId: profileQueryId, createdDate: createdDate, preferredRunDate: preferredRunDate, historyEvents: historyEvents, attemptCount: 0, extractedProfile: extractedProfile)
    }

    static func mock(with createdDate: Date) -> OptOutJobData {
        .init(brokerId: 1, profileQueryId: 1, createdDate: createdDate, historyEvents: [], attemptCount: 0, submittedSuccessfullyDate: nil, extractedProfile: .mockWithoutRemovedDate)
    }

    static func mock(with extractedProfile: ExtractedProfile,
                     historyEvents: [HistoryEvent] = [HistoryEvent](),
                     createdDate: Date,
                     submittedSuccessfullyDate: Date?) -> OptOutJobData {
        .init(brokerId: 1, profileQueryId: 1, createdDate: createdDate, historyEvents: historyEvents, attemptCount: 0, submittedSuccessfullyDate: submittedSuccessfullyDate, extractedProfile: extractedProfile)
    }

    static func mock(with type: HistoryEvent.EventType,
                     submittedDate: Date?,
                     sevenDaysConfirmationPixelFired: Bool,
                     fourteenDaysConfirmationPixelFired: Bool,
                     twentyOneDaysConfirmationPixelFired: Bool) -> OptOutJobData {
        let extractedProfileId: Int64 = 1
        let brokerId: Int64 = 1
        let profileQueryId: Int64 = 11

        let historyEvent = HistoryEvent(extractedProfileId: extractedProfileId, brokerId: brokerId, profileQueryId: profileQueryId, type: .optOutRequested, date: submittedDate ?? Date())

        let extractedProfile = type == .optOutConfirmed ? ExtractedProfile.mockWithRemovedDate : ExtractedProfile.mockWithoutRemovedDate
        return OptOutJobData(brokerId: brokerId,
                             profileQueryId: profileQueryId,
                             createdDate: submittedDate ?? Date(),
                             historyEvents: [historyEvent],
                             attemptCount: 0,
                             submittedSuccessfullyDate: submittedDate,
                             extractedProfile: extractedProfile,
                             sevenDaysConfirmationPixelFired: sevenDaysConfirmationPixelFired,
                             fourteenDaysConfirmationPixelFired: fourteenDaysConfirmationPixelFired,
                             twentyOneDaysConfirmationPixelFired: twentyOneDaysConfirmationPixelFired)
    }
}

public final class MockBrokerProfileJobQueueManager: BrokerProfileJobQueueManaging {
    public var delegate: BrokerProfileJobQueueManagerDelegate?

    public var debugRunningStatusString: String { return "" }

    public var startImmediateScanOperationsIfPermittedCompletionError: DataBrokerProtectionJobsErrorCollection?
    public var startScheduledAllOperationsIfPermittedCompletionError: DataBrokerProtectionJobsErrorCollection?
    public var startScheduledScanOperationsIfPermittedCompletionError: DataBrokerProtectionJobsErrorCollection?

    public var startImmediateScanOperationsIfPermittedCalledCompletion: (() -> Void)?
    public var startScheduledAllOperationsIfPermittedCalledCompletion: (() -> Void)?
    public var startScheduledScanOperationsIfPermittedCalledCompletion: (() -> Void)?

    public init(jobQueue: BrokerProfileJobQueue, jobProvider: BrokerProfileJobProviding, mismatchCalculator: MismatchCalculator, pixelHandler: Common.EventMapping<DataBrokerProtectionSharedPixels>) {

    }

    public func startImmediateScanOperationsIfPermitted(showWebView: Bool, jobDependencies: BrokerProfileJobDependencyProviding, errorHandler: ((DataBrokerProtectionJobsErrorCollection?) -> Void)?, completion: (() -> Void)?) {
        errorHandler?(startImmediateScanOperationsIfPermittedCompletionError)
        completion?()
        startImmediateScanOperationsIfPermittedCalledCompletion?()
    }

    public func startScheduledAllOperationsIfPermitted(showWebView: Bool, jobDependencies: BrokerProfileJobDependencyProviding, errorHandler: ((DataBrokerProtectionJobsErrorCollection?) -> Void)?, completion: (() -> Void)?) {
        errorHandler?(startScheduledAllOperationsIfPermittedCompletionError)
        completion?()
        startScheduledAllOperationsIfPermittedCalledCompletion?()
    }

    public func startScheduledScanOperationsIfPermitted(showWebView: Bool, jobDependencies: BrokerProfileJobDependencyProviding, errorHandler: ((DataBrokerProtectionJobsErrorCollection?) -> Void)?, completion: (() -> Void)?) {
        errorHandler?(startScheduledScanOperationsIfPermittedCompletionError)
        completion?()
        startScheduledScanOperationsIfPermittedCalledCompletion?()
    }

    public func execute(_ command: DataBrokerProtectionQueueManagerDebugCommand) {
    }

    public func stop() {
    }
}

public final class MockBrokerProfileJobQueue: BrokerProfileJobQueue {
    public var maxConcurrentOperationCount = 1

    public var operations: [Operation] = []
    public var operationCount: Int {
        operations.count
    }

    public private(set) var didCallCancelCount = 0
    public private(set) var didCallAddCount = 0
    public private(set) var didCallAddBarrierBlockCount = 0

    private var barrierBlock: (@Sendable () -> Void)?

    public init() { }

    public func cancelAllOperations() {
        didCallCancelCount += 1
        self.operations.forEach { $0.cancel() }
    }

    public func addOperation(_ op: Operation) {
        didCallAddCount += 1
        self.operations.append(op)
    }

    public func addBarrierBlock1(_ barrier: @escaping @Sendable () -> Void) {
        didCallAddBarrierBlockCount += 1
        self.barrierBlock = barrier
    }

    public func completeAllOperations() {
        operations.forEach { $0.start() }
        operations.removeAll()
        barrierBlock?()
    }

    public func completeOperationsUpTo(index: Int) {
        guard index < operationCount else { return }

        (0..<index).forEach {
            operations[$0].start()
        }

        (0..<index).forEach {
            operations.remove(at: $0)
        }
    }
}

public final class MockBrokerProfileJob: BrokerProfileJob, @unchecked Sendable {

    private var shouldError = false
    private var _isExecuting = false
    private var _isFinished = false
    private var _isCancelled = false

    public convenience init(id: Int64,
                            jobType: JobType,
                            errorDelegate: BrokerProfileJobErrorDelegate,
                            shouldError: Bool = false) {

        self.init(dataBrokerID: id,
                  jobType: jobType,
                  showWebView: false,
                  errorDelegate: errorDelegate,
                  jobDependencies: MockBrokerProfileJobDependencies())

        self.shouldError = shouldError
    }

    public override func main() {
        if shouldError {
            errorDelegate?.dataBrokerOperationDidError(DataBrokerProtectionError.noActionFound, withBrokerName: nil, version: nil)
        }

        finish()
    }

    public override func cancel() {
        self._isCancelled = true
    }

    public override var isCancelled: Bool {
        _isCancelled
    }

    public override var isAsynchronous: Bool {
        return true
    }

    public override var isExecuting: Bool {
        return _isExecuting
    }

    public override var isFinished: Bool {
        return _isFinished
    }

    private func finish() {
        willChangeValue(forKey: #keyPath(isExecuting))
        willChangeValue(forKey: #keyPath(isFinished))

        _isExecuting = false
        _isFinished = true

        didChangeValue(forKey: #keyPath(isExecuting))
        didChangeValue(forKey: #keyPath(isFinished))
    }
}

public final class MockBrokerProfileJobErrorDelegate: BrokerProfileJobErrorDelegate {

    public var operationErrors: [Error] = []
    public var dataBrokerOperationDidErrorCalled = false

    public init() {}

    public func dataBrokerOperationDidError(_ error: any Error, withBrokerName brokerName: String?, version: String?) {
        dataBrokerOperationDidErrorCalled = true
        operationErrors.append(error)
    }
}

public final class MockOperationEventsHandler: EventMapping<JobEvent> {

    public var profileSavedFired = false
    public var firstScanCompletedFired = false
    public var firstScanCompletedAndMatchesFoundFired = false
    public var firstProfileRemovedFired = false
    public var allProfilesRemovedFired = false

    public init() {
        super.init { _, _, _, _ in
        }

        // A workaround to be able to reference self in the eventMapper
        self.eventMapper = { event, _, _, _ in
            self.handle(event: event)
        }
    }

    private func handle(event: JobEvent) {
        switch event {
        case .profileSaved:
            profileSavedFired = true
        case .firstScanCompleted:
            firstScanCompletedFired = true
        case .firstScanCompletedAndMatchesFound:
            firstScanCompletedAndMatchesFoundFired = true
        case .firstProfileRemoved:
            firstProfileRemovedFired = true
        case .allProfilesRemoved:
            allProfilesRemovedFired = true
        }
    }

    public func reset() {
        profileSavedFired = false
        firstScanCompletedFired = false
        firstScanCompletedAndMatchesFoundFired = false
        firstProfileRemovedFired = false
        allProfilesRemovedFired = false
    }
}

public final class MockBrokerProfileJobDependencies: BrokerProfileJobDependencyProviding {
    public var database: any DataBrokerProtectionRepository
    public var contentScopeProperties: ContentScopeProperties
    public var privacyConfig: any PrivacyConfigurationManaging
    public var executionConfig: BrokerJobExecutionConfig
    public var notificationCenter: NotificationCenter
    public var pixelHandler: EventMapping<DataBrokerProtectionSharedPixels>
    public var eventsHandler: EventMapping<JobEvent>
    public var dataBrokerProtectionSettings: DataBrokerProtectionSettings
    public var emailService: any EmailServiceProtocol
    public var captchaService: any CaptchaServiceProtocol
    public var vpnBypassService: (any VPNBypassFeatureProvider)?
    public var jobSortPredicate: BrokerJobDataComparators.Predicate = BrokerJobDataComparators.default

    public var mockScanRunner = MockScanSubJobWebRunner()
    public var mockOptOutRunner = MockOptOutSubJobWebRunner()

    public init() {
        self.database = MockDatabase()
        self.contentScopeProperties = ContentScopeProperties.mock
        self.privacyConfig = PrivacyConfigurationManagingMock()
        self.executionConfig = BrokerJobExecutionConfig()
        self.notificationCenter = .default
        self.pixelHandler = MockPixelHandler()
        self.eventsHandler = MockOperationEventsHandler()
        self.dataBrokerProtectionSettings = DataBrokerProtectionSettings(defaults: .standard)
        self.emailService = EmailServiceMock()
        self.captchaService = CaptchaServiceMock()
    }

    public func createScanRunner(profileQuery: BrokerProfileQueryData,
                                 stageDurationCalculator: any StageDurationCalculator,
                                 shouldRunNextStep: @escaping () -> Bool) -> any BrokerProfileScanSubJobWebRunning {
        return mockScanRunner
    }

    public func createOptOutRunner(profileQuery: BrokerProfileQueryData,
                                   stageDurationCalculator: any StageDurationCalculator,
                                   shouldRunNextStep: @escaping () -> Bool) -> any BrokerProfileOptOutSubJobWebRunning {
        return mockOptOutRunner
    }

}

public final class MockDataBrokerOperationsCreator: BrokerProfileJobProviding {

    public var operationCollections: [BrokerProfileJob] = []
    public var shouldError = false
    public var priorityDate: Date?
    public var createdType: JobType = .manualScan

    public init(operationCollections: [BrokerProfileJob] = []) {
        self.operationCollections = operationCollections
    }

    public func createJobs(with jobType: JobType,
                           withPriorityDate priorityDate: Date?,
                           showWebView: Bool,
                           errorDelegate: BrokerProfileJobErrorDelegate,
                           jobDependencies: BrokerProfileJobDependencyProviding) throws -> [BrokerProfileJob] {
        guard !shouldError else { throw DataBrokerProtectionError.unknown("")}
        self.createdType = jobType
        self.priorityDate = priorityDate
        return operationCollections
    }
}

public final class MockMismatchCalculator: MismatchCalculator {

    private(set) var didCallCalculateMismatches = false

    public init(database: any DataBrokerProtectionRepository, pixelHandler: Common.EventMapping<DataBrokerProtectionSharedPixels>) { }

    public func calculateMismatches() {
        didCallCalculateMismatches = true
    }
}

public final class MockBrokerJSONService: BrokerJSONServiceProvider {
    public var vault: any DataBrokerProtectionCore.DataBrokerProtectionSecureVault

    public private(set) var didCallUpdateBrokers = false
    public private(set) var didCallCheckForUpdates = false

    public init() {
        self.vault = try! DataBrokerProtectionSecureVaultMock(providers:
                                                                SecureStorageProviders(
                                                                    crypto: EmptySecureStorageCryptoProviderMock(),
                                                                    database: SecureStorageDatabaseProviderMock(),
                                                                    keystore: EmptySecureStorageKeyStoreProviderMock()))
    }

    public func checkForUpdates(skipsLimiter: Bool) async throws {
        didCallCheckForUpdates = true
    }

    public func checkForUpdates() async throws {
        didCallCheckForUpdates = true
    }

    public func bundledBrokers() throws -> [DataBroker]? {
        nil
    }

    public func updateBrokers() {
        didCallUpdateBrokers = true
    }
}

public struct MockLocalBrokerJSONService: LocalBrokerJSONServiceProvider {
    public init() {}

    public func bundledBrokers() throws -> [DataBroker]? {
        []
    }

    public func checkForUpdates() async throws {
    }
}

public final class MockFileManager: FileManager {
    public var hasUnzippedContent = false

    let fileNames = ["valid-broker", "invalid-broker-with-unsupported-type", "invalid-broker-with-unsupported-action"]
    lazy var fileURLs = fileNames.compactMap { Bundle.module.url(forResource: $0, withExtension: "json", subdirectory: "Resources") }

    public override func fileExists(atPath path: String, isDirectory: UnsafeMutablePointer<ObjCBool>?) -> Bool {
        hasUnzippedContent
    }

    public override func contentsOfDirectory(at url: URL, includingPropertiesForKeys keys: [URLResourceKey]?, options mask: FileManager.DirectoryEnumerationOptions = []) throws -> [URL] {
        hasUnzippedContent ? fileURLs : []
    }

    public override func removeItem(at URL: URL) throws {
        hasUnzippedContent = false
    }

    public override func unzipArchive(at sourceURL: URL, to destinationURL: URL) throws {
        hasUnzippedContent = true
    }
}

public final class MockAuthenticationManager: DataBrokerProtectionAuthenticationManaging {

    public init() { }

    public var isUserAuthenticatedValue = false
    public var isUserEligibleForFreeTrialValue = false
    public var accessTokenValue: String? = "fake token"
    public var shouldAskForInviteCodeValue = false
    public var redeemCodeCalled = false
    public var authHeaderValue: String? = "fake auth header"
    public var hasValidEntitlementValue = false
    public var shouldThrowEntitlementError = false

    public var isUserAuthenticated: Bool { isUserAuthenticatedValue }

    public var isUserEligibleForFreeTrial: Bool { isUserEligibleForFreeTrialValue }

    public func accessToken() async -> String? { accessTokenValue }

    public func hasValidEntitlement() async throws -> Bool {
        if shouldThrowEntitlementError {
            throw NSError(domain: "duck.com", code: 0, userInfo: [NSLocalizedDescriptionKey: "Error"])
        }
        return hasValidEntitlementValue
    }

    func shouldAskForInviteCode() -> Bool { shouldAskForInviteCodeValue }

    func redeem(inviteCode: String) async throws {
        redeemCodeCalled = true
    }

    public func getAuthHeader() -> String? { authHeaderValue }

    public func reset() {
        isUserAuthenticatedValue = false
        accessTokenValue = "fake token"
        shouldAskForInviteCodeValue = false
        redeemCodeCalled = false
        authHeaderValue = "fake auth header"
        hasValidEntitlementValue = false
        shouldThrowEntitlementError = false
    }
}

public final class MockDBPKeychainService: KeychainService {

    public enum Mode {
        case nothingFound
        case migratedDataFound
        case legacyDataFound
        case readError
        case updateError

        public var statusCode: Int32? {
            switch self {
            case .readError:
                return -25295
            case .updateError:
                return -25299
            default:
                return nil
            }
        }
    }

    public var latestItemMatchingQuery: [String: Any] = [:]
    public var latestUpdateQuery: [String: Any] = [:]
    public var latestAddQuery: [String: Any] = [:]
    public var latestUpdateAttributes: [String: Any] = [:]
    public var addCallCount = 0
    public var itemMatchingCallCount = 0
    public var updateCallCount = 0

    public var mode: Mode = .nothingFound

    public init() {}

    public func itemMatching(_ query: [String: Any], _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        itemMatchingCallCount += 1
        latestItemMatchingQuery = query

        func setResult() {
            let originalString = "Mock Keychain data!"
            let data = originalString.data(using: .utf8)!
            let encodedString = data.base64EncodedString()
            let mockResult = encodedString.data(using: .utf8)! as CFData

            if let result = result {
                result.pointee = mockResult
            }
        }

        switch mode {
        case .nothingFound:
            return errSecItemNotFound
        case .migratedDataFound:
            setResult()
            return errSecSuccess
        case .legacyDataFound, .updateError:
            if itemMatchingCallCount == 2 {
                setResult()
                return errSecSuccess
            } else {
                return errSecItemNotFound
            }
        case .readError:
            return errSecInvalidKeychain
        }
    }

    public func add(_ query: [String: Any], _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        latestAddQuery = query
        addCallCount += 1
        return errSecSuccess
    }

    public func update(_ query: [String: Any], _ attributesToUpdate: [String: Any]) -> OSStatus {
        guard mode != .updateError else { return errSecDuplicateItem }
        updateCallCount += 1
        latestUpdateQuery = query
        latestUpdateAttributes = attributesToUpdate
        return errSecSuccess
    }
}

public struct MockGroupNameProvider: GroupNameProviding {
    public var appGroupName: String {
        return "mockGroup"
    }

    public init() {}
}

extension SecureStorageError: @retroactive Equatable {
    public static func == (lhs: SecureStorageError, rhs: SecureStorageError) -> Bool {
        switch (lhs, rhs) {
        case (.initFailed(let cause1), .initFailed(let cause2)):
            return cause1.localizedDescription == cause2.localizedDescription
        case (.authError(let cause1), .authError(let cause2)):
            return cause1.localizedDescription == cause2.localizedDescription
        case (.failedToOpenDatabase(let cause1), .failedToOpenDatabase(let cause2)):
            return cause1.localizedDescription == cause2.localizedDescription
        case (.databaseError(let cause1), .databaseError(let cause2)):
            return cause1.localizedDescription == cause2.localizedDescription
        case (.keystoreError(let status1), .keystoreError(let status2)):
            return status1 == status2
        case (.secError(let status1), .secError(let status2)):
            return status1 == status2
        case (.keystoreReadError(let status1), .keystoreReadError(let status2)):
            return status1 == status2
        case (.keystoreUpdateError(let status1), .keystoreUpdateError(let status2)):
            return status1 == status2
        case (.authRequired, .authRequired), (.invalidPassword, .invalidPassword),
            (.noL1Key, .noL1Key), (.noL2Key, .noL2Key), (.duplicateRecord, .duplicateRecord),
            (.generalCryptoError, .generalCryptoError), (.encodingFailed, .encodingFailed):
            return true
        default:
            return false
        }
    }
}

public final class MockDataBrokerProtectionStatsPixelsRepository: DataBrokerProtectionStatsPixelsRepository {

    public var wasMarkStatsWeeklyPixelDateCalled: Bool = false
    public var wasMarkStatsMonthlyPixelDateCalled: Bool = false
    public var latestStatsWeeklyPixelDate: Date?
    public var latestStatsMonthlyPixelDate: Date?
    public var didSetCustomStatsPixelsLastSentTimestamp = false
    public var didGetCustomStatsPixelsLastSentTimestamp = false
    public var _customStatsPixelsLastSentTimestamp: Date?

    public var customStatsPixelsLastSentTimestamp: Date? {
        get {
            defer { didGetCustomStatsPixelsLastSentTimestamp = true }
            return _customStatsPixelsLastSentTimestamp
        } set {
            didSetCustomStatsPixelsLastSentTimestamp = true
            _customStatsPixelsLastSentTimestamp = newValue
        }
    }

    public init() {}

    public func markStatsWeeklyPixelDate() {
        wasMarkStatsWeeklyPixelDateCalled = true
    }

    public func markStatsMonthlyPixelDate() {
        wasMarkStatsMonthlyPixelDateCalled = true
    }

    public func getLatestStatsWeeklyPixelDate() -> Date? {
        return latestStatsWeeklyPixelDate
    }

    public func getLatestStatsMonthlyPixelDate() -> Date? {
        return latestStatsMonthlyPixelDate
    }

    func clear() {
        wasMarkStatsWeeklyPixelDateCalled = false
        wasMarkStatsMonthlyPixelDateCalled = false
        latestStatsWeeklyPixelDate = nil
        latestStatsMonthlyPixelDate = nil
        didSetCustomStatsPixelsLastSentTimestamp = false
        customStatsPixelsLastSentTimestamp = nil

    }
}

public final class MockDataBrokerProtectionCustomOptOutStatsProvider: DataBrokerProtectionCustomOptOutStatsProvider {

    var customStatsWasCalled = false
    var customStatsToReturn = CustomOptOutStats(customIndividualDataBrokerStat: [], customAggregateBrokersStat: CustomAggregateBrokersStat(optoutSubmitSuccessRate: 0))

    public func customOptOutStats(startDate: Date?, endDate: Date, andQueryData queryData: [BrokerProfileQueryData]) -> CustomOptOutStats {
        customStatsWasCalled = true
        return customStatsToReturn
    }
}

public final class MockActionsHandler: ActionsHandler {

    public var didCallNextAction = false

    public init() {
        super.init(step: Step(type: .scan, actions: []))
    }

    public override func nextAction() -> (any Action)? {
        didCallNextAction = true
        return nil
    }
}

private extension String {
    static func random(length: Int) -> String {
        let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<length).map { _ in characters.randomElement()! })
    }
}

private extension Int {
    static func randomBirthdate() -> Int {
        Int.random(in: 1960...2000)
    }
}

public extension Int64 {
    static func randomValues(ofLength length: Int = 20, start: Int64 = 1001, end: Int64 = 2000) -> [Int64] {
        [0..<length].map { _ in
            Int64.random(in: start..<end)
        }
    }
}

private extension Data {
    static func randomStringData(length: Int) -> Data {
        String.random(length: length).data(using: .utf8)!
    }

    static func randomBirthdateData() -> Data {
        String(Int.randomBirthdate()).data(using: .utf8)!
    }

    static func randomEventData(length: Int) -> Data {
            return .randomStringData(length: length)
        }
}

extension Date {
    static func random() -> Date {
        let currentTime = Date().timeIntervalSince1970
        let randomTimeInterval = TimeInterval.random(in: 0..<currentTime)
        return Date(timeIntervalSince1970: randomTimeInterval)
    }
}

public extension ProfileQueryDB {
    static func random(withProfileIds profileIds: [Int64]) -> [ProfileQueryDB] {
        profileIds.map {
            ProfileQueryDB(id: nil, profileId: $0,
                                         first: .randomStringData(length: 4),
                                         last: .randomStringData(length: 4),
                                         middle: nil,
                                         suffix: nil,
                                         city: .randomStringData(length: 4),
                                         state: .randomStringData(length: 4), street: .randomStringData(length: 4),
                                         zipCode: nil,
                                         phone: nil,
                                         birthYear: Data.randomBirthdateData(),
                                         deprecated: Bool.random())
        }
    }
}

public extension BrokerDB {
    static func random(count: Int) -> [BrokerDB] {
        [0..<count].map {
            BrokerDB(id: nil, name: .random(length: 4),
                     json: try! JSONSerialization.data(withJSONObject: [:], options: []),
                     version: "\($0).\($0).\($0)",
                     url: "www.testbroker.com",
                     eTag: "")
        }
    }
}

public extension ScanHistoryEventDB {
    static func random(withBrokerIds brokerIds: [Int64], profileQueryIds: [Int64]) -> [ScanHistoryEventDB] {
        brokerIds.flatMap { brokerId in
            profileQueryIds.map { profileQueryId in
                ScanHistoryEventDB(
                    brokerId: brokerId,
                    profileQueryId: profileQueryId,
                    event: .randomEventData(length: 8),
                    timestamp: .random()
                )
            }
        }
    }
}

public extension OptOutHistoryEventDB {
    static func random(withBrokerIds brokerIds: [Int64], profileQueryIds: [Int64], extractedProfileIds: [Int64]) -> [OptOutHistoryEventDB] {
        brokerIds.flatMap { brokerId in
            profileQueryIds.flatMap { profileQueryId in
                extractedProfileIds.map { extractedProfileId in
                    OptOutHistoryEventDB(
                        brokerId: brokerId,
                        profileQueryId: profileQueryId,
                        extractedProfileId: extractedProfileId,
                        event: .randomEventData(length: 8),
                        timestamp: .random()
                    )
                }
            }
        }
    }
}

public extension ExtractedProfileDB {
    static func random(withBrokerIds brokerIds: [Int64], profileQueryIds: [Int64]) -> [ExtractedProfileDB] {
        brokerIds.flatMap { brokerId in
            profileQueryIds.map { profileQueryId in
                ExtractedProfileDB(
                    id: nil,
                    brokerId: brokerId,
                    profileQueryId: profileQueryId,
                    profile: .randomEventData(length: 50),
                    removedDate: Bool.random() ? .random() : nil
                )
            }
        }
    }
}

public struct MockMigrationsProvider: DataBrokerProtectionDatabaseMigrationsProvider {
    public static var didCallV2Migrations = false
    public static var didCallV3Migrations = false
    public static var didCallV4Migrations = false
    public static var didCallV5Migrations = false
    public static var didCallV6Migrations = false

    public static var v2Migrations: (inout GRDB.DatabaseMigrator) throws -> Void {
        didCallV2Migrations = true
        return { _ in }
    }

    public static var v3Migrations: (inout GRDB.DatabaseMigrator) throws -> Void {
        didCallV3Migrations = true
        return { _ in }
    }

    public static var v4Migrations: (inout GRDB.DatabaseMigrator) throws -> Void {
        didCallV4Migrations = true
        return { _ in }
    }

    public static var v5Migrations: (inout GRDB.DatabaseMigrator) throws -> Void {
        didCallV5Migrations = true
        return { _ in }
    }

    public static var v6Migrations: (inout GRDB.DatabaseMigrator) throws -> Void {
        didCallV6Migrations = true
        return { _ in }
    }
}

public final class MockScanSubJobWebRunner: BrokerProfileScanSubJobWebRunning {
    public var shouldScanThrow = false
    public var scanResults = [ExtractedProfile]()
    public var wasScanCalled = false

    public init() { }

    public func scan(_ profileQuery: BrokerProfileQueryData,
                     showWebView: Bool,
                     shouldRunNextStep: @escaping () -> Bool) async throws -> [ExtractedProfile] {
        wasScanCalled = true

        if shouldScanThrow {
            throw DataBrokerProtectionError.unknown("Test error")
        } else {
            return scanResults
        }
    }

    public func clear() {
        shouldScanThrow = false
        scanResults.removeAll()
        wasScanCalled = false
    }
}

public final class MockOptOutSubJobWebRunner: BrokerProfileOptOutSubJobWebRunning {
    public var shouldOptOutThrow = false
    public var wasOptOutCalled = false

    public init() { }

    public func optOut(profileQuery: BrokerProfileQueryData,
                       extractedProfile: ExtractedProfile,
                       showWebView: Bool,
                       shouldRunNextStep: @escaping () -> Bool) async throws {
        wasOptOutCalled = true

        if shouldOptOutThrow {
            throw DataBrokerProtectionError.unknown("Test error")
        }
    }

    public func clear() {
        shouldOptOutThrow = false
        wasOptOutCalled = false
    }
}

public extension OptOutJobData {

    static func mock(with extractedProfile: ExtractedProfile) -> OptOutJobData {
        .init(brokerId: 1, profileQueryId: 1, createdDate: Date(), historyEvents: [HistoryEvent](), attemptCount: 0, extractedProfile: extractedProfile)
    }

    static func mock(attemptCount: Int64, preferredRunDate: Date? = nil) -> OptOutJobData {
        .init(
            brokerId: 1,
            profileQueryId: 1,
            createdDate: Date(),
            preferredRunDate: preferredRunDate,
            historyEvents: [],
            attemptCount: attemptCount,
            extractedProfile: .mockWithoutRemovedDate
        )
    }
}

public extension DataBroker {

    static var mock: DataBroker {
        DataBroker(
            id: 1,
            name: "Test broker",
            url: "testbroker.com",
            steps: [
                Step(type: .scan, actions: [Action]()),
                Step(type: .optOut, actions: [Action]())
            ],
            version: "1.0",
            schedulingConfig: DataBrokerScheduleConfig(
                retryError: 0,
                confirmOptOutScan: 0,
                maintenanceScan: 0,
                maxAttempts: -1
            ),
            optOutUrl: "",
            eTag: ""
        )
    }

    static var mockWithParentOptOut: DataBroker {
        DataBroker(
            id: 1,
            name: "Test broker",
            url: "testbroker.com",
            steps: [
                Step(type: .scan, actions: [Action]()),
                Step(type: .optOut, actions: [Action](), optOutType: .parentSiteOptOut)
            ],
            version: "1.0",
            schedulingConfig: DataBrokerScheduleConfig(
                retryError: 0,
                confirmOptOutScan: 0,
                maintenanceScan: 0,
                maxAttempts: -1
            ),
            parent: "some",
            optOutUrl: "",
            eTag: ""
        )
    }

    static var mockWithoutId: DataBroker {
        DataBroker(
            name: "Test broker",
            url: "testbroker.com",
            steps: [Step](),
            version: "1.0",
            schedulingConfig: DataBrokerScheduleConfig(
                retryError: 0,
                confirmOptOutScan: 0,
                maintenanceScan: 0,
                maxAttempts: -1
            ),
            optOutUrl: "",
            eTag: ""
        )
    }

    static func mockWithDefaults(id: Int64? = 1,
                                 name: String = "TestBroker",
                                 url: String = "testbroker.com",
                                 steps: [Step] = [],
                                 version: String = "1.0",
                                 schedulingConfig: DataBrokerScheduleConfig = DataBrokerScheduleConfig(
                                    retryError: 0,
                                    confirmOptOutScan: 0,
                                    maintenanceScan: 0,
                                    maxAttempts: -1),
                                 parent: String? = nil,
                                 mirrorSites: [MirrorSite] = [MirrorSite](),
                                 optOutUrl: String = "testbroker.com/optout",
                                 eTag: String = "") -> DataBroker {
        return DataBroker(id: id, name: name, url: url, steps: steps, version: version, schedulingConfig: schedulingConfig, parent: parent, mirrorSites: mirrorSites, optOutUrl: optOutUrl, eTag: eTag)
    }

    static func mock(withId id: Int64) -> DataBroker {
        DataBroker(
            id: id,
            name: "Test broker",
            url: "testbroker.com",
            steps: [Step](),
            version: "1.0",
            schedulingConfig: DataBrokerScheduleConfig(
                retryError: 0,
                confirmOptOutScan: 0,
                maintenanceScan: 0,
                maxAttempts: -1
            ),
            optOutUrl: "",
            eTag: ""
        )
    }

    static func mockWithURL(_ url: String) -> DataBroker {
        .init(name: "Test",
              url: url,
              steps: [Step](),
              version: "1.0",
              schedulingConfig: DataBrokerScheduleConfig(
                retryError: 0,
                confirmOptOutScan: 0,
                maintenanceScan: 0,
                maxAttempts: -1
              ),
              optOutUrl: "",
              eTag: ""
        )
    }

    static func mockWith(mirroSites: [MirrorSite]) -> DataBroker {
        DataBroker(
            id: 1,
            name: "Test broker",
            url: "testbroker.com",
            steps: [
                Step(type: .scan, actions: [Action]()),
                Step(type: .optOut, actions: [Action]())
            ],
            version: "1.0",
            schedulingConfig: DataBrokerScheduleConfig(
                retryError: 0,
                confirmOptOutScan: 0,
                maintenanceScan: 0,
                maxAttempts: -1
            ),
            mirrorSites: mirroSites,
            optOutUrl: "",
            eTag: ""
        )
    }
}

public extension ExtractedProfile {

    static var mockWithRemovedDate: ExtractedProfile {
        ExtractedProfile(id: 1, name: "Some name", profileUrl: "someURL", removedDate: Date(), identifier: "someURL")
    }

    static var mockWithoutRemovedDate: ExtractedProfile {
        ExtractedProfile(id: 1, name: "Some name", profileUrl: "someURL", identifier: "someURL")
    }

    static var mockWithoutId: ExtractedProfile {
        ExtractedProfile(name: "Some name", profileUrl: "someOtherURL", identifier: "someOtherURL")
    }

    static func mockWithRemoveDate(_ date: Date) -> ExtractedProfile {
        ExtractedProfile(id: 1, name: "Some name", profileUrl: "someURL", removedDate: date, identifier: "someURL")
    }

    static func mockWithName(_ name: String, alternativeNames: [String]? = nil, age: String, addresses: [AddressCityState], relatives: [String]? = nil) -> ExtractedProfile {
        ExtractedProfile(id: 1, name: name, alternativeNames: [], addressFull: nil, addresses: addresses, phoneNumbers: nil, relatives: nil, profileUrl: "someUrl", age: age, identifier: "someUrl")
    }
}

public extension AttemptInformation {

    static var mock: AttemptInformation {
        AttemptInformation(extractedProfileId: 1,
                           dataBroker: "broker",
                           attemptId: UUID().uuidString,
                           lastStageDate: Date(),
                           startDate: Date())
    }
}

// swiftlint:enable force_try
// swiftlint:enable identifier_name
// swiftlint:enable large_tuple

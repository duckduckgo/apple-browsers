//
//  DBPEndToEndTests.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import LoginItems
import PixelKitTestingUtilities
import XCTest

@testable import DataBrokerProtection_macOS
@testable import DataBrokerProtectionCore
@testable import DuckDuckGo_Privacy_Browser
@testable import PixelKit

// swiftlint:disable force_try

final class DBPEndToEndTests: XCTestCase {

    var loginItemsManager: LoginItemsManager!
    var pirProtectionManager: DataBrokerProtectionManager! = DataBrokerProtectionManager.shared
    var communicationLayer: DBPUICommunicationLayer!
    var communicationDelegate: DBPUICommunicationDelegate!
    var viewModel: DBPUIViewModel!
    var testUserDefault: UserDefaults! = UserDefaults(suiteName: #function)

    override func setUpWithError() throws {
        continueAfterFailure = false

        loginItemsManager = LoginItemsManager()
        loginItemsManager.disableLoginItems([LoginItem.dbpBackgroundAgent])

        communicationLayer = DBPUICommunicationLayer(webURLSettings: DataBrokerProtectionWebUIURLSettings(UserDefaults.standard),
                                                     privacyConfig: PrivacyConfigurationManagingMock())
        communicationLayer.delegate = pirProtectionManager.dataManager!.communicator

        communicationDelegate = pirProtectionManager.dataManager!.communicator

        viewModel = DBPUIViewModel(dataManager: pirProtectionManager.dataManager, agentInterface: pirProtectionManager.loginItemInterface, webUISettings: DataBrokerProtectionWebUIURLSettings(UserDefaults.standard), pixelHandler: DataBrokerProtectionSharedPixelsHandler(pixelKit: PixelKit.shared!, platform: .macOS))

        pirProtectionManager.dataManager!.communicator.scanDelegate = viewModel

        let database = pirProtectionManager.dataManager!.database
        try database.deleteProfileData()
    }

    override func tearDown() async throws {
        try pirProtectionManager.dataManager!.database.deleteProfileData()
        loginItemsManager.disableLoginItems([LoginItem.dbpBackgroundAgent])

        loginItemsManager = nil
        pirProtectionManager = nil
        communicationLayer = nil
        communicationDelegate = nil
        viewModel = nil
        testUserDefault = nil
    }

    /*
     Tests the entire PIR process with both removed and non-removed brokers, broken down into 9 steps.
     Kicks the process off by simulating a save profile message from the FE
     From there it performs a series of various introspections to check each step
     E.g. checking correct pixels are fired, checking operation statuses and events in the DB etc.
     Additionally verifies that removed brokers are filtered out at each stage

     ⚠️  IMPORTANT: This test has EXPLICIT expectations for exactly 2 brokers:
         - 1 non-removed broker: "DDG Fake Broker" (fakebroker.com.json)
         - 1 removed broker: "DDG Fake Removed Broker" (fakeremovedbroker.com.json)
         
         If you add/remove fake brokers, you MUST update the count assertions throughout
         this test to reflect the new expected numbers. This is intentional to ensure
         changes don't go unnoticed and removed broker filtering is properly verified.

     It checks more than just the headline (e.g. step 1 checks we save a profile but
     also checks the broker profile queries are created correctly and that the login item
     is running). This is mostly to make them easy to debug if they fail.

     The steps:
     1/ We save a profile and verify removed brokers are loaded but filtered
     2/ We scan brokers (only non-removed ones)
     3/ We find and save extracted profiles (only from non-removed brokers)
     4/ We create opt out jobs (only for non-removed brokers)
     5/ We run those opt out jobs (only for non-removed brokers)
     6/ The BE service receives the email
     7/ The app polls the backend service for the link
     8/ We visit the confirmation link
     9/ We confirm the opt out through a scan (only for non-removed brokers)

     Checking steps 6-8 are currently commented out since the fake broker doesn't
     support sending emails at the moment

     It avoids using XCTAssert etc in place of expectations (with helper methods)
     so when they fail there are more useful error messages in the log.
     When we adopt Swift 6, this can likely be replaced with the new testing macros
     */
    func testWhenProfileIsSaved_ThenEachStepHappensInSequence() async throws {
        // Given

        // Local state set up
        let dataManager = pirProtectionManager.dataManager
        let database = dataManager!.database
        let communicator = pirProtectionManager.dataManager!.communicator
        try database.deleteProfileData()
        XCTAssert(try database.fetchAllBrokerProfileQueryData(shouldFilterRemovedBrokers: false).isEmpty)

        // Fake broker set up
        await deleteAllProfilesOnFakeBroker()

        let mockUserProfile = mockFakeBrokerUserProfile()
        let returnedUserProfile = await createProfileOnFakeBroker(mockUserProfile)
        XCTAssertEqual(mockUserProfile.firstName, returnedUserProfile.firstName)

        // When
        /*
         1/ We save a profile
         */
        communicator.profile = mockProfile
        Task { @MainActor in
            _ = try await communicationLayer.saveProfile(params: [], original: WKScriptMessage())
        }

        // Then
        let profileSavedExpectation = expectation(description: "Profile saved in DB")
        let profileQueriesCreatedExpectation = expectation(description: "Profile queries created")

        await awaitFulfillment(of: profileSavedExpectation,
                               withTimeout: 3,
                               whenCondition: {
            autoreleasepool { // All autoreleasepool uses have been added as part of https://app.asana.com/0/1193060753475688/1209661386167901 in order to bring down the memory usage from 20Gb+ to 60-70Mb
                try! database.fetchProfile() != nil
            }
        })
        await awaitFulfillment(of: profileQueriesCreatedExpectation,
                               withTimeout: 3,
                               whenCondition: {
            autoreleasepool {
                try! database.fetchAllBrokerProfileQueryData(shouldFilterRemovedBrokers: false).count > 0
            }
        })

        // Also check that we made the broker profile queries correctly and that removed brokers are filtered
        let allQueries = try! database.fetchAllBrokerProfileQueryData(shouldFilterRemovedBrokers: false)
        let filteredQueries = try! database.fetchAllBrokerProfileQueryData(shouldFilterRemovedBrokers: true)
        let allBrokers = allQueries.compactMap { $0.dataBroker }
        let nonRemovedBrokers = allBrokers.filter { $0.removedAt == nil }
        let removedBrokers = allBrokers.filter { $0.removedAt != nil }

        // EXPLICIT BROKER COUNT EXPECTATIONS - UPDATE THESE WHEN ADDING NEW BROKERS
        assertCondition(withExpectationDescription: "Should load exactly 2 total brokers (1 non-removed + 1 removed)",
                        condition: { allBrokers.count == 2 })
        assertCondition(withExpectationDescription: "Should have exactly 1 non-removed broker",
                        condition: { nonRemovedBrokers.count == 1 })
        assertCondition(withExpectationDescription: "Should have exactly 1 removed broker",
                        condition: { removedBrokers.count == 1 })

        // EXPLICIT BROKER NAME EXPECTATIONS - UPDATE THESE WHEN ADDING NEW BROKERS
        assertCondition(withExpectationDescription: "Non-removed broker should be the DDG Fake Broker",
                        condition: { nonRemovedBrokers.first?.name == "DDG Fake Broker" })
        assertCondition(withExpectationDescription: "Removed broker should be DDG Fake Removed Broker",
                        condition: { removedBrokers.first?.name == "DDG Fake Removed Broker" })

        // FILTERING BEHAVIOR VERIFICATION
        assertCondition(withExpectationDescription: "Filtered queries should only contain non-removed brokers",
                        condition: { filteredQueries.allSatisfy { $0.dataBroker.removedAt == nil } })
        assertCondition(withExpectationDescription: "Filtered queries should contain exactly 1 broker (non-removed only)",
                        condition: { filteredQueries.count == 1 })
        assertCondition(withExpectationDescription: "Unfiltered queries should contain exactly 2 brokers (non-removed + removed)",
                        condition: { allQueries.count == 2 })

        print("Successfully detected 1 non-removed broker and 1 removed broker with proper filtering")

        // At this stage the login item should be running
        assertCondition(withExpectationDescription: "Login item enabled after profile save",
                        condition: { loginItemsManager.isAnyEnabled([.dbpBackgroundAgent]) })

        // This needs to be await since it takes time to start the login item
        let loginItemRunningExpectation = expectation(description: "Login item running after profile save")
        await awaitFulfillment(of: loginItemRunningExpectation,
                               withTimeout: 10,
                               whenCondition: {
            LoginItem.dbpBackgroundAgent.isRunning
        })

        print("Stage 1 passed: We save a profile")

        /*
        2/ We scan brokers
        */
        let schedulerStartsExpectation = expectation(description: "Scheduler starts")

        await awaitFulfillment(of: schedulerStartsExpectation,
                               withTimeout: 100,
                               whenCondition: {
            try! self.pirProtectionManager.dataManager!.prepareBrokerProfileQueryDataCache()
            return await self.communicationDelegate.getBackgroundAgentMetadata().lastStartedSchedulerOperationTimestamp != nil
        })

        let metaData = await communicationDelegate.getBackgroundAgentMetadata()
        assertCondition(withExpectationDescription: "Last operation broker URL is not nil",
                        condition: { metaData.lastStartedSchedulerOperationBrokerUrl != nil })

        // Verify only non-removed broker is being scanned (should be "fakebroker.com", not "fakeremovedbroker.com")
        let nonRemovedBrokerUrl = "fakebroker.com"
        assertCondition(withExpectationDescription: "Scheduler should only process the non-removed broker (fakebroker.com)",
                        condition: { metaData.lastStartedSchedulerOperationBrokerUrl?.contains(nonRemovedBrokerUrl) == true })
        assertCondition(withExpectationDescription: "Scheduler should NOT process the removed broker (fakeremovedbroker.com)",
                        condition: { !(metaData.lastStartedSchedulerOperationBrokerUrl?.contains("fakeremovedbroker.com") == true) })

        print("Stage 2 passed: We scan brokers (only non-removed ones)")

        /*
        3/ We find and save extracted profiles
        */
        let extractedProfilesFoundExpectation = expectation(description: "Extracted profiles found and saved in DB")

        await awaitFulfillment(of: extractedProfilesFoundExpectation,
                               withTimeout: 60,
                               whenCondition: {
            autoreleasepool {
                let queries = try! database.fetchAllBrokerProfileQueryData(shouldFilterRemovedBrokers: true) // Only check non-removed brokers
                let brokerIDs = queries.compactMap { $0.dataBroker.id }
                let extractedProfiles = brokerIDs.flatMap { try! database.fetchExtractedProfiles(for: $0) }
                return extractedProfiles.count > 0
            }
        })

        // Verify extracted profiles are only from non-removed brokers
        let removedBrokerIDs = removedBrokers.compactMap { $0.id }
        assertCondition(withExpectationDescription: "Should have exactly 1 removed broker ID to check",
                        condition: { removedBrokerIDs.count == 1 })

        for removedBrokerID in removedBrokerIDs {
            let extractedProfilesFromRemoved = try! database.fetchExtractedProfiles(for: removedBrokerID)
            assertCondition(withExpectationDescription: "Removed broker (DDG Fake Removed Broker) should not have extracted profiles",
                            condition: { extractedProfilesFromRemoved.isEmpty })
        }

        print("Stage 3 passed: We find and save extracted profiles (only from non-removed brokers)")

        /*
         4/ We create opt out jobs
         */
        let optOutJobsCreatedExpectation = expectation(description: "Opt out jobs created")

        await awaitFulfillment(of: optOutJobsCreatedExpectation,
                               withTimeout: 10,
                               whenCondition: {
            autoreleasepool {
                let queries = try! database.fetchAllBrokerProfileQueryData(shouldFilterRemovedBrokers: true) // Only check non-removed brokers
                let optOutJobs = queries.flatMap { $0.optOutJobData }
                return optOutJobs.count > 0
            }
        })

        // Verify opt-out jobs are only created for non-removed brokers
        let allQueriesWithJobs = try! database.fetchAllBrokerProfileQueryData(shouldFilterRemovedBrokers: false)
        var removedBrokerQueries = allQueriesWithJobs.filter { $0.dataBroker.removedAt != nil }
        assertCondition(withExpectationDescription: "Should have exactly 1 removed broker query to check",
                        condition: { removedBrokerQueries.count == 1 })

        for removedQuery in removedBrokerQueries {
            assertCondition(withExpectationDescription: "Removed broker (DDG Fake Removed Broker) should not have opt-out jobs",
                            condition: { removedQuery.optOutJobData.isEmpty })
        }

        print("Stage 4 passed: We create opt out jobs (only for non-removed brokers)")

        /*
         5/ We run those opt out jobs
         For now we check the lastRunDate on the optOutJob, but that could always be wrong. Ideally we need this information from the fake broker
         */
        let optOutJobsRunExpectation = expectation(description: "Opt out jobs run")

        await awaitFulfillment(of: optOutJobsRunExpectation,
                               withTimeout: 300,
                               whenCondition: {
            autoreleasepool {
                let queries = try! database.fetchAllBrokerProfileQueryData(shouldFilterRemovedBrokers: true) // Only check non-removed brokers
                let optOutJobs = queries.flatMap { $0.optOutJobData }
                return optOutJobs.first?.lastRunDate != nil
            }
        })
        print("Stage 5.1 passed: We start running the opt out jobs (only for non-removed brokers)")

        let optOutRequestedExpectation = expectation(description: "Opt out requested")
        await awaitFulfillment(of: optOutRequestedExpectation,
                               withTimeout: 300,
                               whenCondition: {
            let queries = try! database.fetchAllBrokerProfileQueryData(shouldFilterRemovedBrokers: true) // Only check non-removed brokers
            let optOutJobs = queries.flatMap { $0.optOutJobData }
            let events = optOutJobs.flatMap { $0.historyEvents }
            let optOutsRequested = events.filter { $0.type == .optOutRequested }
            return optOutsRequested.count > 0
        })
        print("Stage 5 passed: We finish running the opt out jobs (only for non-removed brokers)")

        /*
        6/ The BE service receives the email
         The fake broker currently doesn't, but will eventually send this,
         so there's nothing to do on the client to test this step.
         */

        /*
        7/ The app polls the backend service for the link
         8/ We visit the confirmation link

         Since the fake broker doesn't send emails at the moment, we can't actually test these steps
         Once it does, we can use the below code.

          The current only way we can check these from the app is through pixels
          Not great to tie to pixels. Better to check from fake broker we visited confirmation page correctly
         */
        /*
        let optOutEmailReceivedPixelExpectation = expectation(description: "Opt out email received pixel fired")
        let optOutEmailConfirmedPixelExpectation = expectation(description: "Opt out email confirmed pixel fired")

        let optOutEmailReceivedPixel = DataBrokerProtectionSharedPixels.optOutEmailReceive(dataBroker: "", attemptId: UUID(), duration: 0)
        let optOutEmailConfirmedPixel = DataBrokerProtectionSharedPixels.optOutEmailConfirm(dataBroker: "", attemptId: UUID(), duration: 0)

        let pixelExpectations = [
            PixelExpectation(pixel: optOutEmailReceivedPixel,
                             expectation: optOutEmailReceivedPixelExpectation),
            PixelExpectation(pixel: optOutEmailConfirmedPixel,
                             expectation: optOutEmailConfirmedPixelExpectation)]
        let pixelKit = pixelKitToTest(pixelExpectations)
        PixelKit.setSharedForTesting(pixelKit: pixelKit)

        await fulfillment(of: [optOutEmailReceivedPixelExpectation, optOutEmailConfirmedPixelExpectation],
                          timeout: 300)

         PixelKit.tearDown()
         pixelKit.clearFrequencyHistoryForAllPixels()
         */
        print("Stages 6-8 skipped: Fake broker doesn't support sending emails")

        /*
        9/ We confirm the opt out through a scan
         */
        let optOutConfirmedExpectation = expectation(description: "Opt out confirmed")
        await awaitFulfillment(of: optOutConfirmedExpectation,
                               withTimeout: 600,
                               whenCondition: {
            autoreleasepool {
                let queries = try! database.fetchAllBrokerProfileQueryData(shouldFilterRemovedBrokers: true) // Only check non-removed brokers
                let optOutJobs = queries.flatMap { $0.optOutJobData }
                let events = optOutJobs.flatMap { $0.historyEvents }
                let optOutsConfirmed = events.filter { $0.type == .optOutConfirmed }
                return optOutsConfirmed.count > 0
            }
        })

        // Final verification: ensure removed brokers have no confirmed opt-outs
        let allQueriesWithEvents = try! database.fetchAllBrokerProfileQueryData(shouldFilterRemovedBrokers: false)
        removedBrokerQueries = allQueriesWithEvents.filter { $0.dataBroker.removedAt != nil }
        assertCondition(withExpectationDescription: "Should have exactly 1 removed broker query for final verification",
                        condition: { removedBrokerQueries.count == 1 })

        for removedQuery in removedBrokerQueries {
            let events = removedQuery.optOutJobData.flatMap { $0.historyEvents }
            let confirmedEvents = events.filter { $0.type == .optOutConfirmed }
            assertCondition(withExpectationDescription: "Removed broker (DDG Fake Removed Broker) should not have confirmed opt-outs",
                            condition: { confirmedEvents.isEmpty })
        }

        print("Stage 9 passed: We confirm the opt out through a scan (only for non-removed brokers)")
    }
}

// MARK: - Fake broker setup and config

extension DBPEndToEndTests {

    struct FakeBrokerUserProfile: Codable {
        let firstName: String
        let lastName: String
        let age: Int
        let city: String
        let state: String
    }

    struct FakeBrokerReturnedUserProfile: Codable {
        let id: Int
        let profileUrl: String
        let firstName: String
        let lastName: String
        let age: Int
        let city: String
        let state: String
    }

    func mockFakeBrokerUserProfile() -> FakeBrokerUserProfile {
        return FakeBrokerUserProfile(firstName: "John", lastName: "Smith", age: 63, city: "Dallas", state: "TX")
    }

    var fakeBrokerAPIAddress: String {
        "http://localhost:3001/api/"
    }

    func deleteAllProfilesOnFakeBroker() async {
        let deleteProfilesURL = URL(string: fakeBrokerAPIAddress + "profiles")!
        var deleteRequest = URLRequest(url: deleteProfilesURL)
        deleteRequest.httpMethod = "DELETE"

        let (responseData, response) = try! await URLSession.shared.data(for: deleteRequest)
        validateFakeBrokerResponse(responseData: responseData, response: response)
    }

    func createProfileOnFakeBroker(_ profile: FakeBrokerUserProfile) async -> FakeBrokerReturnedUserProfile {
        let url = URL(string: fakeBrokerAPIAddress + "profiles")!
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpMethod = "POST"
        let encoder = JSONEncoder()
        let data = try! encoder.encode(profile)
        request.httpBody = data

        let (responseData, response) = try! await URLSession.shared.data(for: request)
        validateFakeBrokerResponse(responseData: responseData, response: response)

        let decoder = JSONDecoder()
        return try! decoder.decode(FakeBrokerReturnedUserProfile.self, from: responseData)
    }
}

// MARK: - Testing helpers and utilities

private extension DBPEndToEndTests {

    /*
     Used to check an Expectation continuously
     i.e. for Expectations when we don't know exactly when they will complete
     but don't want to have to wait unnecessarily since they may take some time
     */
    private func awaitFulfillment(of expectation: XCTestExpectation, withTimeout timeout: TimeInterval, whenCondition condition: @escaping () async -> Bool) async {
        let task = Task {
            await fulfillExpecation(expectation, whenCondition: condition)
        }

        await fulfillment(of: [expectation], timeout: timeout)
        task.cancel()
    }

    // Helper function for the above
    private func fulfillExpecation(_ expectation: XCTestExpectation, whenCondition condition: () async -> Bool) async {
        while await !condition() { }
        expectation.fulfill()
    }

    /*
     Used instead of using assert etc directly so we get better error messages
     in the log when they fail.
     When we adopt Swift 6 can likely be replaced
     */
    private func assertCondition(withExpectationDescription description: String, condition: () -> Bool) {
        let expectation = expectation(description: description)
        if condition() {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 0)
    }

    typealias PixelExpectation = (pixel: DataBrokerProtectionSharedPixels, expectation: XCTestExpectation)

    private func pixelKitToTest(_ pixelExpectations: [PixelExpectation]) -> PixelKit {
        return PixelKit(dryRun: false,
                        appVersion: "1.0.0",
                        defaultHeaders: [:],
                        defaults: testUserDefault) { pixelName, _, _, _, _, _ in
            for pixelExpectation in pixelExpectations where pixelName.hasPrefix(pixelExpectation.pixel.name) {
                pixelExpectation.expectation.fulfill()
            }
        }
    }

    func validateFakeBrokerResponse(responseData: Data, response: URLResponse) {
        // swiftlint:disable:next force_cast
        let httpResponse = response as! HTTPURLResponse
        if httpResponse.statusCode != 200 {
            prettyPrintJSONData(responseData)
            XCTFail("Response code indidcates failure. Check the printed response data above (if expected json)")
        }
    }

    // A useful function for debugging responses from the fake broker
    func prettyPrintJSONData(_ data: Data) {
        if let json = try? JSONSerialization.jsonObject(with: data, options: .mutableContainers),
           let jsonData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
           let jsonString = jsonData.utf8String() {
            print(jsonString)
        } else {
            print("json data malformed")
        }
    }
}

// MARK: - Mocks

private extension DBPEndToEndTests {

    var mockProfile: DataBrokerProtectionProfile {
        // Use the current year to calculate age, since the fake broker is static (so will always list "63")
        let year = Calendar(identifier: .gregorian).component(.year, from: Date())
        let birthYear = year - 63

        return .init(names: [.init(firstName: "John", lastName: "Smith")],
                     addresses: [.init(city: "Dallas", state: "TX")],
                     phones: [],
                     birthYear: birthYear)
    }

    final class PrivacyConfigurationManagingMock: PrivacyConfigurationManaging {
        var currentConfig: Data = Data()

        var updatesPublisher: AnyPublisher<Void, Never> = .init(Just(()))

        var privacyConfig: BrowserServicesKit.PrivacyConfiguration = PrivacyConfigurationMock()

        var internalUserDecider: InternalUserDecider = DefaultInternalUserDecider(store: InternalUserDeciderStoreMock())

        func reload(etag: String?, data: Data?) -> PrivacyConfigurationManager.ReloadResult {
            .downloaded
        }
    }

    final class PrivacyConfigurationMock: PrivacyConfiguration {
        var identifier: String = "mock"
        var version: String? = "123456789"

        var userUnprotectedDomains = [String]()

        var tempUnprotectedDomains = [String]()

        var trackerAllowlist = BrowserServicesKit.PrivacyConfigurationData.TrackerAllowlist(entries: [String: [PrivacyConfigurationData.TrackerAllowlist.Entry]](), state: "mock")

        func isEnabled(featureKey: BrowserServicesKit.PrivacyFeature, versionProvider: BrowserServicesKit.AppVersionProvider, defaultValue: Bool) -> Bool {
            false
        }

        func stateFor(featureKey: BrowserServicesKit.PrivacyFeature, versionProvider: BrowserServicesKit.AppVersionProvider) -> BrowserServicesKit.PrivacyConfigurationFeatureState {
            .disabled(.disabledInConfig)
        }

        func isSubfeatureEnabled(_ subfeature: any BrowserServicesKit.PrivacySubfeature, versionProvider: AppVersionProvider, randomizer: (Range<Double>) -> Double, defaultValue: Bool) -> Bool {
            false
        }

        func stateFor(_ subfeature: any PrivacySubfeature, versionProvider: BrowserServicesKit.AppVersionProvider, randomizer: (Range<Double>) -> Double) -> BrowserServicesKit.PrivacyConfigurationFeatureState {
            .disabled(.disabledInConfig)
        }

        func exceptionsList(forFeature featureKey: BrowserServicesKit.PrivacyFeature) -> [String] {
            [String]()
        }

        func isFeature(_ feature: BrowserServicesKit.PrivacyFeature, enabledForDomain: String?) -> Bool {
            false
        }

        func isProtected(domain: String?) -> Bool {
            false
        }

        func isUserUnprotected(domain: String?) -> Bool {
            false
        }

        func isTempUnprotected(domain: String?) -> Bool {
            false
        }

        func isInExceptionList(domain: String?, forFeature featureKey: BrowserServicesKit.PrivacyFeature) -> Bool {
            false
        }

        func settings(for feature: BrowserServicesKit.PrivacyFeature) -> BrowserServicesKit.PrivacyConfigurationData.PrivacyFeature.FeatureSettings {
            [String: Any]()
        }

        func settings(for subfeature: any BrowserServicesKit.PrivacySubfeature) -> PrivacyConfigurationData.PrivacyFeature.SubfeatureSettings? {
            nil
        }

        func userEnabledProtection(forDomain: String) {

        }

        func userDisabledProtection(forDomain: String) {

        }

        func stateFor(subfeatureID: SubfeatureID, parentFeatureID: ParentFeatureID, versionProvider: AppVersionProvider, randomizer: (Range<Double>) -> Double) -> PrivacyConfigurationFeatureState {
            .disabled(.disabledInConfig)
        }

        func cohorts(for subfeature: any PrivacySubfeature) -> [PrivacyConfigurationData.Cohort]? {
            return nil
        }

        func cohorts(subfeatureID: SubfeatureID, parentFeatureID: ParentFeatureID) -> [PrivacyConfigurationData.Cohort]? {
            return nil
        }
    }
}

// swiftlint:enable force_try

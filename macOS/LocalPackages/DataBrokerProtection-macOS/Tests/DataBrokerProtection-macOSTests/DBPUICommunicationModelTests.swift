//
//  DBPUICommunicationModelTests.swift
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

import XCTest
import Foundation
@testable import DataBrokerProtection_macOS
import DataBrokerProtectionCore
import DataBrokerProtectionCoreTestsUtils

final class DBPUICommunicationModelTests: XCTestCase {

    private func makeUIBroker(name: String = "doesn't matter for the test",
                              url: String = "see above",
                              parentURL: String? = nil,
                              optOutUrl: String = "broker.com") -> DBPUIDataBroker {
        DBPUIDataBroker(name: name,
                        url: url,
                        parentURL: parentURL,
                        optOutUrl: optOutUrl)
    }

    func testProfileMatchInit_whenCreatedDateIsNotDefault_thenResultingProfileMatchDatesAreBothBasedOnOptOutJobDataDates() {

        // Given
        let extractedProfile = ExtractedProfile.mockWithRemovedDate

        let foundEventDate = Calendar.current.date(byAdding: .day, value: -20, to: Date.now)!
        let submittedEventDate = Calendar.current.date(byAdding: .day, value: -18, to: Date.now)!
        let historyEvents = [
            HistoryEvent(extractedProfileId: 0, brokerId: 0, profileQueryId: 0, type: .matchesFound(count: 1), date: foundEventDate),
            HistoryEvent(extractedProfileId: 0, brokerId: 0, profileQueryId: 0, type: .optOutRequested, date: submittedEventDate)
        ]

        let createdDate = Calendar.current.date(byAdding: .day, value: -14, to: Date.now)!
        let submittedDate = Calendar.current.date(byAdding: .day, value: -7, to: Date.now)!
        let optOut = OptOutJobData.mock(with: extractedProfile,
                                        historyEvents: historyEvents,
                                        createdDate: createdDate,
                                        submittedSuccessfullyDate: submittedDate)

        // When
        let profileMatch = DBPUIDataBrokerProfileMatch(optOutJobData: optOut,
                                                       dataBroker: makeUIBroker(parentURL: "whatever"),
                                                       parentBrokerOptOutJobData: nil)

        // Then
        XCTAssertEqual(profileMatch.foundDate, createdDate.timeIntervalSince1970)
        XCTAssertEqual(profileMatch.optOutSubmittedDate, submittedDate.timeIntervalSince1970)
    }

    func testProfileMatchInit_whenExtractedProfileHasProfileUrl_thenProfileUrlIsExposed() {
        // Given
        let profileUrl = "https://example.com/profile/123"
        let extractedProfile = ExtractedProfile(id: 1, name: "Sample Name", profileUrl: profileUrl)
        let optOut = OptOutJobData.mock(with: extractedProfile)

        // When
        let profileMatch = DBPUIDataBrokerProfileMatch(optOutJobData: optOut,
                                                       dataBroker: makeUIBroker(),
                                                       parentBrokerOptOutJobData: nil)

        // Then
        XCTAssertEqual(profileMatch.profileUrl, profileUrl)
    }

    func testProfileMatchInit_whenCreatedDateIsDefault_thenResultingProfileMatchDatesAreBothBasedOnEventDates() {

        // Given
        let extractedProfile = ExtractedProfile.mockWithRemovedDate

        let foundEventDate = Calendar.current.date(byAdding: .day, value: -20, to: Date.now)!
        let submittedEventDate = Calendar.current.date(byAdding: .day, value: -18, to: Date.now)!
        let historyEvents = [
            HistoryEvent(extractedProfileId: 0, brokerId: 0, profileQueryId: 0, type: .matchesFound(count: 1), date: foundEventDate),
            HistoryEvent(extractedProfileId: 0, brokerId: 0, profileQueryId: 0, type: .optOutRequested, date: submittedEventDate)
        ]

        let createdDate = Date(timeIntervalSince1970: 0)
        let submittedDate = Calendar.current.date(byAdding: .day, value: -7, to: Date.now)!
        let optOut = OptOutJobData.mock(with: extractedProfile,
                                        historyEvents: historyEvents,
                                        createdDate: createdDate,
                                        submittedSuccessfullyDate: submittedDate)

        // When
        let profileMatch = DBPUIDataBrokerProfileMatch(optOutJobData: optOut,
                                                       dataBroker: makeUIBroker(parentURL: "whatever"),
                                                       parentBrokerOptOutJobData: nil)

        // Then
        XCTAssertEqual(profileMatch.foundDate, foundEventDate.timeIntervalSince1970)
        XCTAssertEqual(profileMatch.optOutSubmittedDate, submittedEventDate.timeIntervalSince1970)
    }

    func testProfileMatchInit_whenCreatedDateIsDefaultAndThereAreMultipleEventsOfTheSameType_thenResultingProfileMatchDatesAreBothBasedOnFirstEventDates() {

        // Given
        let extractedProfile = ExtractedProfile.mockWithRemovedDate

        let foundEventDate1 = Calendar.current.date(byAdding: .day, value: -20, to: Date.now)!
        let foundEventDate2 = Calendar.current.date(byAdding: .day, value: -21, to: Date.now)!
        let foundEventDate3 = Calendar.current.date(byAdding: .day, value: -19, to: Date.now)!
        let submittedEventDate1 = Calendar.current.date(byAdding: .day, value: -18, to: Date.now)!
        let submittedEventDate2 = Calendar.current.date(byAdding: .day, value: -19, to: Date.now)!
        let submittedEventDate3 = Calendar.current.date(byAdding: .day, value: -17, to: Date.now)!
        let historyEvents = [
            HistoryEvent(extractedProfileId: 0, brokerId: 0, profileQueryId: 0, type: .matchesFound(count: 1), date: foundEventDate1),
            HistoryEvent(extractedProfileId: 0, brokerId: 0, profileQueryId: 0, type: .matchesFound(count: 1), date: foundEventDate2),
            HistoryEvent(extractedProfileId: 0, brokerId: 0, profileQueryId: 0, type: .matchesFound(count: 1), date: foundEventDate3),
            HistoryEvent(extractedProfileId: 0, brokerId: 0, profileQueryId: 0, type: .optOutRequested, date: submittedEventDate1),
            HistoryEvent(extractedProfileId: 0, brokerId: 0, profileQueryId: 0, type: .optOutRequested, date: submittedEventDate2),
            HistoryEvent(extractedProfileId: 0, brokerId: 0, profileQueryId: 0, type: .optOutRequested, date: submittedEventDate3)
        ]

        let createdDate = Date(timeIntervalSince1970: 0)
        let submittedDate = Calendar.current.date(byAdding: .day, value: -7, to: Date.now)!
        let optOut = OptOutJobData.mock(with: extractedProfile,
                                        historyEvents: historyEvents,
                                        createdDate: createdDate,
                                        submittedSuccessfullyDate: submittedDate)

        // When
        let profileMatch = DBPUIDataBrokerProfileMatch(optOutJobData: optOut,
                                                       dataBroker: makeUIBroker(parentURL: "whatever"),
                                                       parentBrokerOptOutJobData: nil)

        // Then
        XCTAssertEqual(profileMatch.foundDate, foundEventDate2.timeIntervalSince1970)
        XCTAssertEqual(profileMatch.optOutSubmittedDate, submittedEventDate2.timeIntervalSince1970)
    }

    /*
     test cases
     one exact matching parent
     one exact matching parent mixed in the array (probs can combnie with above
     no match
     partial match
     */

    func testProfileMatchInit_whenThereIsExactParentMatch_thenHasMatchingRecordOnParentBrokerIsTrue() {

        // Given
        let extractedProfile = ExtractedProfile.mockWithName("Steve Jones", age: "20", addresses: [AddressCityState(city: "New York", state: "NY")])
        let parentProfile = ExtractedProfile.mockWithName("Steve Jones", age: "20", addresses: [AddressCityState(city: "New York", state: "NY")])

        let optOut = OptOutJobData.mock(with: extractedProfile,
                                        historyEvents: [])
        let parentOptOut = OptOutJobData.mock(with: parentProfile,
                                              historyEvents: [])

        // When
        let profileMatch = DBPUIDataBrokerProfileMatch(optOutJobData: optOut,
                                                       dataBroker: makeUIBroker(parentURL: "whatever"),
                                                       parentBrokerOptOutJobData: [parentOptOut])

        // Then
        XCTAssertTrue(profileMatch.hasMatchingRecordOnParentBroker)
    }

    func testProfileMatchInit_whenThereAreMultipleNonMatchingProfilesAndAnExactParentMatch_thenHasMatchingRecordOnParentBrokerIsTrue() {

        // Given
        let extractedProfile = ExtractedProfile.mockWithName("Steve Jones", age: "20", addresses: [AddressCityState(city: "New York", state: "NY")])
        let parentProfileMatching = ExtractedProfile.mockWithName("Steve Jones", age: "20", addresses: [AddressCityState(city: "New York", state: "NY")])
        let parentProfileNonmatching1 = ExtractedProfile.mockWithName("Steve Jones", age: "30", addresses: [AddressCityState(city: "New York", state: "NY")])
        let parentProfileNonmatching2 = ExtractedProfile.mockWithName("Jamie Jones", age: "20", addresses: [AddressCityState(city: "New York", state: "NY")])

        let optOut = OptOutJobData.mock(with: extractedProfile,
                                        historyEvents: [])
        let parentOptOutMatching = OptOutJobData.mock(with: parentProfileMatching,
                                                      historyEvents: [])
        let parentOptOutNonmatching1 = OptOutJobData.mock(with: parentProfileNonmatching1,
                                                      historyEvents: [])
        let parentOptOutNonmatching2 = OptOutJobData.mock(with: parentProfileNonmatching2,
                                                      historyEvents: [])

        // When
        let profileMatch = DBPUIDataBrokerProfileMatch(optOutJobData: optOut,
                                                       dataBroker: makeUIBroker(parentURL: "whatever"),
                                                       parentBrokerOptOutJobData: [parentOptOutNonmatching1,
                                                                                   parentOptOutMatching,
                                                                                   parentOptOutNonmatching2])

        // Then
        XCTAssertTrue(profileMatch.hasMatchingRecordOnParentBroker)
    }

    func testProfileMatchInit_whenThereIsNoParentMatch_thenHasMatchingRecordOnParentBrokerIsFalse() {

        // Given
        let extractedProfile = ExtractedProfile.mockWithName("Steve Jones", age: "20", addresses: [AddressCityState(city: "New York", state: "NY")])
        let parentProfileNonmatching1 = ExtractedProfile.mockWithName("Steve Jones", age: "30", addresses: [AddressCityState(city: "New York", state: "NY")])
        let parentProfileNonmatching2 = ExtractedProfile.mockWithName("Jamie Jones", age: "20", addresses: [AddressCityState(city: "New York", state: "NY")])

        let optOut = OptOutJobData.mock(with: extractedProfile,
                                        historyEvents: [])
        let parentOptOutNonmatching1 = OptOutJobData.mock(with: parentProfileNonmatching1,
                                                      historyEvents: [])
        let parentOptOutNonmatching2 = OptOutJobData.mock(with: parentProfileNonmatching2,
                                                      historyEvents: [])

        // When
        let profileMatch = DBPUIDataBrokerProfileMatch(optOutJobData: optOut,
                                                       dataBroker: makeUIBroker(parentURL: "whatever"),
                                                       parentBrokerOptOutJobData: [parentOptOutNonmatching1,
                                                                                   parentOptOutNonmatching2])

        // Then
        XCTAssertFalse(profileMatch.hasMatchingRecordOnParentBroker)
    }

    func testProfileMatchInit_whenThereIsANonExactParentMatch_thenHasMatchingRecordOnParentBrokerIsTrue() {

        // Given
        let extractedProfile = ExtractedProfile.mockWithName("Steve Jones", age: "20", addresses: [AddressCityState(city: "New York", state: "NY")])
        let parentProfile = ExtractedProfile.mockWithName("Steve Jones", age: "20", addresses: [AddressCityState(city: "New York", state: "NY"), AddressCityState(city: "Atlanta", state: "GA")])

        let optOut = OptOutJobData.mock(with: extractedProfile,
                                        historyEvents: [])
        let parentOptOut = OptOutJobData.mock(with: parentProfile,
                                              historyEvents: [])

        // When
        let profileMatch = DBPUIDataBrokerProfileMatch(optOutJobData: optOut,
                                                       dataBroker: makeUIBroker(parentURL: "whatever"),
                                                       parentBrokerOptOutJobData: [parentOptOut])

        // Then
        XCTAssertTrue(profileMatch.hasMatchingRecordOnParentBroker)
    }

    // MARK: - `profileMatches` Broker OptOut URL & Name tests

    func testProfileMatches_optOutUrlAndBrokerNameForChildBroker() {
        // Given
        let extractedProfile = ExtractedProfile(id: 1, name: "Sample Name", profileUrl: "profile.com")

        let childBroker = BrokerProfileQueryData.mock(
            dataBrokerName: "ChildBroker",
            url: "child.com",
            parentURL: "parent.com",
            optOutUrl: "child.com/optout",
            extractedProfile: extractedProfile
        )

        let parentBroker = BrokerProfileQueryData.mock(
            dataBrokerName: "ParentBroker",
            url: "parent.com",
            optOutUrl: "parent.com/optout",
            extractedProfile: extractedProfile
        )

        // When
        let results = DBPUIDataBrokerProfileMatch.profileMatches(from: [childBroker, parentBroker])

        // Then
        XCTAssertEqual(results.count, 2)

        let childProfile = results.first { $0.dataBroker.name == "ChildBroker" }
        XCTAssertEqual(childProfile?.dataBroker.optOutUrl, "child.com/optout")
    }

    // MARK: - `optOutFormSubmittedDate` tests

    func testProfileMatchInit_forNonEmailBroker_whenOptOutHasOptOutRequestedEvent_thenOptOutFormSubmittedDateMatchesThatEventDate() {

        // Given
        let extractedProfile = ExtractedProfile.mockWithoutRemovedDate
        let optOutRequestedDate = Calendar.current.date(byAdding: .day, value: -10, to: Date.now)!
        let historyEvents = [
            HistoryEvent(extractedProfileId: 0, brokerId: 0, profileQueryId: 0, type: .optOutStarted, date: Calendar.current.date(byAdding: .day, value: -12, to: Date.now)!),
            HistoryEvent(extractedProfileId: 0, brokerId: 0, profileQueryId: 0, type: .optOutRequested, date: optOutRequestedDate)
        ]

        let optOut = OptOutJobData.mock(with: extractedProfile,
                                        historyEvents: historyEvents,
                                        createdDate: Calendar.current.date(byAdding: .day, value: -14, to: Date.now)!,
                                        submittedSuccessfullyDate: optOutRequestedDate)

        // When
        let profileMatch = DBPUIDataBrokerProfileMatch(optOutJobData: optOut,
                                                       dataBroker: makeUIBroker(),
                                                       parentBrokerOptOutJobData: nil)

        // Then
        XCTAssertEqual(profileMatch.optOutFormSubmittedDate, optOutRequestedDate.timeIntervalSince1970)
    }

    func testProfileMatchInit_forEmailBrokerDecoupledFlow_whenBothFormSubmittedAndOptOutRequestedEventsExist_thenOptOutFormSubmittedDateMatchesTheEarlierEvent() {

        // Given
        let extractedProfile = ExtractedProfile.mockWithoutRemovedDate
        let formSubmittedDate = Calendar.current.date(byAdding: .day, value: -12, to: Date.now)!
        let confirmationDate = Calendar.current.date(byAdding: .day, value: -8, to: Date.now)!
        let historyEvents = [
            HistoryEvent(extractedProfileId: 0, brokerId: 0, profileQueryId: 0, type: .optOutStarted, date: Calendar.current.date(byAdding: .day, value: -14, to: Date.now)!),
            HistoryEvent(extractedProfileId: 0, brokerId: 0, profileQueryId: 0, type: .optOutSubmittedAndAwaitingEmailConfirmation, date: formSubmittedDate),
            HistoryEvent(extractedProfileId: 0, brokerId: 0, profileQueryId: 0, type: .optOutRequested, date: confirmationDate)
        ]

        let optOut = OptOutJobData.mock(with: extractedProfile,
                                        historyEvents: historyEvents,
                                        createdDate: Calendar.current.date(byAdding: .day, value: -14, to: Date.now)!,
                                        submittedSuccessfullyDate: confirmationDate)

        // When
        let profileMatch = DBPUIDataBrokerProfileMatch(optOutJobData: optOut,
                                                       dataBroker: makeUIBroker(),
                                                       parentBrokerOptOutJobData: nil)

        // Then
        XCTAssertEqual(profileMatch.optOutFormSubmittedDate, formSubmittedDate.timeIntervalSince1970)
        XCTAssertEqual(profileMatch.optOutSubmittedDate, confirmationDate.timeIntervalSince1970)
    }

    func testProfileMatchInit_whenOptOutHasNoFormSubmissionEvents_thenOptOutFormSubmittedDateIsNil() {

        // Given
        let extractedProfile = ExtractedProfile.mockWithoutRemovedDate
        let historyEvents = [
            HistoryEvent(extractedProfileId: 0, brokerId: 0, profileQueryId: 0, type: .optOutStarted, date: Calendar.current.date(byAdding: .day, value: -2, to: Date.now)!)
        ]

        let optOut = OptOutJobData.mock(with: extractedProfile,
                                        historyEvents: historyEvents,
                                        createdDate: Calendar.current.date(byAdding: .day, value: -3, to: Date.now)!,
                                        submittedSuccessfullyDate: nil)

        // When
        let profileMatch = DBPUIDataBrokerProfileMatch(optOutJobData: optOut,
                                                       dataBroker: makeUIBroker(),
                                                       parentBrokerOptOutJobData: nil)

        // Then
        XCTAssertNil(profileMatch.optOutFormSubmittedDate)
    }

    func testProfileMatchInit_forChildBroker_whenParentHasFormSubmission_thenOptOutFormSubmittedDateComesFromParent() {

        // Given
        let childExtractedProfile = ExtractedProfile.mockWithoutRemovedDate
        let parentExtractedProfile = ExtractedProfile.mockWithoutRemovedDate
        let parentFormSubmittedDate = Calendar.current.date(byAdding: .day, value: -5, to: Date.now)!
        let parentHistoryEvents = [
            HistoryEvent(extractedProfileId: 0, brokerId: 0, profileQueryId: 0, type: .optOutRequested, date: parentFormSubmittedDate)
        ]

        let childOptOut = OptOutJobData.mock(with: childExtractedProfile, historyEvents: [])
        let parentOptOut = OptOutJobData.mock(with: parentExtractedProfile, historyEvents: parentHistoryEvents)

        // When
        let profileMatch = DBPUIDataBrokerProfileMatch(optOutJobData: childOptOut,
                                                       dataBroker: makeUIBroker(parentURL: "parent.com"),
                                                       parentBrokerOptOutJobData: [parentOptOut])

        // Then
        XCTAssertEqual(profileMatch.optOutFormSubmittedDate, parentFormSubmittedDate.timeIntervalSince1970)
    }

    func testProfileMatchInit_forChildBroker_whenParentHasMultipleFormSubmissions_thenOptOutFormSubmittedDateIsTheMostRecent() {

        // Given: parent opt-out names intentionally don't match the child — strict matching is bypassed.
        let childExtractedProfile = ExtractedProfile.mockWithName("Adam P Smith", age: "30", addresses: [AddressCityState(city: "New York", state: "NY")])
        let olderDate = Calendar.current.date(byAdding: .day, value: -20, to: Date.now)!
        let mostRecentDate = Calendar.current.date(byAdding: .day, value: -3, to: Date.now)!
        let middleDate = Calendar.current.date(byAdding: .day, value: -10, to: Date.now)!

        let parentOptOutOldest = OptOutJobData.mock(
            with: ExtractedProfile.mockWithName("Different Person", age: "40", addresses: []),
            historyEvents: [HistoryEvent(extractedProfileId: 0, brokerId: 0, profileQueryId: 0, type: .optOutRequested, date: olderDate)]
        )
        let parentOptOutMiddle = OptOutJobData.mock(
            with: ExtractedProfile.mockWithName("Adam Joseph Smith", age: "30", addresses: [AddressCityState(city: "New York", state: "NY")]),
            historyEvents: [HistoryEvent(extractedProfileId: 0, brokerId: 0, profileQueryId: 0, type: .optOutRequested, date: middleDate)]
        )
        let parentOptOutNewest = OptOutJobData.mock(
            with: ExtractedProfile.mockWithName("Yet Another Person", age: "50", addresses: []),
            historyEvents: [HistoryEvent(extractedProfileId: 0, brokerId: 0, profileQueryId: 0, type: .optOutRequested, date: mostRecentDate)]
        )

        let childOptOut = OptOutJobData.mock(with: childExtractedProfile, historyEvents: [])

        // When
        let profileMatch = DBPUIDataBrokerProfileMatch(optOutJobData: childOptOut,
                                                       dataBroker: makeUIBroker(parentURL: "parent.com"),
                                                       parentBrokerOptOutJobData: [parentOptOutOldest, parentOptOutNewest, parentOptOutMiddle])

        // Then
        XCTAssertEqual(profileMatch.optOutFormSubmittedDate, mostRecentDate.timeIntervalSince1970)
    }

    func testProfileMatches_optOutUrlAndBrokerNameForParentBroker() {
        // Given
        let extractedProfile = ExtractedProfile(id: 1, name: "Sample Name", profileUrl: "profile.com")

        let childBroker = BrokerProfileQueryData.mock(
            dataBrokerName: "ChildBroker",
            url: "child.com",
            parentURL: "parent.com",
            optOutUrl: "parent.com/optout",
            extractedProfile: extractedProfile
        )

        let parentBroker = BrokerProfileQueryData.mock(
            dataBrokerName: "ParentBroker",
            url: "parent.com",
            optOutUrl: "parent.com/optout",
            extractedProfile: extractedProfile
        )

        // When
        let results = DBPUIDataBrokerProfileMatch.profileMatches(from: [childBroker, parentBroker])

        // Then
        XCTAssertEqual(results.count, 2)

        let childProfile = results.first { $0.dataBroker.name == "ChildBroker" }
        XCTAssertEqual(childProfile?.dataBroker.optOutUrl, "parent.com/optout")
    }
}

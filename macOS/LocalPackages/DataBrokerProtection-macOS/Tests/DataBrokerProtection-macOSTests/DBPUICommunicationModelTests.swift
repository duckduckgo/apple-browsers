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

    // MARK: - optOutFormSubmittedDate derivation

    func testProfileMatchInit_whenNonEmailBrokerHasOptOutRequestedEvent_thenOptOutFormSubmittedDateIsThatEventDate() {

        // Given — non-email-confirming broker: `.optOutRequested` is logged at form submission
        // success, so it represents both moment 1 and moment 2.
        let extractedProfile = ExtractedProfile.mockWithoutRemovedDate
        let optOutRequestedDate = Calendar.current.date(byAdding: .day, value: -3, to: Date.now)!
        let historyEvents = [
            HistoryEvent(extractedProfileId: 0, brokerId: 0, profileQueryId: 0, type: .optOutRequested, date: optOutRequestedDate)
        ]
        let optOut = OptOutJobData.mock(with: extractedProfile,
                                        historyEvents: historyEvents,
                                        createdDate: Date.now,
                                        submittedSuccessfullyDate: optOutRequestedDate)

        // When
        let profileMatch = DBPUIDataBrokerProfileMatch(optOutJobData: optOut,
                                                       dataBroker: makeUIBroker(),
                                                       parentBrokerOptOutJobData: nil)

        // Then
        XCTAssertEqual(profileMatch.optOutFormSubmittedDate, optOutRequestedDate.timeIntervalSince1970)
        XCTAssertEqual(profileMatch.optOutSubmittedDate, optOutRequestedDate.timeIntervalSince1970)
    }

    func testProfileMatchInit_whenEmailBrokerHasFormSubmittedAndConfirmationEvents_thenOptOutFormSubmittedDateIsTheFormSubmissionEventDate() {

        // Given — email-confirming broker: `.optOutSubmittedAndAwaitingEmailConfirmation` is
        // logged at form submission (moment 1), `.optOutRequested` is logged later, after the
        // broker confirms by email (moment 2).
        let extractedProfile = ExtractedProfile.mockWithoutRemovedDate
        let formSubmittedAtDate = Calendar.current.date(byAdding: .day, value: -5, to: Date.now)!
        let emailConfirmedDate = Calendar.current.date(byAdding: .day, value: -2, to: Date.now)!
        let historyEvents = [
            HistoryEvent(extractedProfileId: 0, brokerId: 0, profileQueryId: 0, type: .optOutSubmittedAndAwaitingEmailConfirmation, date: formSubmittedAtDate),
            HistoryEvent(extractedProfileId: 0, brokerId: 0, profileQueryId: 0, type: .optOutRequested, date: emailConfirmedDate)
        ]
        let optOut = OptOutJobData.mock(with: extractedProfile,
                                        historyEvents: historyEvents,
                                        createdDate: Date.now,
                                        submittedSuccessfullyDate: emailConfirmedDate)

        // When
        let profileMatch = DBPUIDataBrokerProfileMatch(optOutJobData: optOut,
                                                       dataBroker: makeUIBroker(),
                                                       parentBrokerOptOutJobData: nil)

        // Then
        XCTAssertEqual(profileMatch.optOutFormSubmittedDate, formSubmittedAtDate.timeIntervalSince1970)
        XCTAssertEqual(profileMatch.optOutSubmittedDate, emailConfirmedDate.timeIntervalSince1970)
    }

    func testProfileMatchInit_whenMultipleSubmissionEventsExist_thenOptOutFormSubmittedDateIsTheFirstOne() {

        // Given — value should be set once at the first successful submission and not overwritten
        // on retries.
        let extractedProfile = ExtractedProfile.mockWithoutRemovedDate
        let firstAttempt = Calendar.current.date(byAdding: .day, value: -10, to: Date.now)!
        let secondAttempt = Calendar.current.date(byAdding: .day, value: -5, to: Date.now)!
        let historyEvents = [
            HistoryEvent(extractedProfileId: 0, brokerId: 0, profileQueryId: 0, type: .optOutRequested, date: secondAttempt),
            HistoryEvent(extractedProfileId: 0, brokerId: 0, profileQueryId: 0, type: .optOutRequested, date: firstAttempt)
        ]
        let optOut = OptOutJobData.mock(with: extractedProfile,
                                        historyEvents: historyEvents,
                                        createdDate: Date.now,
                                        submittedSuccessfullyDate: nil)

        // When
        let profileMatch = DBPUIDataBrokerProfileMatch(optOutJobData: optOut,
                                                       dataBroker: makeUIBroker(),
                                                       parentBrokerOptOutJobData: nil)

        // Then
        XCTAssertEqual(profileMatch.optOutFormSubmittedDate, firstAttempt.timeIntervalSince1970)
    }

    func testProfileMatchInit_whenNoSubmissionEventsAndNoParent_thenOptOutFormSubmittedDateIsNil() {

        // Given
        let extractedProfile = ExtractedProfile.mockWithoutRemovedDate
        let historyEvents = [
            HistoryEvent(extractedProfileId: 0, brokerId: 0, profileQueryId: 0, type: .matchesFound(count: 1), date: Date.now)
        ]
        let optOut = OptOutJobData.mock(with: extractedProfile,
                                        historyEvents: historyEvents,
                                        createdDate: Date.now,
                                        submittedSuccessfullyDate: nil)

        // When
        let profileMatch = DBPUIDataBrokerProfileMatch(optOutJobData: optOut,
                                                       dataBroker: makeUIBroker(),
                                                       parentBrokerOptOutJobData: nil)

        // Then
        XCTAssertNil(profileMatch.optOutFormSubmittedDate)
    }

    func testProfileMatchInit_whenChildBrokerHasNoOwnSubmissionEventsButParentDoes_thenOptOutFormSubmittedDateFallsBackToParent() {

        // Given — child broker's opt-out is performed by its parent rather than directly, so the
        // child has no submission events of its own; the parent ran the opt-out and has the
        // submission event.
        let extractedProfile = ExtractedProfile.mockWithName("Steve Jones", age: "20", addresses: [AddressCityState(city: "New York", state: "NY")])
        let parentProfile = ExtractedProfile.mockWithName("Steve Jones", age: "20", addresses: [AddressCityState(city: "New York", state: "NY")])

        let parentSubmissionDate = Calendar.current.date(byAdding: .day, value: -4, to: Date.now)!
        let parentEvents = [
            HistoryEvent(extractedProfileId: 0, brokerId: 0, profileQueryId: 0, type: .optOutRequested, date: parentSubmissionDate)
        ]

        let childOptOut = OptOutJobData.mock(with: extractedProfile, historyEvents: [])
        let parentOptOut = OptOutJobData.mock(with: parentProfile, historyEvents: parentEvents)

        // When
        let profileMatch = DBPUIDataBrokerProfileMatch(optOutJobData: childOptOut,
                                                       dataBroker: makeUIBroker(parentURL: "parent.com"),
                                                       parentBrokerOptOutJobData: [parentOptOut])

        // Then
        XCTAssertEqual(profileMatch.optOutFormSubmittedDate, parentSubmissionDate.timeIntervalSince1970)
    }

    func testProfileMatchInit_whenChildBrokerHasNoOwnSubmissionEventsAndParentMatchHasNone_thenOptOutFormSubmittedDateIsNil() {

        // Given
        let extractedProfile = ExtractedProfile.mockWithName("Steve Jones", age: "20", addresses: [AddressCityState(city: "New York", state: "NY")])
        let parentProfile = ExtractedProfile.mockWithName("Steve Jones", age: "20", addresses: [AddressCityState(city: "New York", state: "NY")])

        let childOptOut = OptOutJobData.mock(with: extractedProfile, historyEvents: [])
        let parentOptOut = OptOutJobData.mock(with: parentProfile, historyEvents: [])

        // When
        let profileMatch = DBPUIDataBrokerProfileMatch(optOutJobData: childOptOut,
                                                       dataBroker: makeUIBroker(parentURL: "parent.com"),
                                                       parentBrokerOptOutJobData: [parentOptOut])

        // Then
        XCTAssertNil(profileMatch.optOutFormSubmittedDate)
    }

    func testProfileMatchInit_whenChildHasOwnSubmissionEventAndParentAlsoHasOne_thenOptOutFormSubmittedDatePrefersChild() {

        // Given — defensive: if a child somehow has its own submission event, the child's own
        // value should win over the parent fallback.
        let extractedProfile = ExtractedProfile.mockWithName("Steve Jones", age: "20", addresses: [AddressCityState(city: "New York", state: "NY")])
        let parentProfile = ExtractedProfile.mockWithName("Steve Jones", age: "20", addresses: [AddressCityState(city: "New York", state: "NY")])

        let childSubmission = Calendar.current.date(byAdding: .day, value: -2, to: Date.now)!
        let parentSubmission = Calendar.current.date(byAdding: .day, value: -10, to: Date.now)!

        let childOptOut = OptOutJobData.mock(
            with: extractedProfile,
            historyEvents: [HistoryEvent(extractedProfileId: 0, brokerId: 0, profileQueryId: 0, type: .optOutRequested, date: childSubmission)]
        )
        let parentOptOut = OptOutJobData.mock(
            with: parentProfile,
            historyEvents: [HistoryEvent(extractedProfileId: 0, brokerId: 0, profileQueryId: 0, type: .optOutRequested, date: parentSubmission)]
        )

        // When
        let profileMatch = DBPUIDataBrokerProfileMatch(optOutJobData: childOptOut,
                                                       dataBroker: makeUIBroker(parentURL: "parent.com"),
                                                       parentBrokerOptOutJobData: [parentOptOut])

        // Then
        XCTAssertEqual(profileMatch.optOutFormSubmittedDate, childSubmission.timeIntervalSince1970)
    }

    func testProfileMatchInit_whenChildHasNoSubmissionEventsAndParentMatchIsNotAnExactProfileMatch_thenOptOutFormSubmittedDateStillUsesParentSubmission() {

        // Given — broker-level fallback: every child broker record is structurally downstream of
        // the parent, so any parent submission is a removal request that may clear this record.
        // The strict matcher (`doesMatchExtractedProfile`) is reserved for
        // `hasMatchingRecordOnParentBroker`.
        let extractedProfile = ExtractedProfile.mockWithName("Steve Jones", age: "20", addresses: [AddressCityState(city: "New York", state: "NY")])
        let parentProfileNonmatching = ExtractedProfile.mockWithName("Jamie Jones", age: "20", addresses: [AddressCityState(city: "New York", state: "NY")])

        let parentSubmission = Calendar.current.date(byAdding: .day, value: -4, to: Date.now)!
        let childOptOut = OptOutJobData.mock(with: extractedProfile, historyEvents: [])
        let parentOptOut = OptOutJobData.mock(
            with: parentProfileNonmatching,
            historyEvents: [HistoryEvent(extractedProfileId: 0, brokerId: 0, profileQueryId: 0, type: .optOutRequested, date: parentSubmission)]
        )

        // When
        let profileMatch = DBPUIDataBrokerProfileMatch(optOutJobData: childOptOut,
                                                       dataBroker: makeUIBroker(parentURL: "parent.com"),
                                                       parentBrokerOptOutJobData: [parentOptOut])

        // Then
        XCTAssertEqual(profileMatch.optOutFormSubmittedDate, parentSubmission.timeIntervalSince1970)
        // Strict matcher still rejects, so the parent-broker-duplicate signal stays false.
        XCTAssertFalse(profileMatch.hasMatchingRecordOnParentBroker)
    }

    func testProfileMatchInit_whenMultipleParentJobsHaveSubmissions_thenChildUsesMostRecent() {

        // Given — three parent opt-outs, two with submissions on different dates, one without.
        // The fallback should pick the most recent submission across all parent jobs.
        let extractedProfile = ExtractedProfile.mockWithName("Steve Jones", age: "20", addresses: [AddressCityState(city: "New York", state: "NY")])
        let parentA = ExtractedProfile.mockWithName("Adam P Smith", age: "46", addresses: [AddressCityState(city: "San Diego", state: "CA")])
        let parentB = ExtractedProfile.mockWithName("Adam M Smith", age: "48", addresses: [AddressCityState(city: "San Diego", state: "CA")])
        let parentC = ExtractedProfile.mockWithName("Adam O Smith", age: "50", addresses: [AddressCityState(city: "San Diego", state: "CA")])

        let oldSubmission = Calendar.current.date(byAdding: .day, value: -10, to: Date.now)!
        let recentSubmission = Calendar.current.date(byAdding: .day, value: -2, to: Date.now)!

        let childOptOut = OptOutJobData.mock(with: extractedProfile, historyEvents: [])
        let parentOptOutA = OptOutJobData.mock(
            with: parentA,
            historyEvents: [HistoryEvent(extractedProfileId: 0, brokerId: 0, profileQueryId: 0, type: .optOutRequested, date: oldSubmission)]
        )
        let parentOptOutB = OptOutJobData.mock(
            with: parentB,
            historyEvents: [HistoryEvent(extractedProfileId: 0, brokerId: 0, profileQueryId: 0, type: .optOutSubmittedAndAwaitingEmailConfirmation, date: recentSubmission)]
        )
        let parentOptOutC = OptOutJobData.mock(with: parentC, historyEvents: [])

        // When
        let profileMatch = DBPUIDataBrokerProfileMatch(optOutJobData: childOptOut,
                                                       dataBroker: makeUIBroker(parentURL: "parent.com"),
                                                       parentBrokerOptOutJobData: [parentOptOutA, parentOptOutB, parentOptOutC])

        // Then
        XCTAssertEqual(profileMatch.optOutFormSubmittedDate, recentSubmission.timeIntervalSince1970)
    }

    func testProfileMatchInit_whenAllParentJobsAreMissingSubmissionEvents_thenOptOutFormSubmittedDateIsNil() {

        // Given — parent has opt-outs but none reached a submission event (e.g. only started, or
        // failed). Broker-level fallback should resolve to nil rather than papering over the
        // missing submission.
        let extractedProfile = ExtractedProfile.mockWithName("Steve Jones", age: "20", addresses: [AddressCityState(city: "New York", state: "NY")])
        let parentProfile = ExtractedProfile.mockWithName("Adam P Smith", age: "46", addresses: [AddressCityState(city: "San Diego", state: "CA")])

        let childOptOut = OptOutJobData.mock(with: extractedProfile, historyEvents: [])
        let parentOptOut = OptOutJobData.mock(
            with: parentProfile,
            historyEvents: [HistoryEvent(extractedProfileId: 0, brokerId: 0, profileQueryId: 0, type: .optOutStarted, date: Date.now)]
        )

        // When
        let profileMatch = DBPUIDataBrokerProfileMatch(optOutJobData: childOptOut,
                                                       dataBroker: makeUIBroker(parentURL: "parent.com"),
                                                       parentBrokerOptOutJobData: [parentOptOut])

        // Then
        XCTAssertNil(profileMatch.optOutFormSubmittedDate)
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

//
//  CodableRoundTripTests.swift
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

import XCTest
import DataBrokerProtectionCore
@testable import PIRDebugKit

final class CodableRoundTripTests: XCTestCase {

    // MARK: - DebugProfile

    func testDebugProfileRoundTrip() throws {
        let profile = DebugProfile(
            names: [.init(firstName: "John", middleName: "Q", lastName: "Smith"),
                    .init(firstName: "Jane", lastName: "Doe")],
            addresses: [.init(city: "Dallas", state: "TX")],
            phones: ["555-1234"],
            birthYear: 1960)

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(DebugProfile.self, from: data)
        XCTAssertEqual(profile, decoded)
    }

    func testDebugProfileDecodesFromDocumentedShape() throws {
        let json = """
        {
          "names": [{ "firstName": "John", "middleName": "Q", "lastName": "Smith" }],
          "addresses": [{ "city": "Dallas", "state": "TX" }],
          "phones": [],
          "birthYear": 1960
        }
        """
        let profile = try JSONDecoder().decode(DebugProfile.self, from: Data(json.utf8))
        XCTAssertEqual(profile.names.count, 1)
        XCTAssertEqual(profile.names[0].middleName, "Q")
        XCTAssertEqual(profile.addresses[0].city, "Dallas")
        XCTAssertEqual(profile.birthYear, 1960)
    }

    func testDebugProfileConversionToDataBrokerProtectionProfile() {
        let profile = DebugProfile(
            names: [.init(firstName: "John", middleName: "Q", lastName: "Smith")],
            addresses: [.init(city: "Dallas", state: "TX")],
            phones: ["555"],
            birthYear: 1960)
        let converted = profile.toDataBrokerProtectionProfile()
        XCTAssertEqual(converted.names.count, 1)
        XCTAssertEqual(converted.names[0].firstName, "John")
        XCTAssertEqual(converted.names[0].middleName, "Q")
        XCTAssertEqual(converted.addresses[0].state, "TX")
        XCTAssertEqual(converted.phones, ["555"])
        XCTAssertEqual(converted.birthYear, 1960)
    }

    // MARK: - PIRDebugEvent

    func testPIRDebugEventRoundTripWithISO8601Timestamp() throws {
        let event = PIRDebugEvent(timestamp: Date(timeIntervalSince1970: 1_700_000_000.5),
                                  profileQueryLabel: "John Smith x Dallas TX",
                                  kind: .actionResponse,
                                  actionType: "extract",
                                  details: "some details")
        let data = try JSONEncoder().encode(event)
        // Timestamp is serialized as an ISO-8601 string.
        let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertTrue(jsonObject?["timestamp"] is String)

        let decoded = try JSONDecoder().decode(PIRDebugEvent.self, from: data)
        XCTAssertEqual(decoded.profileQueryLabel, event.profileQueryLabel)
        XCTAssertEqual(decoded.kind, .actionResponse)
        XCTAssertEqual(decoded.actionType, "extract")
        XCTAssertEqual(decoded.details, "some details")
        XCTAssertEqual(decoded.timestamp.timeIntervalSince1970, event.timestamp.timeIntervalSince1970, accuracy: 0.001)
    }

    // MARK: - Result types

    func testPIRScanResultRoundTrip() throws {
        let extracted = ExtractedProfile(id: 42, name: "John Smith", profileUrl: "http://x/1", age: "60")
        let record = PIRExtractedProfileRecord(brokerId: 1, profileQueryId: 2,
                                               profileQueryLabel: "L", extractedProfile: extracted)
        let result = PIRScanResult(
            brokerName: "DDG Fake Broker",
            brokerURL: "fakebroker.com",
            brokerVersion: "1.0.0",
            brokerId: 1,
            queryStatuses: [.init(profileQueryId: 2, profileQueryLabel: "L", outcome: .matches, extractedProfileCount: 1, error: nil)],
            extractedProfiles: [record],
            duration: 3.5,
            eventCount: 7)

        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(PIRScanResult.self, from: data)
        XCTAssertEqual(decoded, result)
        XCTAssertEqual(decoded.extractedProfiles.first?.extractedProfile.id, 42)
    }

    func testPIROptOutResultRoundTrip() throws {
        let result = PIROptOutResult(
            brokerName: "DDG Fake Broker",
            brokerURL: "fakebroker.com",
            brokerVersion: "1.0.0",
            brokerId: 1,
            profileQueryId: 2,
            profileQueryLabel: "L",
            extractedProfileId: 42,
            lastStage: "Waiting 1.0s (between actions)",
            success: false,
            awaitingEmailConfirmation: true,
            error: nil,
            duration: 2.0,
            eventCount: 4)

        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(PIROptOutResult.self, from: data)
        XCTAssertEqual(decoded, result)
    }
}

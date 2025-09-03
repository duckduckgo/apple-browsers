//
//  MapperToModelTests+OptOutEmailConfirmationDB.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
@testable import DataBrokerProtectionCore

final class MapperOptOutEmailConfirmationTests: XCTestCase {

    private var mapperToDB = MapperToDB { data in
        String(data: data, encoding: .utf8)!.rot13().data(using: .utf8)!
    }

    private var mapperToModel = MapperToModel { data in
        String(data: data, encoding: .utf8)!.rot13().data(using: .utf8)!
    }

    func testMappingCompleteOptOutEmailConfirmation() throws {
        let original = OptOutEmailConfirmationJobData(
            brokerId: 123,
            profileQueryId: 456,
            extractedProfileId: 789,
            generatedEmail: "test@example.com",
            attemptID: "attempt-123",
            emailConfirmationLink: "https://confirm.example.com/token",
            emailConfirmationLinkObtainedOnBEDate: Date(),
            emailConfirmationAttemptCount: 3
        )

        let dbModel = try mapperToDB.mapToDB(original)
        XCTAssertEqual(dbModel.brokerId, original.brokerId)
        XCTAssertEqual(dbModel.profileQueryId, original.profileQueryId)
        XCTAssertEqual(dbModel.extractedProfileId, original.extractedProfileId)
        XCTAssertEqual(String(data: dbModel.generatedEmail, encoding: .utf8), "grfg@rknzcyr.pbz")
        XCTAssertEqual(dbModel.attemptID, original.attemptID)
        XCTAssertEqual(String(data: dbModel.emailConfirmationLink!, encoding: .utf8), "uggcf://pbasvez.rknzcyr.pbz/gbxra")
        XCTAssertEqual(dbModel.emailConfirmationLinkObtainedOnBEDate, original.emailConfirmationLinkObtainedOnBEDate)
        XCTAssertEqual(dbModel.emailConfirmationAttemptCount, original.emailConfirmationAttemptCount)

        let result = try mapperToModel.mapToModel(dbModel)
        XCTAssertEqual(result.brokerId, original.brokerId)
        XCTAssertEqual(result.profileQueryId, original.profileQueryId)
        XCTAssertEqual(result.extractedProfileId, original.extractedProfileId)
        XCTAssertEqual(result.generatedEmail, original.generatedEmail)
        XCTAssertEqual(result.attemptID, original.attemptID)
        XCTAssertEqual(result.emailConfirmationLink, original.emailConfirmationLink)
        XCTAssertEqual(result.emailConfirmationLinkObtainedOnBEDate, original.emailConfirmationLinkObtainedOnBEDate)
        XCTAssertEqual(result.emailConfirmationAttemptCount, original.emailConfirmationAttemptCount)
    }

    func testMappingOptOutEmailConfirmation_withoutEmailConfirmationLink() throws {
        let original = OptOutEmailConfirmationJobData(
            brokerId: 123,
            profileQueryId: 456,
            extractedProfileId: 789,
            generatedEmail: "test@example.com",
            attemptID: "attempt-123",
            emailConfirmationLink: nil,
            emailConfirmationLinkObtainedOnBEDate: nil,
            emailConfirmationAttemptCount: 0
        )

        let dbModel = try mapperToDB.mapToDB(original)
        XCTAssertNil(dbModel.emailConfirmationLink)

        let result = try mapperToModel.mapToModel(dbModel)
        XCTAssertEqual(result.generatedEmail, original.generatedEmail)
        XCTAssertNil(result.emailConfirmationLink)
        XCTAssertNil(result.emailConfirmationLinkObtainedOnBEDate)
    }
}

extension String {
    func rot13() -> String {
        let uppercase = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        let lowercase = Array("abcdefghijklmnopqrstuvwxyz")

        var key = [Character: Character]()
        for i in 0 ..< 26 {
            key[uppercase[i]] = uppercase[(i + 13) % 26]
            key[lowercase[i]] = lowercase[(i + 13) % 26]
        }

        let transformed = self.map { key[$0] ?? $0 }
        return String(transformed)
    }
}

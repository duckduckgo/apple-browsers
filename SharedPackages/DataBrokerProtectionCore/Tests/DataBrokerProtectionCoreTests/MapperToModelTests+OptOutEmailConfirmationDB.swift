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
        ROT13.string(String(data: data, encoding: .utf8)!).data(using: .utf8)!
    }

    private var mapperToModel = MapperToModel { data in
        ROT13.string(String(data: data, encoding: .utf8)!).data(using: .utf8)!
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

/// From: https://www.hackingwithswift.com/example-code/strings/how-to-calculate-the-rot13-of-a-string
struct ROT13 {
    // create a dictionary that will store our character mapping
    private static var key = [Character: Character]()

    // create arrays of all uppercase and lowercase letters
    private static let uppercase = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    private static let lowercase = Array("abcdefghijklmnopqrstuvwxyz")

    static func string(_ string: String) -> String {
        // if this is the first time the method is being called, calculate the ROT13 key dictionary
        if ROT13.key.isEmpty {
            for i in 0 ..< 26 {
                ROT13.key[ROT13.uppercase[i]] = ROT13.uppercase[(i + 13) % 26]
                ROT13.key[ROT13.lowercase[i]] = ROT13.lowercase[(i + 13) % 26]
            }
        }

        // now return the transformed string
        let transformed = string.map { ROT13.key[$0] ?? $0 }
        return String(transformed)
    }
}

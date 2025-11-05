//
//  OptOutEmailConfirmationJobData.swift
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

import Foundation

public struct OptOutEmailConfirmationJobData: Sendable {
    public let brokerId: Int64
    public let profileQueryId: Int64
    public let extractedProfileId: Int64
    public let generatedEmail: String
    public let attemptID: String
    public let emailConfirmationLink: String?
    public let emailConfirmationLinkObtainedOnBEDate: Date?
    public let emailConfirmationAttemptCount: Int64

    public init(
        brokerId: Int64,
        profileQueryId: Int64,
        extractedProfileId: Int64,
        generatedEmail: String,
        attemptID: String,
        emailConfirmationLink: String? = nil,
        emailConfirmationLinkObtainedOnBEDate: Date? = nil,
        emailConfirmationAttemptCount: Int64 = 0
    ) {
        self.brokerId = brokerId
        self.profileQueryId = profileQueryId
        self.extractedProfileId = extractedProfileId
        self.generatedEmail = generatedEmail
        self.attemptID = attemptID
        self.emailConfirmationLink = emailConfirmationLink
        self.emailConfirmationLinkObtainedOnBEDate = emailConfirmationLinkObtainedOnBEDate
        self.emailConfirmationAttemptCount = emailConfirmationAttemptCount
    }
}

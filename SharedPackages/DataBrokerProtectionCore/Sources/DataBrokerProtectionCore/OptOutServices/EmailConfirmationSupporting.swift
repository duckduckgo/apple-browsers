//
//  EmailConfirmationSupporting.swift
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

import Foundation

/// Abstraction for email confirmation persistence and lookup so debug flows can avoid touching the vault.
public protocol EmailConfirmationSupporting {
    func saveOptOutEmailConfirmation(profileQueryId: Int64,
                                     brokerId: Int64,
                                     extractedProfileId: Int64,
                                     generatedEmail: String,
                                     attemptID: String) throws
    func deleteOptOutEmailConfirmation(profileQueryId: Int64,
                                       brokerId: Int64,
                                       extractedProfileId: Int64) throws
    func fetchAllOptOutEmailConfirmations() throws -> [OptOutEmailConfirmationJobData]
    func fetchOptOutEmailConfirmationsAwaitingLink() throws -> [OptOutEmailConfirmationJobData]
    func fetchOptOutEmailConfirmationsWithLink() throws -> [OptOutEmailConfirmationJobData]
    func fetchIdentifiersForActiveEmailConfirmations() throws -> Set<OptOutIdentifier>
    func updateOptOutEmailConfirmationLink(_ emailConfirmationLink: String?,
                                           emailConfirmationLinkObtainedOnBEDate: Date?,
                                           profileQueryId: Int64,
                                           brokerId: Int64,
                                           extractedProfileId: Int64) throws
    func incrementOptOutEmailConfirmationAttemptCount(profileQueryId: Int64,
                                                      brokerId: Int64,
                                                      extractedProfileId: Int64) throws
    func fetchExtractedProfile(with id: Int64) throws -> (brokerId: Int64, profileQueryId: Int64, profile: ExtractedProfile)?
}

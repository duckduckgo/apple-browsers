//
//  DebugEmailConfirmationStore.swift
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

public final class DebugEmailConfirmationStore: EmailConfirmationSupporting {
    private struct Key: Hashable {
        let brokerId: Int64
        let profileQueryId: Int64
        let extractedProfileId: Int64
    }

    private let queue = DispatchQueue(label: "com.duckduckgo.dbp.debug.email-confirmation-store")
    private var confirmations: [Key: OptOutEmailConfirmationJobData] = [:]
    private var extractedProfiles: [Int64: (brokerId: Int64, profileQueryId: Int64, profile: ExtractedProfile)] = [:]
    public init() {}

    public func storeExtractedProfile(_ profile: ExtractedProfile,
                                      brokerId: Int64,
                                      profileQueryId: Int64,
                                      stableId: Int64) -> ExtractedProfile {
        queue.sync {
            let storedProfile = profile.with(id: stableId)
            if let id = storedProfile.id {
                extractedProfiles[id] = (brokerId: brokerId, profileQueryId: profileQueryId, profile: storedProfile)
            }
            return storedProfile
        }
    }

    public func saveOptOutEmailConfirmation(profileQueryId: Int64,
                                            brokerId: Int64,
                                            extractedProfileId: Int64,
                                            generatedEmail: String,
                                            attemptID: String) throws {
        queue.sync {
            let key = Key(brokerId: brokerId, profileQueryId: profileQueryId, extractedProfileId: extractedProfileId)
            confirmations[key] = OptOutEmailConfirmationJobData(brokerId: brokerId,
                                                                profileQueryId: profileQueryId,
                                                                extractedProfileId: extractedProfileId,
                                                                generatedEmail: generatedEmail,
                                                                attemptID: attemptID)
        }
    }

    public func deleteOptOutEmailConfirmation(profileQueryId: Int64,
                                              brokerId: Int64,
                                              extractedProfileId: Int64) throws {
        queue.sync {
            _ = confirmations.removeValue(forKey: Key(brokerId: brokerId,
                                                      profileQueryId: profileQueryId,
                                                      extractedProfileId: extractedProfileId))
        }
    }

    public func fetchAllOptOutEmailConfirmations() throws -> [OptOutEmailConfirmationJobData] {
        queue.sync {
            Array(confirmations.values)
        }
    }

    public func fetchOptOutEmailConfirmationsAwaitingLink() throws -> [OptOutEmailConfirmationJobData] {
        queue.sync {
            confirmations.values.filter { $0.emailConfirmationLink == nil }
        }
    }

    public func fetchOptOutEmailConfirmationsWithLink() throws -> [OptOutEmailConfirmationJobData] {
        queue.sync {
            confirmations.values.filter { $0.emailConfirmationLink != nil }
        }
    }

    public func fetchIdentifiersForActiveEmailConfirmations() throws -> Set<OptOutIdentifier> {
        queue.sync {
            Set(confirmations.values.map {
                OptOutIdentifier(brokerId: $0.brokerId, profileQueryId: $0.profileQueryId, extractedProfileId: $0.extractedProfileId)
            })
        }
    }

    public func updateOptOutEmailConfirmationLink(_ emailConfirmationLink: String?,
                                                  emailConfirmationLinkObtainedOnBEDate: Date?,
                                                  profileQueryId: Int64,
                                                  brokerId: Int64,
                                                  extractedProfileId: Int64) throws {
        queue.sync {
            let key = Key(brokerId: brokerId, profileQueryId: profileQueryId, extractedProfileId: extractedProfileId)
            guard let existing = confirmations[key] else { return }
            confirmations[key] = OptOutEmailConfirmationJobData(brokerId: existing.brokerId,
                                                                profileQueryId: existing.profileQueryId,
                                                                extractedProfileId: existing.extractedProfileId,
                                                                generatedEmail: existing.generatedEmail,
                                                                attemptID: existing.attemptID,
                                                                emailConfirmationLink: emailConfirmationLink,
                                                                emailConfirmationLinkObtainedOnBEDate: emailConfirmationLinkObtainedOnBEDate,
                                                                emailConfirmationAttemptCount: existing.emailConfirmationAttemptCount)
        }
    }

    public func incrementOptOutEmailConfirmationAttemptCount(profileQueryId: Int64,
                                                             brokerId: Int64,
                                                             extractedProfileId: Int64) throws {
        queue.sync {
            let key = Key(brokerId: brokerId, profileQueryId: profileQueryId, extractedProfileId: extractedProfileId)
            guard let existing = confirmations[key] else { return }
            confirmations[key] = OptOutEmailConfirmationJobData(brokerId: existing.brokerId,
                                                                profileQueryId: existing.profileQueryId,
                                                                extractedProfileId: existing.extractedProfileId,
                                                                generatedEmail: existing.generatedEmail,
                                                                attemptID: existing.attemptID,
                                                                emailConfirmationLink: existing.emailConfirmationLink,
                                                                emailConfirmationLinkObtainedOnBEDate: existing.emailConfirmationLinkObtainedOnBEDate,
                                                                emailConfirmationAttemptCount: existing.emailConfirmationAttemptCount + 1)
        }
    }

    public func fetchExtractedProfile(with id: Int64) throws -> (brokerId: Int64, profileQueryId: Int64, profile: ExtractedProfile)? {
        queue.sync {
            extractedProfiles[id]
        }
    }

    public func reset() {
        queue.sync {
            confirmations.removeAll()
            extractedProfiles.removeAll()
        }
    }
}

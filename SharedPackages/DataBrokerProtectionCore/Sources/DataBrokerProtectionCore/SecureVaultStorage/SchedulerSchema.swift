//
//  SchedulerSchema.swift
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

import Foundation
import BrowserServicesKit
import SecureStorage
import GRDB

public struct ProfileQueryDB: Codable {
    let id: Int64?
    let profileId: Int64
    let first: Data
    let last: Data
    let middle: Data?
    let suffix: Data?
    let city: Data
    let state: Data
    let street: Data?
    let zipCode: Data?
    let phone: Data?
    let birthYear: Data
    let deprecated: Bool
}

extension ProfileQueryDB: PersistableRecord, FetchableRecord {
    public static let databaseTableName: String = "profileQuery"

    enum Columns: String, ColumnExpression {
        case id
        case profileId
        case first
        case last
        case middle
        case suffix
        case city
        case state
        case street
        case zipCode
        case phone
        case birthYear
        case deprecated
    }

    public init(row: Row) throws {
        id = row[Columns.id]
        profileId = row[Columns.profileId]
        first = row[Columns.first]
        last = row[Columns.last]
        middle = row[Columns.middle]
        suffix = row[Columns.suffix]
        city = row[Columns.city]
        state = row[Columns.state]
        street = row[Columns.street]
        zipCode = row[Columns.zipCode]
        phone = row[Columns.phone]
        birthYear = row[Columns.birthYear]
        deprecated = row[Columns.deprecated]
    }

    public func encode(to container: inout PersistenceContainer) throws {
        container[Columns.id] = id
        container[Columns.profileId] = profileId
        container[Columns.first] = first
        container[Columns.last] = last
        container[Columns.middle] = middle
        container[Columns.suffix] = suffix
        container[Columns.city] = city
        container[Columns.state] = state
        container[Columns.street] = street
        container[Columns.zipCode] = zipCode
        container[Columns.phone] = phone
        container[Columns.birthYear] = birthYear
        container[Columns.deprecated] = deprecated
    }
}

public struct BrokerDB: Codable {
    let id: Int64?
    let name: String
    let json: Data
    let version: String
    let url: String
    let eTag: String
    let removedAt: Date?
}

extension BrokerDB: PersistableRecord, FetchableRecord {
    public static let databaseTableName: String = "broker"
    static let missingETagValue = "MISSING_ETAG_VALUE"

    enum Columns: String, ColumnExpression {
        case id
        case name
        case json
        case version
        case url
        case eTag
        case removedAt
    }

    public init(row: Row) throws {
        id = row[Columns.id]
        name = row[Columns.name]
        json = row[Columns.json]
        version = row[Columns.version]
        url = row[Columns.url]
        if row.hasColumn(Columns.eTag.rawValue) {
            eTag = row[Columns.eTag]
        } else {
            eTag = Self.missingETagValue
        }
        if row.hasColumn(Columns.removedAt.rawValue) {
            removedAt = row[Columns.removedAt]
        } else {
            removedAt = nil
        }
    }

    public func encode(to container: inout PersistenceContainer) throws {
        container[Columns.id] = id
        container[Columns.name] = name
        container[Columns.json] = json
        container[Columns.version] = version
        container[Columns.url] = url
        container[Columns.eTag] = eTag
        container[Columns.removedAt] = removedAt
    }
}

public struct ScanDB: Codable {
    let brokerId: Int64
    let profileQueryId: Int64
    var lastRunDate: Date?
    var preferredRunDate: Date?
}

extension ScanDB: PersistableRecord, FetchableRecord {
    public static let databaseTableName: String = "scan"

    static let profileQuery = belongsTo(ProfileQueryDB.self)
    static let broker = belongsTo(BrokerDB.self)

    enum Columns: String, ColumnExpression {
        case brokerId
        case profileQueryId
        case lastRunDate
        case preferredRunDate
    }

    public init(row: Row) throws {
        brokerId = row[Columns.brokerId]
        profileQueryId = row[Columns.profileQueryId]
        lastRunDate = row[Columns.lastRunDate]
        preferredRunDate = row[Columns.preferredRunDate]
    }

    public func encode(to container: inout PersistenceContainer) throws {
        container[Columns.brokerId] = brokerId
        container[Columns.profileQueryId] = profileQueryId
        container[Columns.lastRunDate] = lastRunDate
        container[Columns.preferredRunDate] = preferredRunDate
    }
}

public struct ScanHistoryEventDB: Codable {
    let brokerId: Int64
    let profileQueryId: Int64
    let event: Data
    let timestamp: Date
}

extension ScanHistoryEventDB: PersistableRecord, FetchableRecord {
    public static let databaseTableName: String = "scanHistoryEvent"

    static let profileQuery = belongsTo(ProfileQueryDB.self)
    static let broker = belongsTo(BrokerDB.self)

    enum Columns: String, ColumnExpression {
        case brokerId
        case profileQueryId
        case event
        case timestamp
    }

    public init(row: Row) throws {
        brokerId = row[Columns.brokerId]
        profileQueryId = row[Columns.profileQueryId]
        event = row[Columns.event]
        timestamp = row[Columns.timestamp]
    }

    public func encode(to container: inout PersistenceContainer) throws {
        container[Columns.brokerId] = brokerId
        container[Columns.profileQueryId] = profileQueryId
        container[Columns.event] = event
        container[Columns.timestamp] = timestamp
    }
}

public struct OptOutDB: Codable {
    let brokerId: Int64
    let profileQueryId: Int64
    let extractedProfileId: Int64

    let createdDate: Date
    var lastRunDate: Date?
    var preferredRunDate: Date?

    var attemptCount: Int64

    // This was added in a later migration (V4), so will be nil for older entries submitted before the migration
    var submittedSuccessfullyDate: Date?

    var sevenDaysConfirmationPixelFired: Bool
    var fourteenDaysConfirmationPixelFired: Bool
    var twentyOneDaysConfirmationPixelFired: Bool
}

extension OptOutDB: PersistableRecord, FetchableRecord {
    public static let databaseTableName: String = "optOut"

    static let profileQuery = belongsTo(ProfileQueryDB.self)
    static let broker = belongsTo(BrokerDB.self)
    static let extractedProfile = belongsTo(ExtractedProfileDB.self)

    var extractedProfile: QueryInterfaceRequest<ExtractedProfileDB> {
        request(for: OptOutDB.extractedProfile)
    }

    enum Columns: String, ColumnExpression {
        case brokerId
        case profileQueryId
        case extractedProfileId
        case createdDate
        case lastRunDate
        case preferredRunDate
        case attemptCount
        case submittedSuccessfullyDate
        case sevenDaysConfirmationPixelFired
        case fourteenDaysConfirmationPixelFired
        case twentyOneDaysConfirmationPixelFired
    }

    public init(row: Row) throws {
        brokerId = row[Columns.brokerId]
        profileQueryId = row[Columns.profileQueryId]
        extractedProfileId = row[Columns.extractedProfileId]
        createdDate = row[Columns.createdDate]
        lastRunDate = row[Columns.lastRunDate]
        preferredRunDate = row[Columns.preferredRunDate]
        attemptCount = row[Columns.attemptCount]
        submittedSuccessfullyDate = row[Columns.submittedSuccessfullyDate]
        sevenDaysConfirmationPixelFired = row[Columns.sevenDaysConfirmationPixelFired]
        fourteenDaysConfirmationPixelFired = row[Columns.fourteenDaysConfirmationPixelFired]
        twentyOneDaysConfirmationPixelFired = row[Columns.twentyOneDaysConfirmationPixelFired]
    }

    public func encode(to container: inout PersistenceContainer) throws {
        container[Columns.brokerId] = brokerId
        container[Columns.profileQueryId] = profileQueryId
        container[Columns.extractedProfileId] = extractedProfileId
        container[Columns.createdDate] = createdDate
        container[Columns.lastRunDate] = lastRunDate
        container[Columns.preferredRunDate] = preferredRunDate
        container[Columns.attemptCount] = attemptCount
        container[Columns.submittedSuccessfullyDate] = submittedSuccessfullyDate
        container[Columns.sevenDaysConfirmationPixelFired] = sevenDaysConfirmationPixelFired
        container[Columns.fourteenDaysConfirmationPixelFired] = fourteenDaysConfirmationPixelFired
        container[Columns.twentyOneDaysConfirmationPixelFired] = twentyOneDaysConfirmationPixelFired
    }
}

public struct OptOutHistoryEventDB: Codable {
    let brokerId: Int64
    let profileQueryId: Int64
    let extractedProfileId: Int64
    let event: Data
    let timestamp: Date
}

extension OptOutHistoryEventDB: PersistableRecord, FetchableRecord {
    public static let databaseTableName: String = "optOutHistoryEvent"

    static let profileQuery = belongsTo(ProfileQueryDB.self)
    static let broker = belongsTo(BrokerDB.self)
    static let extractedProfile = belongsTo(ExtractedProfileDB.self)

    enum Columns: String, ColumnExpression {
        case brokerId
        case profileQueryId
        case extractedProfileId
        case event
        case timestamp
    }

    public init(row: Row) throws {
        brokerId = row[Columns.brokerId]
        profileQueryId = row[Columns.profileQueryId]
        extractedProfileId = row[Columns.extractedProfileId]
        event = row[Columns.event]
        timestamp = row[Columns.timestamp]
    }

    public func encode(to container: inout PersistenceContainer) throws {
        container[Columns.brokerId] = brokerId
        container[Columns.profileQueryId] = profileQueryId
        container[Columns.extractedProfileId] = extractedProfileId
        container[Columns.event] = event
        container[Columns.timestamp] = timestamp
    }
}

public struct OptOutEmailConfirmationDB: Codable {
    let brokerId: Int64
    let profileQueryId: Int64
    let extractedProfileId: Int64
    let generatedEmail: Data
    let attemptID: String
    var emailConfirmationLink: Data?
    var emailConfirmationLinkObtainedOnBEDate: Date?
    var emailConfirmationAttemptCount: Int64
}

extension OptOutEmailConfirmationDB: PersistableRecord, FetchableRecord {
    public static let databaseTableName: String = "optOutEmailConfirmation"

    static let profileQuery = belongsTo(ProfileQueryDB.self)
    static let broker = belongsTo(BrokerDB.self)
    static let extractedProfile = belongsTo(ExtractedProfileDB.self)

    enum Columns: String, ColumnExpression {
        case brokerId
        case profileQueryId
        case extractedProfileId
        case generatedEmail
        case attemptID
        case emailConfirmationLink
        case emailConfirmationLinkObtainedOnBEDate
        case emailConfirmationAttemptCount
    }

    public init(row: Row) throws {
        brokerId = row[Columns.brokerId]
        profileQueryId = row[Columns.profileQueryId]
        extractedProfileId = row[Columns.extractedProfileId]
        generatedEmail = row[Columns.generatedEmail]
        attemptID = row[Columns.attemptID]
        emailConfirmationLink = row[Columns.emailConfirmationLink]
        emailConfirmationLinkObtainedOnBEDate = row[Columns.emailConfirmationLinkObtainedOnBEDate]
        emailConfirmationAttemptCount = row[Columns.emailConfirmationAttemptCount]
    }

    public func encode(to container: inout PersistenceContainer) throws {
        container[Columns.brokerId] = brokerId
        container[Columns.profileQueryId] = profileQueryId
        container[Columns.extractedProfileId] = extractedProfileId
        container[Columns.generatedEmail] = generatedEmail
        container[Columns.attemptID] = attemptID
        container[Columns.emailConfirmationLink] = emailConfirmationLink
        container[Columns.emailConfirmationLinkObtainedOnBEDate] = emailConfirmationLinkObtainedOnBEDate
        container[Columns.emailConfirmationAttemptCount] = emailConfirmationAttemptCount
    }
}

public struct ExtractedProfileDB: Codable {
    let id: Int64?
    let brokerId: Int64
    let profileQueryId: Int64
    let profile: Data // Stored as Data JSON
    var removedDate: Date?
}

extension ExtractedProfileDB: PersistableRecord, FetchableRecord {
    public static let databaseTableName: String = "extractedProfile"

    static let profileQuery = belongsTo(ProfileQueryDB.self)
    static let broker = belongsTo(BrokerDB.self)

    enum Columns: String, ColumnExpression {
        case id
        case brokerId
        case profileQueryId
        case profile
        case removedDate
    }

    public init(row: Row) throws {
        id = row[Columns.id]
        brokerId = row[Columns.brokerId]
        profileQueryId = row[Columns.profileQueryId]
        profile = row[Columns.profile]
        removedDate = row[Columns.removedDate]
    }

    public func encode(to container: inout PersistenceContainer) throws {
        container[Columns.id] = id
        container[Columns.brokerId] = brokerId
        container[Columns.profileQueryId] = profileQueryId
        container[Columns.profile] = profile
        container[Columns.removedDate] = removedDate
    }
}

public struct OptOutAttemptDB: Codable {
    let extractedProfileId: Int64
    let dataBroker: String
    var attemptId: String
    var lastStageDate: Date
    var startDate: Date
}

extension OptOutAttemptDB: PersistableRecord, FetchableRecord {
    public static let databaseTableName: String = "optOutAttempt"

    static let extractedProfile = belongsTo(ExtractedProfileDB.self)

    enum Columns: String, ColumnExpression {
        case extractedProfileId
        case dataBroker
        case attemptId
        case lastStageDate
        case startDate
    }

    public init(row: Row) throws {
        extractedProfileId = row[Columns.extractedProfileId]
        dataBroker = row[Columns.dataBroker]
        attemptId = row[Columns.attemptId]
        lastStageDate = row[Columns.lastStageDate]
        startDate = row[Columns.startDate]
    }

    public func encode(to container: inout PersistenceContainer) throws {
        container[Columns.extractedProfileId] = extractedProfileId
        container[Columns.dataBroker] = dataBroker
        container[Columns.attemptId] = attemptId
        container[Columns.lastStageDate] = lastStageDate
        container[Columns.startDate] = startDate
    }
}

public struct BackgroundTaskEventDB: Codable {
    let id: Int64?
    public let sessionId: String
    public let eventType: String
    public let timestamp: Date
    public let metadata: Data?
}

extension BackgroundTaskEventDB: PersistableRecord, FetchableRecord {
    public static let databaseTableName: String = "backgroundTaskEvent"

    enum Columns: String, ColumnExpression {
        case id
        case sessionId
        case eventType
        case timestamp
        case metadata
    }

    public init(row: Row) throws {
        id = row[Columns.id]
        sessionId = row[Columns.sessionId]
        eventType = row[Columns.eventType]
        timestamp = row[Columns.timestamp]
        metadata = row[Columns.metadata]
    }

    public func encode(to container: inout PersistenceContainer) throws {
        container[Columns.id] = id
        container[Columns.sessionId] = sessionId
        container[Columns.eventType] = eventType
        container[Columns.timestamp] = timestamp
        container[Columns.metadata] = metadata
    }
}

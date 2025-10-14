//
//  SecureVaultModels+Sync.swift
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

import Common
import Foundation
import GRDB

public protocol SecureVaultSyncable {
    var uuid: String { get set }
    var objectId: Int64? { get }
    var lastModified: Date? { get set }
}

public enum SecureVaultSyncableColumns: String, ColumnExpression {
    case id, uuid, objectId, lastModified
}

extension SecureVaultModels {

    /**
     * Convenience struct representing Website Credentials including its respective Account information and Sync metadata.
     *
     * This is the main data object used by Sync for credentials.
     */
    public struct SyncableCredentials: FetchableRecord, Decodable {
        public var metadata: SyncableCredentialsRecord
        public var account: WebsiteAccount? {
            didSet {
                metadata.objectId = account?.id.flatMap(Int64.init)
            }
        }
        public var credentialsRecord: WebsiteCredentialsRecord? {
            didSet {
                metadata.objectId = account?.id.flatMap(Int64.init)
            }
        }

        public var credentials: WebsiteCredentials? {
            get {
                guard let account else {
                    return nil
                }
                return .init(account: account, password: credentialsRecord?.password)
            }
            set {
                credentialsRecord = newValue.flatMap { WebsiteCredentialsRecord(credentials: $0) }
                account = newValue?.account
            }
        }

        public init(uuid: String = UUID().uuidString, credentials: WebsiteCredentials?, lastModified: Date? = Date()) {
            metadata = .init(uuid: uuid, objectId: credentials?.account.id.flatMap(Int64.init), lastModified: lastModified)
            self.credentials = credentials
        }

        static public var query: QueryInterfaceRequest<SyncableCredentials> {
            SecureVaultModels.SyncableCredentialsRecord
                .including(optional: SecureVaultModels.SyncableCredentialsRecord.account)
                .including(optional: SecureVaultModels.SyncableCredentialsRecord.credentials)
                .asRequest(of: SecureVaultModels.SyncableCredentials.self)
                .order(SecureVaultModels.SyncableCredentialsRecord.Columns.uuid)
        }
    }

    /**
     * Struct representing database entity for Sync-related Website Credentials metadata (uuid and modification timestamp),
     * with optional reference to the associated Account and Credentials objects.
     */
    public struct SyncableCredentialsRecord: SecureVaultSyncable, TableRecord, FetchableRecord, PersistableRecord, Decodable {
        public typealias Columns = SecureVaultSyncableColumns
        public static var databaseTableName: String = "website_accounts_sync_metadata"

        public static let accountForeignKey = ForeignKey([Columns.objectId])
        public static let credentialsForeignKey = ForeignKey([Columns.objectId])
        public static let account = belongsTo(SecureVaultModels.WebsiteAccount.self, key: "account", using: accountForeignKey)
        public static let credentials = belongsTo(SecureVaultModels.WebsiteCredentialsRecord.self,
                                                  key: "credentialsRecord",
                                                  using: credentialsForeignKey)

        public var uuid: String
        public var objectId: Int64?
        public var lastModified: Date?

        /// Marked private because it's not used by application logic.
        private var id: Int64?

        public init(row: Row) throws {
            id = row[Columns.id]
            uuid = row[Columns.uuid]
            objectId = row[Columns.objectId]
            lastModified = row[Columns.lastModified]
        }

        public func encode(to container: inout PersistenceContainer) {
            container[Columns.id] = id
            container[Columns.uuid] = uuid
            container[Columns.objectId] = objectId
            container[Columns.lastModified] = lastModified
        }

        public init(uuid: String = UUID().uuidString, objectId: Int64?, lastModified: Date? = Date()) {
            self.uuid = uuid
            self.objectId = objectId
            self.lastModified = lastModified
        }
    }

    /**
     * Struct representing Website Credentials as stored in the database (as opposed to `WebsiteCredentials`
     * which has `account` instead of ID and as such it can't be fetched directly from the database using GRDB API).
     */
    public struct WebsiteCredentialsRecord: FetchableRecord, PersistableRecord, TableRecord, Decodable {

        public typealias Columns = WebsiteCredentials.Columns
        public static let databaseTableName: String = WebsiteCredentials.databaseTableName
        public static let accountForeignKey = ForeignKey([Columns.id])
        public static let account = belongsTo(SecureVaultModels.WebsiteAccount.self, key: "account", using: accountForeignKey)

        public var id: Int64?
        public var password: Data?

        public init(row: Row) throws {
            id = row[Columns.id]
            password = row[Columns.password]
        }

        public func encode(to container: inout PersistenceContainer) throws {
            assert(id != nil, "Account ID must not be nil")
            container[Columns.id] = id
            container[Columns.password] = password
        }

        enum CodingKeys: String, CodingKey {
            case id, password
        }

        public init(credentials: WebsiteCredentials) {
            self.id = credentials.account.id.flatMap(Int64.init)
            self.password = credentials.password
        }
    }

    // MARK: - SyncableCreditCard

    /**
     * Convenience struct representing Credit Card including its Sync metadata.
     *
     * This is the main data object used by Sync for credit cards.
     */
    public struct SyncableCreditCard: FetchableRecord, Decodable {
        public var metadata: SyncableCreditCardsRecord
        public var creditCard: CreditCard? {
            didSet {
                metadata.objectId = creditCard?.id.flatMap(Int64.init)
            }
        }

        public init(uuid: String = UUID().uuidString, creditCard: CreditCard?, lastModified: Date? = Date()) {
            metadata = .init(uuid: uuid, objectId: creditCard?.id.flatMap(Int64.init), lastModified: lastModified)
            self.creditCard = creditCard
        }

        static public var query: QueryInterfaceRequest<SyncableCreditCard> {
            SecureVaultModels.SyncableCreditCardsRecord
                .including(optional: SecureVaultModels.SyncableCreditCardsRecord.creditCard)
                .asRequest(of: SecureVaultModels.SyncableCreditCard.self)
                .order(SecureVaultModels.SyncableCreditCardsRecord.Columns.uuid)
        }
    }

    /**
     * Struct representing database entity for Sync-related Credit Card metadata (uuid and modification timestamp),
     * with optional reference to the associated Credit Card object.
     */
    public struct SyncableCreditCardsRecord: SecureVaultSyncable, TableRecord, FetchableRecord, PersistableRecord, Decodable {
        public typealias Columns = SecureVaultSyncableColumns
        public static var databaseTableName: String = "credit_cards_sync_metadata"

        public static let creditCardForeignKey = ForeignKey([Columns.objectId])
        public static let creditCard = belongsTo(SecureVaultModels.CreditCard.self, key: "creditCard", using: creditCardForeignKey)

        public var uuid: String
        public var objectId: Int64?
        public var lastModified: Date?

        /// Marked private because it's not used by application logic.
        private var id: Int64?

        public init(row: Row) throws {
            id = row[Columns.id]
            uuid = row[Columns.uuid]
            objectId = row[Columns.objectId]
            lastModified = row[Columns.lastModified]
        }

        public func encode(to container: inout PersistenceContainer) {
            container[Columns.id] = id
            container[Columns.uuid] = uuid
            container[Columns.objectId] = objectId
            container[Columns.lastModified] = lastModified
        }

        public init(uuid: String = UUID().uuidString, objectId: Int64?, lastModified: Date? = Date()) {
            self.uuid = uuid
            self.objectId = objectId
            self.lastModified = lastModified
        }
    }

    // MARK: - SyncableIdentity

    /**
     * Convenience struct representing Identity including its Sync metadata.
     *
     * This is the main data object used by Sync for identities.
     */
    public struct SyncableIdentity: FetchableRecord, Decodable {
        public var metadata: SyncableIdentitiesRecord
        public var identity: Identity? {
            didSet {
                metadata.objectId = identity?.id.flatMap(Int64.init)
            }
        }

        public init(uuid: String = UUID().uuidString, identity: Identity?, lastModified: Date? = Date()) {
            metadata = .init(uuid: uuid, objectId: identity?.id.flatMap(Int64.init), lastModified: lastModified)
            self.identity = identity
        }

        static public var query: QueryInterfaceRequest<SyncableIdentity> {
            SecureVaultModels.SyncableIdentitiesRecord
                .including(optional: SecureVaultModels.SyncableIdentitiesRecord.identity)
                .asRequest(of: SecureVaultModels.SyncableIdentity.self)
                .order(SecureVaultModels.SyncableIdentitiesRecord.Columns.uuid)
        }
    }

    /**
     * Struct representing database entity for Sync-related Identity metadata (uuid and modification timestamp),
     * with optional reference to the associated Identity object.
     */
    public struct SyncableIdentitiesRecord: SecureVaultSyncable, TableRecord, FetchableRecord, PersistableRecord, Decodable {
        public typealias Columns = SecureVaultSyncableColumns
        public static var databaseTableName: String = "identities_sync_metadata"

        public static let identityForeignKey = ForeignKey([Columns.objectId])
        public static let identity = belongsTo(SecureVaultModels.Identity.self, key: "identity", using: identityForeignKey)

        public var uuid: String
        public var objectId: Int64?
        public var lastModified: Date?

        /// Marked private because it's not used by application logic.
        private var id: Int64?

        public init(row: Row) throws {
            id = row[Columns.id]
            uuid = row[Columns.uuid]
            objectId = row[Columns.objectId]
            lastModified = row[Columns.lastModified]
        }

        public func encode(to container: inout PersistenceContainer) {
            container[Columns.id] = id
            container[Columns.uuid] = uuid
            container[Columns.objectId] = objectId
            container[Columns.lastModified] = lastModified
        }

        public init(uuid: String = UUID().uuidString, objectId: Int64?, lastModified: Date? = Date()) {
            self.uuid = uuid
            self.objectId = objectId
            self.lastModified = lastModified
        }
    }
}

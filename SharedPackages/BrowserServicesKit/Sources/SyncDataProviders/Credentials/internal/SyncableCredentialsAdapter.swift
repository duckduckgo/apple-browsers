//
//  SyncableCredentialsAdapter.swift
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

import BrowserServicesKit
import DDGSync
import Foundation

struct SyncableCredentialsAdapter {

    let syncable: Syncable

    init(syncable: Syncable) {
        self.syncable = syncable
    }

    var uuid: String? {
        syncable.payload["id"] as? String
    }

    var isDeleted: Bool {
        syncable.isDeleted
    }

    var encryptedDomain: String? {
        syncable.payload["domain"] as? String
    }

    var encryptedTitle: String? {
        syncable.payload["title"] as? String
    }

    var encryptedUsername: String? {
        syncable.payload["username"] as? String
    }

    var encryptedPassword: String? {
        syncable.payload["password"] as? String
    }

    var encryptedNotes: String? {
        syncable.payload["notes"] as? String
    }
}

extension Syncable {

    enum SyncableCredentialError: Error {
        case validationFailed
    }

    enum CredentialValidationConstraints {
        static let maxEncryptedTitleLength = 3000
        static let maxEncryptedDomainLength = 1000
        static let maxEncryptedUsernameLength = 1000
        static let maxEncryptedPasswordLength = 1000
        static let maxEncryptedNotesLength = 1000
    }

    // swiftlint:disable:next cyclomatic_complexity
    init(syncableCredentials: SecureVaultModels.SyncableCredentials, encryptedUsing encrypt: (String) throws -> String) throws {
        var payload: [String: Any] = [:]

        payload["id"] = syncableCredentials.metadata.uuid

        guard let credential = syncableCredentials.credentials else {
            payload["deleted"] = ""
            self.init(jsonObject: payload)
            return
        }

        if let title = credential.account.title {
            let encryptedTitle = try encrypt(title)
            guard encryptedTitle.count <= CredentialValidationConstraints.maxEncryptedTitleLength else {
                throw SyncableCredentialError.validationFailed
            }
            payload["title"] = encryptedTitle
        }
        if let domain = credential.account.domain {
            let encryptedDomain = try encrypt(domain)
            guard encryptedDomain.count <= CredentialValidationConstraints.maxEncryptedDomainLength else {
                throw SyncableCredentialError.validationFailed
            }
            payload["domain"] = encryptedDomain
        }
        if let username = credential.account.username {
            let encryptedUsername = try encrypt(username)
            guard encryptedUsername.count <= CredentialValidationConstraints.maxEncryptedUsernameLength else {
                throw SyncableCredentialError.validationFailed
            }
            payload["username"] = encryptedUsername
        }
        if let notes = credential.account.notes {
            let encryptedNotes = try encrypt(notes)
            guard encryptedNotes.count <= CredentialValidationConstraints.maxEncryptedNotesLength else {
                throw SyncableCredentialError.validationFailed
            }
            payload["notes"] = encryptedNotes
        }

        if let passwordData = credential.password, let password = String(data: passwordData, encoding: .utf8) {
            let encryptedPassword = try encrypt(password)
            guard encryptedPassword.count <= CredentialValidationConstraints.maxEncryptedPasswordLength else {
                throw SyncableCredentialError.validationFailed
            }
            payload["password"] = encryptedPassword
        }

        if let modifiedAt = syncableCredentials.metadata.lastModified {
            payload["client_last_modified"] = Self.dateFormatter.string(from: modifiedAt)
        }
        self.init(jsonObject: payload)
    }

    private static var dateFormatter: ISO8601DateFormatter {
        ISO8601DateFormatter()
    }
}

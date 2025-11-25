//
//  SyncableIdentitiesAdapter.swift
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

import BrowserServicesKit
import DDGSync
import Foundation

struct SyncableIdentitiesAdapter {

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

    var encryptedTitle: String? {
        syncable.payload["title"] as? String
    }

    var encryptedFirstName: String? {
        syncable.payload["first_name"] as? String
    }

    var encryptedMiddleName: String? {
        syncable.payload["middle_name"] as? String
    }

    var encryptedLastName: String? {
        syncable.payload["last_name"] as? String
    }

    var encryptedBirthday: String? {
        syncable.payload["birthday"] as? String
    }

    var encryptedPhone: String? {
        syncable.payload["phone"] as? String
    }

    var encryptedEmailAddress: String? {
        syncable.payload["email_address"] as? String
    }

    var encryptedAddress: [String: Any]? {
        syncable.payload["address"] as? [String: Any]
    }

    var encryptedAddressStreet: String? {
        encryptedAddress?["street"] as? String
    }

    var encryptedAddressStreet2: String? {
        encryptedAddress?["street2"] as? String
    }

    var encryptedAddressCity: String? {
        encryptedAddress?["city"] as? String
    }

    var encryptedAddressProvince: String? {
        encryptedAddress?["province"] as? String
    }

    var encryptedAddressPostalCode: String? {
        encryptedAddress?["postal_code"] as? String
    }

    var encryptedAddressCountryCode: String? {
        encryptedAddress?["country_code"] as? String
    }
}

extension Syncable {

    enum SyncableIdentityError: Error {
        case validationFailed
    }

    enum IdentitiesValidationConstraints {
        static let maxEncryptedTitleLength = 3000
        static let maxEncryptedFirstNameLength = 1000
        static let maxEncryptedMiddleNameLength = 1000
        static let maxEncryptedLastNameLength = 1000
        static let maxEncryptedBirthdayLength = 100
        static let maxEncryptedStreetLength = 1000
        static let maxEncryptedStreet2Length = 1000
        static let maxEncryptedCityLength = 1000
        static let maxEncryptedProvinceLength = 1000
        static let maxEncryptedPostalCodeLength = 1000
        static let maxEncryptedCountryCodeLength = 100
        static let maxEncryptedPhoneLength = 500
        static let maxEncryptedEmailAddressLength = 1000
    }

    // swiftlint:disable:next cyclomatic_complexity
    init(syncableIdentity: SecureVaultModels.SyncableIdentity, encryptedUsing encrypt: (String) throws -> String) throws {
        var payload: [String: Any] = [:]

        payload["id"] = syncableIdentity.metadata.uuid

        guard let identity = syncableIdentity.identity else {
            payload["deleted"] = ""
            self.init(jsonObject: payload)
            return
        }

        if !identity.title.isEmpty {
            let encryptedTitle = try encrypt(identity.title)
            guard encryptedTitle.count <= IdentitiesValidationConstraints.maxEncryptedTitleLength else {
                throw SyncableIdentityError.validationFailed
            }
            payload["title"] = encryptedTitle
        }

        if let firstName = identity.firstName {
            let encryptedFirstName = try encrypt(firstName)
            guard encryptedFirstName.count <= IdentitiesValidationConstraints.maxEncryptedFirstNameLength else {
                throw SyncableIdentityError.validationFailed
            }
            payload["first_name"] = encryptedFirstName
        }

        if let middleName = identity.middleName {
            let encryptedMiddleName = try encrypt(middleName)
            guard encryptedMiddleName.count <= IdentitiesValidationConstraints.maxEncryptedMiddleNameLength else {
                throw SyncableIdentityError.validationFailed
            }
            payload["middle_name"] = encryptedMiddleName
        }

        if let lastName = identity.lastName {
            let encryptedLastName = try encrypt(lastName)
            guard encryptedLastName.count <= IdentitiesValidationConstraints.maxEncryptedLastNameLength else {
                throw SyncableIdentityError.validationFailed
            }
            payload["last_name"] = encryptedLastName
        }

        if let day = identity.birthdayDay,
           let month = identity.birthdayMonth,
           let year = identity.birthdayYear {
            let birthday = String(format: "%04d-%02d-%02d", year, month, day)
            let encryptedBirthday = try encrypt(birthday)
            guard encryptedBirthday.count <= IdentitiesValidationConstraints.maxEncryptedBirthdayLength else {
                throw SyncableIdentityError.validationFailed
            }
            payload["birthday"] = encryptedBirthday
        }

        if let phone = identity.homePhone {
            let encryptedPhone = try encrypt(phone)
            guard encryptedPhone.count <= IdentitiesValidationConstraints.maxEncryptedPhoneLength else {
                throw SyncableIdentityError.validationFailed
            }
            payload["phone"] = encryptedPhone
        }

        if let emailAddress = identity.emailAddress {
            let encryptedEmailAddress = try encrypt(emailAddress)
            guard encryptedEmailAddress.count <= IdentitiesValidationConstraints.maxEncryptedEmailAddressLength else {
                throw SyncableIdentityError.validationFailed
            }
            payload["email_address"] = encryptedEmailAddress
        }

        var hasAddress = false
        var addressPayload: [String: Any] = [:]

        if let street = identity.addressStreet {
            let encryptedStreet = try encrypt(street)
            guard encryptedStreet.count <= IdentitiesValidationConstraints.maxEncryptedStreetLength else {
                throw SyncableIdentityError.validationFailed
            }
            addressPayload["street"] = encryptedStreet
            hasAddress = true
        }

        if let street2 = identity.addressStreet2 {
            let encryptedStreet2 = try encrypt(street2)
            guard encryptedStreet2.count <= IdentitiesValidationConstraints.maxEncryptedStreet2Length else {
                throw SyncableIdentityError.validationFailed
            }
            addressPayload["street2"] = encryptedStreet2
            hasAddress = true
        }

        if let city = identity.addressCity {
            let encryptedCity = try encrypt(city)
            guard encryptedCity.count <= IdentitiesValidationConstraints.maxEncryptedCityLength else {
                throw SyncableIdentityError.validationFailed
            }
            addressPayload["city"] = encryptedCity
            hasAddress = true
        }

        if let province = identity.addressProvince {
            let encryptedProvince = try encrypt(province)
            guard encryptedProvince.count <= IdentitiesValidationConstraints.maxEncryptedProvinceLength else {
                throw SyncableIdentityError.validationFailed
            }
            addressPayload["province"] = encryptedProvince
            hasAddress = true
        }

        if let postalCode = identity.addressPostalCode {
            let encryptedPostalCode = try encrypt(postalCode)
            guard encryptedPostalCode.count <= IdentitiesValidationConstraints.maxEncryptedPostalCodeLength else {
                throw SyncableIdentityError.validationFailed
            }
            addressPayload["postal_code"] = encryptedPostalCode
            hasAddress = true
        }

        if let countryCode = identity.addressCountryCode {
            let encryptedCountryCode = try encrypt(countryCode)
            guard encryptedCountryCode.count <= IdentitiesValidationConstraints.maxEncryptedCountryCodeLength else {
                throw SyncableIdentityError.validationFailed
            }
            addressPayload["country_code"] = encryptedCountryCode
            hasAddress = true
        }

        if hasAddress {
            payload["address"] = addressPayload
        }

        if let modifiedAt = syncableIdentity.metadata.lastModified {
            payload["client_last_modified"] = Self.dateFormatter.string(from: modifiedAt)
        }
        self.init(jsonObject: payload)
    }

    private static var dateFormatter: ISO8601DateFormatter {
        ISO8601DateFormatter()
    }
}

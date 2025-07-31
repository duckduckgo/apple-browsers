//
//  DBPUINativeModel.swift
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

public struct DBPUIEditablePartialProfile {
    public var names: [DBPUIUserProfileName] = []
    public var birthYear: DBPUIBirthYear?
    public var addresses: [DBPUIUserProfileAddress] = []

    public init(names: [DBPUIUserProfileName] = [], birthYear: DBPUIBirthYear? = nil, addresses: [DBPUIUserProfileAddress] = []) {
        self.names = names
        self.birthYear = birthYear
        self.addresses = addresses
    }
}

public extension DBPUIEditablePartialProfile {

    init(from profile: DataBrokerProtectionProfile) {
        let names = profile.names.map { DBPUIUserProfileName(first: $0.firstName, middle: $0.middleName, last: $0.lastName, suffix: $0.suffix) }
        let addresses = profile.addresses.map { DBPUIUserProfileAddress(street: $0.street, city: $0.city, state: $0.state, zipCode: $0.zipCode) }
        let birthYear = DBPUIBirthYear(year: profile.birthYear)
        self.init(names: names, birthYear: birthYear, addresses: addresses)
    }

    mutating func addName(_ name: DBPUIUserProfileName) -> Bool {
        guard !name.requiredComponentsAreBlank() else { return false }

        // Duplicates not allowed
        guard names.firstIndex(where: { $0  == name }) == nil else { return false }

        names.append(name)
        return true
    }

    mutating func setNameAtIndex(_ nameAtIndex: DBPUINameAtIndex) -> Bool {
        guard nameAtIndex.index < names.count else {
            assertionFailure("Attempted to set name at index \(nameAtIndex.index) but only have \(names.count) names")
            return false
        }

        names[nameAtIndex.index] = nameAtIndex.name
        return true
    }

    mutating func removeNameAtIndex(_ index: Int) -> Bool {
        guard index < names.count else {
            assertionFailure("Attempted to remove name at index \(index) but only have \(names.count) names")
            return false
        }

        names.remove(at: index)
        return true
    }

    mutating func addAddress(_ address: DBPUIUserProfileAddress) -> Bool {
        guard !address.requiredComponentsAreBlank() else { return false }

        // Duplicates not allowed
        guard addresses.firstIndex(of: address) == nil else { return false }

        addresses.append(address)
        return true
    }

    mutating func setAddressAtIndex(_ addressAtIndex: DBPUIAddressAtIndex) -> Bool {
        guard addressAtIndex.index < addresses.count else {
            assertionFailure("Attempted to set address at index \(addressAtIndex.index) but only have \(addresses.count) addresses")
            return false
        }

        addresses[addressAtIndex.index] = addressAtIndex.address
        return true
    }

    mutating func removeAddressAtIndex(_ index: Int) -> Bool {
        guard index < addresses.count else {
            assertionFailure("Attempted to remove address at index \(index) but only have \(addresses.count) addresses")
            return false
        }

        addresses.remove(at: index)
        return true
    }
}

public extension DataBrokerProtectionProfile {
    init?(from profile: DBPUIEditablePartialProfile) {
        guard let birthYear = profile.birthYear else {
            return nil
        }

        let names = profile.names.map { Name(firstName: $0.first, lastName: $0.last, middleName: $0.middle, suffix: $0.suffix) }
        let addresses = profile.addresses.map { Address(city: $0.city, state: $0.state, street: $0.street, zipCode: $0.zipCode) }
        self.init(names: names, addresses: addresses, phones: [], birthYear: birthYear.year)
    }
}

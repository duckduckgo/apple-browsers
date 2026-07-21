//
//  DebugProfile.swift
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
import DataBrokerProtectionCore

/// `Codable` mirror of the debug window's form and `DataBrokerProtectionProfile`.
///
/// JSON shape:
/// ```json
/// {
///   "names": [{ "firstName": "John", "middleName": "Q", "lastName": "Smith" }],
///   "addresses": [{ "city": "Dallas", "state": "TX" }],
///   "phones": [],
///   "birthYear": 1960
/// }
/// ```
public struct DebugProfile: Codable, Sendable, Equatable {

    public struct Name: Codable, Sendable, Equatable {
        public let firstName: String
        public let middleName: String?
        public let lastName: String

        public init(firstName: String, middleName: String? = nil, lastName: String) {
            self.firstName = firstName
            self.middleName = middleName
            self.lastName = lastName
        }
    }

    public struct Address: Codable, Sendable, Equatable {
        public let city: String
        public let state: String

        public init(city: String, state: String) {
            self.city = city
            self.state = state
        }
    }

    public let names: [Name]
    public let addresses: [Address]
    public let phones: [String]
    public let birthYear: Int

    public init(names: [Name], addresses: [Address], phones: [String] = [], birthYear: Int) {
        self.names = names
        self.addresses = addresses
        self.phones = phones
        self.birthYear = birthYear
    }

    public func toDataBrokerProtectionProfile() -> DataBrokerProtectionProfile {
        DataBrokerProtectionProfile(
            names: names.map {
                .init(firstName: $0.firstName, lastName: $0.lastName, middleName: $0.middleName)
            },
            addresses: addresses.map {
                .init(city: $0.city, state: $0.state)
            },
            phones: phones,
            birthYear: birthYear
        )
    }
}

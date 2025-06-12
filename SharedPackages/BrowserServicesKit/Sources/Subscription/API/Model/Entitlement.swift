//
//  Entitlement.swift
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

public struct Entitlement: Codable, Equatable {
    public let product: ProductName

    public enum ProductName: String, Codable {
        case networkProtection = "Network Protection"
        case dataBrokerProtection = "Data Broker Protection"
        case identityTheftRestoration = "Identity Theft Restoration"
        case identityTheftRestorationGlobal = "Global Identity Theft Restoration"
        case paidAIChat = "Premium DuckChat"
        case unknown

        public init(from decoder: Decoder) throws {
            self = try Self(rawValue: decoder.singleValueContainer().decode(RawValue.self)) ?? .unknown
        }
    }
}

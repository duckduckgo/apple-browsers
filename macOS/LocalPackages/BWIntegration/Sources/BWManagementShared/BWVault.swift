//
//  BWVault.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

public struct BWVault: Equatable {
    public let id: String
    public let email: String
    public let status: Status
    public let active: Bool

    public enum Status: String {
        case locked
        case unlocked
    }

    public init(id: String, email: String, status: Status, active: Bool) {
        self.id = id
        self.email = email
        self.status = status
        self.active = active
    }

    public var locked: BWVault {
        BWVault(id: id, email: email, status: .locked, active: active)
    }

}

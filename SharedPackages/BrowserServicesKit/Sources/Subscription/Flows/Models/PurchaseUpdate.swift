//
//  PurchaseUpdate.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

public struct PurchaseUpdate: Codable, Equatable {
    let type: String
    let token: String?

    public init(type: String, token: String? = nil) {
        self.type = type
        self.token = token
    }

    public static let completed = PurchaseUpdate(type: "completed")
    public static let canceled = PurchaseUpdate(type: "canceled")
    public static let redirect = PurchaseUpdate(type: "redirect")
    public static func redirect(withToken token: String) -> Self { PurchaseUpdate(type: "redirect", token: token) }
}

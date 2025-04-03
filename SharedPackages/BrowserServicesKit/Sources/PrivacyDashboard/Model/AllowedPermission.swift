//
//  AllowedPermission.swift
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

public struct AllowedPermission: Codable {

    var key: String
    var icon: String
    var title: String
    var permission: String
    var used: Bool
    var paused: Bool
    var options: [[String: String]]

    public init(key: String,
                icon: String,
                title: String,
                permission: String,
                used: Bool,
                paused: Bool,
                options: [[String: String]] = []) {
        self.key = key
        self.icon = icon
        self.title = title
        self.permission = permission
        self.used = used
        self.paused = paused
        self.options = options
    }

}

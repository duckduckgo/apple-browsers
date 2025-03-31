//
//  SecurityOrigin.swift
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

public struct SecurityOrigin: Hashable {

    public let `protocol`: String
    public let host: String
    public let port: Int

    public init(`protocol`: String, host: String, port: Int) {
        self.`protocol` = `protocol`
        self.host = host
        self.port = port
    }

    public static let empty = SecurityOrigin(protocol: "", host: "", port: 0)

    public var isEmpty: Bool {
        self == .empty
    }

}

//
//  Redirect.swift
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

import Common
import Foundation

public enum RedirectType: Equatable {
    case client(delay: TimeInterval)
    case server
    case developer
}

public extension RedirectType {

    var isClient: Bool {
        if case .client = self { return true }
        return false
    }

}

extension RedirectType: CustomStringConvertible {
    public var description: String {
        switch self {
        case .client(delay: let delay): return "client" + (delay > 0 ? "(delay: \(delay))" : "")
        case .server: return "server"
        case .developer: return "developer"
        }
    }
}

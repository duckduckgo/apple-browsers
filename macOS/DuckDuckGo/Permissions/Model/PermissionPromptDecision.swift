//
//  PermissionPromptDecision.swift
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

/// A choice made in the Allow this visit / Always allow / Never allow dialog.
enum PermissionPromptDecision {
    case allowThisVisit
    case alwaysAllow
    case neverAllow

    var output: PermissionAuthorizationQueryOutput {
        switch self {
        case .allowThisVisit:
            return (granted: true, remember: false)
        case .alwaysAllow:
            return (granted: true, remember: true)
        case .neverAllow:
            return (granted: false, remember: true)
        }
    }
}

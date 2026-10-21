//
//  AutoconsentManagementProvider.swift
//  DuckDuckGo
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

enum AutoconsentContext: Hashable {
    case normal
    case fireMode
}

protocol AutoconsentManagementProviding {
    @MainActor func management(for context: AutoconsentContext) -> AutoconsentManaging
}

@MainActor
final class AutoconsentManagementProvider: AutoconsentManagementProviding {

    private var managements: [AutoconsentContext: AutoconsentManaging] = [:]

    func management(for context: AutoconsentContext) -> AutoconsentManaging {
        if let existing = managements[context] {
            return existing
        }

        let management = AutoconsentManagement()
        managements[context] = management
        return management
    }

}

extension Tab {
    var autoconsentContext: AutoconsentContext {
        self.fireTab ? .fireMode : .normal
    }
}

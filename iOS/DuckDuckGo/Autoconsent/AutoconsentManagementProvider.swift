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

protocol AutoconsentManagementProviding {
    @MainActor func management(fireMode: Bool) -> AutoconsentManaging
}

@MainActor
final class AutoconsentManagementProvider: AutoconsentManagementProviding {

    private let normalManagement: AutoconsentManaging
    private let fireModeManagement: AutoconsentManaging

    init() {
        self.normalManagement = AutoconsentManagement()
        self.fireModeManagement = AutoconsentManagement()
    }

    func management(fireMode: Bool) -> AutoconsentManaging {
        fireMode ? fireModeManagement : normalManagement
    }

}

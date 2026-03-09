//
//  BrowsingMenuSheetCapability.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import Core
import Foundation
import Persistence
import PrivacyConfig

protocol BrowsingMenuSheetCapable {
    var isEnabled: Bool { get }
    var mergeActionsAndBookmarks: Bool { get }
}

enum BrowsingMenuSheetCapability {
    static func create() -> BrowsingMenuSheetCapable {
        if #available(iOS 17, *) {
            return BrowsingMenuSheetDefaultCapability()
        } else {
            return BrowsingMenuSheetUnavailableCapability()
        }
    }
}

struct BrowsingMenuSheetUnavailableCapability: BrowsingMenuSheetCapable {
    let mergeActionsAndBookmarks: Bool = false
    let isEnabled = false
}

struct BrowsingMenuSheetDefaultCapability: BrowsingMenuSheetCapable {

    let mergeActionsAndBookmarks = true
    let isEnabled = true
}

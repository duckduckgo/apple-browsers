//
//  DebugScreen.swift
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

import DDGSync
import Persistence
import BrowserServicesKit
import Core
import SwiftUI
import UIKit
import SystemSettingsPiPTutorial

enum DebugScreen: Identifiable {

    struct Dependencies {

        let syncService: DDGSyncing
        let bookmarksDatabase: CoreDataDatabase
        let internalUserDecider: InternalUserDecider
        let tabManager: TabManager
        let tipKitUIActionHandler: TipKitDebugOptionsUIActionHandling
        let fireproofing: Fireproofing
        let keyValueStore: ThrowingKeyValueStoring
        let systemSettingsPiPTutorialManager: SystemSettingsPiPTutorialManaging

    }

    case controller(title: String, (Dependencies) -> UIViewController)
    case view(title: String, (Dependencies) -> any View)
    case action(title: String, (Dependencies) -> Void)

    var isAction: Bool {
        if case .action = self {
            return true
        }
        return false
    }

    var id: String {
        return title
    }

    var title: String {
        switch self {
        case .controller(let title, _):
            return title

        case .view(let title, _):
            return title

        case .action(let title, _):
            return title
        }
    }

}

//
//  DefaultBrowserAndDockPromptStoreMigrator.swift
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

import Foundation

protocol DefaultBrowserAndDockPromptStoreMigrating: AnyObject {
    func migrateIfNeeded()
}

final class DefaultBrowserAndDockPromptStoreMigrator: DefaultBrowserAndDockPromptStoreMigrating {
    private let oldStore: DefaultBrowserAndDockPromptLegacyStoring
    private let newStore: DefaultBrowserAndDockPromptStorage
    private let dateProvider: () -> Date

    init(
        oldStore: DefaultBrowserAndDockPromptLegacyStoring,
        newStore: DefaultBrowserAndDockPromptStorage,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.oldStore = oldStore
        self.newStore = newStore
        self.dateProvider = dateProvider
    }

    func migrateIfNeeded() {
        // If the user saw a prompt during the banner vs popover experiment we assume they saw the popover.
        // In this case we save the popover seen date to now so the users will see the banner next when the time comes.
        if oldStore.didShowPrompt() && !newStore.hasSeenPopover {
            newStore.popoverShownDate = dateProvider().timeIntervalSince1970
            // Re-set the value to false to avoid migrating every time the functions gets called
            oldStore.setPromptShown(false)
        }
    }
}

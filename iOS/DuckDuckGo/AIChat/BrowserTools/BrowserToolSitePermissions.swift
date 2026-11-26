//
//  BrowserToolSitePermissions.swift
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

import AIChat
import Combine
import SitePermissions

@MainActor
final class BrowserToolSitePermissions: BrowserToolPermissionStoring {
    private let store: SitePermissionsStore

    let appliesDecisionsToAutoTools = true

    init(store: SitePermissionsStore) {
        self.store = store
    }

    var changesPublisher: AnyPublisher<Void, Never> {
        store.browserToolChangesPublisher
    }

    var storedDecisions: [String: BrowserToolPermissionState] {
        store.browserToolDecisions.compactMapValues { BrowserToolPermissionState(rawValue: $0.rawValue) }
    }

    func state(forToolNamed name: String) -> BrowserToolPermissionState? {
        store.browserToolDecision(for: name).flatMap { BrowserToolPermissionState(rawValue: $0.rawValue) }
    }

    func setState(_ state: BrowserToolPermissionState?, forToolNamed name: String) {
        let decision = state.flatMap { SitePermissionDecision(rawValue: $0.rawValue) }
        store.setBrowserToolDecision(decision, for: name)
    }

    func clearAll() {
        store.resetBrowserToolDecisions()
    }
}

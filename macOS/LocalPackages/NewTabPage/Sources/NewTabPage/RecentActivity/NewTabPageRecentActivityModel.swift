//
//  NewTabPageRecentActivityModel.swift
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

import AppKit
import Combine
import Common
import Foundation
import os.log
import Persistence
import PrivacyStats

/**
 * This protocol describes Recent Activity widget data source.
 *
 * It allows subscribing to history updates as well as triggering activity calculation on demand.
 */
public protocol NewTabPageRecentActivityProviding: AnyObject {
    /**
     * This function should return `DomainActivity` array based on current state of browser history.
     */
    func refreshActivity() -> [NewTabPageDataModel.DomainActivity]

    /**
     * This publisher should publish changes to `DomainActivity` array every time browser history is updated.
     */
    var activityPublisher: AnyPublisher<[NewTabPageDataModel.DomainActivity], Never> { get }
}

/**
 * This protocol describes objects that can return Recent Activity widget visibility.
 *
 * It's implemented by `NewTabPageProtectionsReportModel` and it's used to limit unnecessary
 * data processing when the widget is not present on New Tab Page.
 */
public protocol NewTabPageRecentActivityVisibilityProviding: AnyObject {
    /**
     * This property should return `true` if Recent Activity widget is visible on the New Tab Page.
     */
    var isRecentActivityVisible: Bool { get }
}

public final class NewTabPageRecentActivityModel {

    let activityProvider: NewTabPageRecentActivityProviding
    let actionsHandler: RecentActivityActionsHandling

    public init(activityProvider: NewTabPageRecentActivityProviding, actionsHandler: RecentActivityActionsHandling) {
        self.activityProvider = activityProvider
        self.actionsHandler = actionsHandler
    }

    // MARK: - Actions

    @MainActor func addFavorite(_ url: String) {
        guard let url = URL(string: url), url.isValid else { return }
        actionsHandler.addFavorite(url)
    }

    @MainActor func removeFavorite(_ url: String) {
        guard let url = URL(string: url), url.isValid else { return }
        actionsHandler.removeFavorite(url)
    }

    @MainActor func confirmBurn(_ url: String) async -> Bool {
        guard let url = URL(string: url), url.isValid else { return false }
        return await actionsHandler.confirmBurn(url)
    }

    @MainActor func open(_ url: String, sender: LinkOpenSender, target: LinkOpenTarget, sourceWindow: NSWindow?) {
        guard let url = URL(string: url), url.isValid else { return }
        actionsHandler.openHistoryEntry(url, sender: sender, target: target, sourceWindow: sourceWindow)
    }
}

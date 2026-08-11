//
//  EventHubTabExtension.swift
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

import BrowserServicesKit
import Combine
import EventHub
import Foundation
import Navigation
import os.log

/// Bridges this tab's lifecycle into `EventHub`: owns the tab's `WebEventsHandler` (constructed with
/// this tab's ID baked directly into its `tabIDProvider`, mirroring `WebNotificationsTabExtension`'s
/// handling of `WebNotificationsHandler`) and registers it with the content scope user script when
/// available, reports navigation starts, and reports tab closure via `deinit` (Tab Extensions live
/// exactly as long as their owning `Tab`).
final class EventHubTabExtension {

    private let tabID: EventHubTabID
    private let eventHub: EventHubManaging
    private let handler: WebEventsHandler
    private var cancellables = Set<AnyCancellable>()

    init(tabID: String,
         eventHub: EventHubManaging,
         contentScopeUserScriptPublisher: some Publisher<ContentScopeUserScript, Never>) {
        let eventHubTabID = EventHubTabID(rawValue: UUID(uuidString: tabID) ?? UUID())
        self.tabID = eventHubTabID
        self.eventHub = eventHub
        self.handler = WebEventsHandler(manager: eventHub, tabIDProvider: { _ in eventHubTabID })

        contentScopeUserScriptPublisher.sink { [weak self] contentScopeUserScript in
            guard let handler = self?.handler else { return }
            contentScopeUserScript.registerSubfeature(delegate: handler)
        }.store(in: &cancellables)
    }

    deinit {
        Logger.eventHub.debug("Tab closed — reporting to EventHub")
        eventHub.onTabClosed(tabID: tabID)
    }
}

/// Public surface of `EventHubTabExtension`. Empty beyond `NavigationResponder` — the extension
/// exposes no API of its own — but it must be a distinct protocol (not the concrete type): the
/// `TabExtensionsBuilder.resolve` overload for `where PublicProtocol == T` deliberately traps.
protocol EventHubTabExtensionProtocol: AnyObject, NavigationResponder {}

extension EventHubTabExtension: TabExtension, EventHubTabExtensionProtocol {
    func getPublicProtocol() -> EventHubTabExtensionProtocol { self }
}

extension EventHubTabExtension: NavigationResponder {
    func didStart(_ navigation: Navigation) {
        Logger.eventHub.debug("Tab navigation started — reporting to EventHub")
        eventHub.onNavigationStarted(tabID: tabID, url: navigation.url.absoluteString)
    }
}

extension TabExtensions {
    /// Resolves the per-tab EventHub extension. Also how `Tab` reaches it (via its `dynamicMember`
    /// subscript) to register it as a navigation responder in `setupNavigationDelegate`.
    var eventHub: EventHubTabExtensionProtocol? {
        resolve(EventHubTabExtension.self)
    }
}

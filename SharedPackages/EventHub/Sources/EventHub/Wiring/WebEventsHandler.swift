//
//  WebEventsHandler.swift
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
import WebKit
import UserScript

/// Routes inbound content-scope-scripts `webEvent` messages to `EventHubManaging`: extracts the
/// event payload (`{ type, data }`) and forwards only events whose `type` is present and non-empty.
/// The originating tab is supplied by the caller (the wiring layer, out of scope here) rather than
/// read from the message itself.
public final class WebEventsHandler: Subfeature {
    public let featureName = "webEvents"
    public let messageOriginPolicy: MessageOriginPolicy = .all
    public var broker: UserScriptMessageBroker?

    private let manager: EventHubManaging
    private let tabIDProvider: (WKScriptMessage) -> EventHubTabID

    public init(manager: EventHubManaging, tabIDProvider: @escaping (WKScriptMessage) -> EventHubTabID) {
        self.manager = manager
        self.tabIDProvider = tabIDProvider
    }

    public func handler(forMethodNamed methodName: String) -> Handler? {
        guard methodName == "webEvent" else { return nil }
        return { [weak self] params, original in
            guard let self,
                  let dict = params as? [String: Any],
                  let type = dict["type"] as? String, !type.isEmpty else {
                return nil
            }
            self.manager.handleWebEvent(dict, tabID: self.tabIDProvider(original))
            return nil
        }
    }
}

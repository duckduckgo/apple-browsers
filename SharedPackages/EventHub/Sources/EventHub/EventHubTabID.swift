//
//  EventHubTabID.swift
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

/// Identifies a browser tab for EventHub's per-tab web-event dedup. `.empty` stands in for "no tab"
/// (used by native/aggregated events, which have no page/tab lifecycle to dedup against).
public struct EventHubTabID: Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    public static func new() -> EventHubTabID { EventHubTabID() }

    public static let empty = EventHubTabID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)
}

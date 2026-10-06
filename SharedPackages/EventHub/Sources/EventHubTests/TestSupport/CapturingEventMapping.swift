//
//  CapturingEventMapping.swift
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
import Common
@testable import EventHub

/// Captures the debug events a component fires, so tests can assert on the event itself rather than on
/// whatever a real pixel implementation would do with it.
final class CapturingEventMapping {
    private(set) var fired: [EventHubDebugEvent] = []
    private(set) var errors: [Error?] = []

    /// The mapping to inject. Holds this capture weakly, so a test can keep reading `fired` for as long
    /// as it holds the capture, regardless of what owns the mapping.
    lazy var eventMapping: EventMapping<EventHubDebugEvent> = EventMapping { [weak self] event, error, _, _ in
        self?.fired.append(event)
        self?.errors.append(error)
    }
}

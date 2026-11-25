//
//  MockAutoconsentStatsEventMapping.swift
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

import Common
import Foundation
@testable import AutoconsentStats

final class AutoconsentStatsEvents: Sendable {
    private let recorded = Locked(wrappedValue: [AutoconsentStatsError]())

    var events: [AutoconsentStatsError] { recorded.wrappedValue }

    func makeMapping() -> EventMapping<AutoconsentStatsError> {
        EventMapping { [recorded] event, _, _, _ in
            // The stats actor is the only writer.
            recorded.wrappedValue.append(event)
        }
    }
}

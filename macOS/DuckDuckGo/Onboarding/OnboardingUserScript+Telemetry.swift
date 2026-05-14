//
//  OnboardingUserScript+Telemetry.swift
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

extension OnboardingUserScript {

    enum TelemetryEvent: Equatable {
        case rowShown(OnboardingRow)
        case rowSkipped(OnboardingRow)
        case dockInstructionsShown
        case duckPlayerToggled
    }
}

extension OnboardingUserScript.TelemetryEvent: Decodable {

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let payload = try container.nestedContainer(keyedBy: CodingKeys.self, forKey: .payload)
        let eventName = try payload.decode(EventName.self, forKey: .name)

        switch eventName {
        case .rowShown:
            let row = try Self.decodeOnboardingRow(from: payload)
            self = .rowShown(row)
        case .rowSkipped:
            let row = try Self.decodeOnboardingRow(from: payload)
            self = .rowSkipped(row)
        case .dockInstructionsShown:
            self = .dockInstructionsShown
        case .duckPlayerToggled:
            self = .duckPlayerToggled
        }
    }
}

private extension OnboardingUserScript.TelemetryEvent {

    enum CodingKeys: String, CodingKey {
        case payload = "attributes"
        case name
        case value
    }

    enum EventName: String, Decodable {
        case rowShown = "row_shown"
        case rowSkipped = "row_skipped"
        case dockInstructionsShown = "dock_instructions_shown"
        case duckPlayerToggled = "duck_player_toggled"
    }

    private static func decodeOnboardingRow(from container: KeyedDecodingContainer<CodingKeys>) throws -> OnboardingRow {
        return try container.decode(OnboardingRow.self, forKey: .value)
    }
}
